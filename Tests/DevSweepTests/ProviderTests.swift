import XCTest
@testable import DevSweep

/// Providers point at real tool layouts, so each test builds a throwaway one and
/// tells the provider to look there.
final class ProviderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        TestSupport.useEnglish()
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func context(projects: [DevProject] = [], options: [String: [String]] = [:], inactiveDays: Int = 21) -> ProviderContext {
        ProviderContext(
            prefs: PrefsSnapshot(
                notifications: true, suggestStorageGB: 2, notifyStorageGB: 5, suggestLimboMB: 150,
                notifyRAMMB: 500, lowDiskGB: 30, inactiveProjectDays: inactiveDays, artifactAgeDays: 7,
                artifactsToTrash: true, projectRoots: []
            ),
            projects: projects,
            inactiveCutoff: Date().addingTimeInterval(-Double(inactiveDays) * 86_400),
            options: options
        )
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: FVM

    func testFvmListsEveryVersionExceptTheDefaultAndFlagsUsage() throws {
        let versions = root.appendingPathComponent("versions")
        for version in ["3.1.0", "3.2.0", "3.9.0"] {
            try makeDirectory(versions.appendingPathComponent(version))
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("default"), withDestinationURL: versions.appendingPathComponent("3.9.0")
        )

        let activeProject = root.appendingPathComponent("active-app")
        try makeDirectory(activeProject)
        try #"{"flutter": "3.1.0"}"#.write(to: activeProject.appendingPathComponent(".fvmrc"), atomically: true, encoding: .utf8)

        setenv("FVM_CACHE_PATH", root.path, 1)
        defer { unsetenv("FVM_CACHE_PATH") }

        let projects = [DevProject(url: activeProject, markers: ["pubspec.yaml"], lastActivity: Date())]
        let results = StorageProviders.run("fvm-versions", context: context(projects: projects))
            .filter { $0.paths.first?.path.hasPrefix(root.path) == true }

        XCTAssertEqual(Set(results.compactMap(\.key)), ["3.1.0", "3.2.0"], "the default version is never offered")

        let used = try XCTUnwrap(results.first { $0.key == "3.1.0" })
        XCTAssertEqual(used.autoSuggest, false, "a version an active project pins is listed but not suggested")
        XCTAssertEqual(used.vars["usage"], "Used by active-app.")
        XCTAssertEqual(used.vars["version"], "3.1.0")
        XCTAssertEqual(used.stopProcesses.first, versions.appendingPathComponent("3.1.0").path + "/")

        let unknown = try XCTUnwrap(results.first { $0.key == "3.2.0" })
        XCTAssertEqual(
            unknown.autoSuggest, false,
            "no pin found is not evidence of disuse: the project may sit outside the scanned roots"
        )
        XCTAssertEqual(
            unknown.vars["usage"],
            "No project under your scanned folders pins it. Check before removing: projects outside those folders are invisible here."
        )
    }

    func testFvmMarksVersionsUsedOnlyByInactiveProjects() throws {
        let versions = root.appendingPathComponent("versions")
        try makeDirectory(versions.appendingPathComponent("2.0.0"))
        let stale = root.appendingPathComponent("stale-app")
        try makeDirectory(stale)
        try #"{"flutterSdkVersion": "2.0.0"}"#.write(
            to: stale.appendingPathComponent(".fvmrc"), atomically: true, encoding: .utf8
        )
        setenv("FVM_CACHE_PATH", root.path, 1)
        defer { unsetenv("FVM_CACHE_PATH") }

        let projects = [DevProject(url: stale, markers: [], lastActivity: Date().addingTimeInterval(-90 * 86_400))]
        let result = try XCTUnwrap(
            StorageProviders.run("fvm-versions", context: context(projects: projects))
                .first { $0.key == "2.0.0" && $0.paths.first?.path.hasPrefix(root.path) == true }
        )
        XCTAssertEqual(result.autoSuggest, true)
        XCTAssertEqual(result.vars["usage"], "Used by stale-app (inactive).")
    }

    func testFvmReadsAPinMadeOnlyOfTheSdkSymlink() throws {
        let versions = root.appendingPathComponent("versions")
        try makeDirectory(versions.appendingPathComponent("3.38.0"))
        try makeDirectory(versions.appendingPathComponent("3.44.0"))

        // FVM 2.x and plain `fvm use` leave no .fvmrc, only .fvm/flutter_sdk.
        let project = root.appendingPathComponent("legacy-app")
        try makeDirectory(project.appendingPathComponent(".fvm"))
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent(".fvm/flutter_sdk"),
            withDestinationURL: versions.appendingPathComponent("3.38.0")
        )
        XCTAssertEqual(StorageProviders.fvmVersion(of: project), "3.38.0")

        setenv("FVM_CACHE_PATH", root.path, 1)
        defer { unsetenv("FVM_CACHE_PATH") }

        let projects = [DevProject(url: project, markers: ["pubspec.yaml"], lastActivity: Date())]
        let results = StorageProviders.run("fvm-versions", context: context(projects: projects))
            .filter { $0.paths.first?.path.hasPrefix(root.path) == true }

        let pinned = try XCTUnwrap(results.first { $0.key == "3.38.0" })
        XCTAssertEqual(pinned.autoSuggest, false, "the SDK an active project uses must never be suggested")
        XCTAssertEqual(pinned.vars["usage"], "Used by legacy-app.")
    }

    // MARK: Pub cache

    func testPubCacheKeepsWhatGloballyActivatedPackagesNeed() throws {
        let hosted = root.appendingPathComponent("hosted/pub.dev")
        let hashes = root.appendingPathComponent("hosted-hashes/pub.dev")
        try makeDirectory(hosted)
        try makeDirectory(hashes)
        for package in ["melos-8.6.0", "pub_semver-2.2.1", "http-1.2.0"] {
            try makeDirectory(hosted.appendingPathComponent(package))
            try "sha".write(to: hashes.appendingPathComponent(package + ".sha256"), atomically: true, encoding: .utf8)
        }

        let melos = root.appendingPathComponent("global_packages/melos")
        try makeDirectory(melos)
        try """
        # Generated by pub
        packages:
          melos:
            dependency: "direct main"
            description:
              name: melos
              url: "https://pub.dev"
            source: hosted
            version: "8.6.0"
          pub_semver:
            dependency: transitive
            description:
              name: pub_semver
              url: "https://pub.dev"
            source: hosted
            version: "2.2.1"
        """.write(to: melos.appendingPathComponent("pubspec.lock"), atomically: true, encoding: .utf8)

        let paths = StorageProviders.run("pub-cache-unused", context: context(options: ["root": [root.path]]))
            .flatMap(\.paths).map(\.path)

        XCTAssertTrue(paths.contains(hosted.appendingPathComponent("http-1.2.0").path))
        XCTAssertTrue(
            paths.contains(hashes.appendingPathComponent("http-1.2.0.sha256").path),
            "the hash file goes with the package, otherwise pub reports a corrupt cache"
        )
        for kept in ["melos-8.6.0", "pub_semver-2.2.1"] {
            XCTAssertFalse(
                paths.contains { $0.hasSuffix(kept) || $0.hasSuffix(kept + ".sha256") },
                "\(kept) is needed by an activated global package"
            )
        }
    }

    func testPubLockParsingIgnoresNestedVersionLikeKeys() {
        let locked = StorageProviders.lockedPackages("""
        packages:
          args:
            dependency: transitive
            description:
              name: args
              sha256: "d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04"
              url: "https://pub.dev"
            source: hosted
            version: "2.7.0"
        sdks:
          dart: ">=3.6.0 <4.0.0"
        """)
        XCTAssertEqual(locked, ["args-2.7.0"])
    }

    // MARK: Android

    func testAndroidReturnsSystemImagesNoAvdUses() throws {
        let image = root.appendingPathComponent("system-images/android-34/google_apis/arm64-v8a")
        try makeDirectory(image)

        let results = StorageProviders.run("android-unused-system-images", context: context(options: ["sdk": [root.path]]))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].paths.map(\.standardizedFileURL.path), [image.standardizedFileURL.path])
    }

    func testAndroidReturnsNothingWhenTheSdkIsMissing() {
        let results = StorageProviders.run(
            "android-unused-system-images",
            context: context(options: ["sdk": [root.appendingPathComponent("missing").path]])
        )
        XCTAssertEqual(results.first?.paths ?? [], [])
    }

    // MARK: nvm

    func testNvmKeepsTheDefaultAliasAndTheNewestVersion() throws {
        let nodes = root.appendingPathComponent("versions/node")
        for version in ["v18.19.0", "v20.11.0", "v22.3.0"] {
            try makeDirectory(nodes.appendingPathComponent(version))
        }
        try makeDirectory(root.appendingPathComponent("alias"))
        try "18\n".write(to: root.appendingPathComponent("alias/default"), atomically: true, encoding: .utf8)

        let results = StorageProviders.run("nvm-non-default-versions", context: context(options: ["root": [root.path]]))
        XCTAssertEqual(results.first?.paths.map(\.lastPathComponent), ["v20.11.0"], "v18 is the alias, v22 is the newest")
    }

    func testNvmWithoutAnAliasKeepsOnlyTheNewest() throws {
        let nodes = root.appendingPathComponent("versions/node")
        for version in ["v18.19.0", "v22.3.0"] { try makeDirectory(nodes.appendingPathComponent(version)) }

        let results = StorageProviders.run("nvm-non-default-versions", context: context(options: ["root": [root.path]]))
        XCTAssertEqual(results.first?.paths.map(\.lastPathComponent), ["v18.19.0"])
    }

    // MARK: Simulators

    func testUnavailableSimulatorsProviderAnswersWithoutFailing() {
        // Depends on whether Xcode is installed; only the shape is guaranteed.
        let results = StorageProviders.run("xcode-unavailable-simulators", context: context())
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].paths.allSatisfy { $0.path.contains("CoreSimulator") })
    }

    func testEveryAdvertisedProviderAnswers() {
        for name in StorageProviders.names {
            XCTAssertNoThrow(StorageProviders.run(name, context: context()), name)
        }
    }
}
