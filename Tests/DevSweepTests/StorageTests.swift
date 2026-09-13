import XCTest
@testable import DevSweep

final class SafeDeleteTests: XCTestCase {
    private let home = NSHomeDirectory()

    func testRejectsHomeAndWellKnownFolders() {
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: home)))
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/Documents")))
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/Library/Caches")))
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/Library/Developer")))
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: "/Applications/Xcode.app")))
        XCTAssertFalse(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/.gradle/../Documents")))
    }

    func testAllowsCachesInsideHome() {
        XCTAssertTrue(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/Library/Caches/go-build")))
        XCTAssertTrue(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/.gradle/caches/8.12")))
        XCTAssertTrue(SafeDelete.isAllowed(URL(fileURLWithPath: home + "/Downloads/app-release.apk")))
    }
}

final class PathTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func make(_ names: [String]) throws {
        for name in names {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    func testGlobWildcardsAndExclusions() throws {
        try make(["Runner-abc/Index.noindex", "Runner-abc/Build", "Pods-xyz/Build", "ModuleCache.noindex"])
        XCTAssertEqual(PathGlob.expand(root.path + "/*/Index.noindex").map(\.lastPathComponent), ["Index.noindex"])
        XCTAssertEqual(PathGlob.expand(root.path + "/Runner-*/*", excluding: ["Index.noindex"]).map(\.lastPathComponent), ["Build"])
        XCTAssertTrue(PathGlob.expand(root.path + "/nothing-*/x").isEmpty)
    }

    func testBracesAndEnvironmentDefaults() {
        XCTAssertEqual(PathTemplate.braces("/a/{x,y}/{1,2}"), ["/a/x/1", "/a/x/2", "/a/y/1", "/a/y/2"])
        XCTAssertEqual(PathTemplate.substituteEnvironment("${GOPATH:-~/go}/pkg", environment: [:]), "~/go/pkg")
        XCTAssertEqual(PathTemplate.substituteEnvironment("${GOPATH:-~/go}/pkg", environment: ["GOPATH": "/w"]), "/w/pkg")
    }

    func testKeepNewestByVersionGroupsVariants() throws {
        try make(["gradle-8.12-all", "gradle-8.14-all", "gradle-8.14-bin", "gradle-8.9-bin"])
        let old = PathResolver.resolve(PathSpec(glob: root.path + "/gradle-*", keepNewest: 1, sortBy: "version"))
        XCTAssertEqual(Set(old.map(\.lastPathComponent)), ["gradle-8.12-all", "gradle-8.9-bin"])

        let newest = PathResolver.resolve(PathSpec(glob: root.path + "/gradle-*", onlyNewest: 1, sortBy: "version"))
        XCTAssertEqual(Set(newest.map(\.lastPathComponent)), ["gradle-8.14-all", "gradle-8.14-bin"])
    }

    func testVersionPatternCaptureGroup() throws {
        try make(["toolchain@v0.0.1-go1.24.3.darwin-arm64", "toolchain@v0.0.1-go1.25.1.darwin-arm64"])
        let spec = PathSpec(glob: root.path + "/toolchain@*", keepNewest: 1, sortBy: "version", versionPattern: #"go(\d+(?:\.\d+)+)"#)
        XCTAssertEqual(PathResolver.resolve(spec).map(\.lastPathComponent), ["toolchain@v0.0.1-go1.24.3.darwin-arm64"])
    }

    func testByteSizeParsing() {
        XCTAssertEqual(ByteSize.parse("500MB"), 500_000_000)
        XCTAssertEqual(ByteSize.parse("1.5 GB"), 1_500_000_000)
        XCTAssertEqual(ByteSize.parse("42"), 42)
        XCTAssertNil(ByteSize.parse("lots"))
    }
}
