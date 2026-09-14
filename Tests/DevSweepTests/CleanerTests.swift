import XCTest
@testable import DevSweep

/// Deletion runs for real here, inside a throwaway folder in the home directory
/// (SafeDelete refuses anything outside it).
final class CleanerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        TestSupport.useEnglish()
        root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".devsweep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ name: String, kilobytes: Int = 1) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: kilobytes * 1024).write(to: url)
        return url
    }

    private func target(_ paths: [URL], method: CleanMethod = .delete, stop: [String] = []) -> StorageTarget {
        StorageTarget(
            id: "t", stack: StackInfo(id: "s", name: "S", icon: "gear", order: 1), title: "T", detail: "",
            risk: .safe, paths: paths, method: method, stopProcesses: stop
        )
    }

    func testDeleteRemovesFilesAndFolders() throws {
        let file = try makeFile("cache/file.bin")
        let folder = root.appendingPathComponent("cache")
        XCTAssertEqual(Cleaner.clean(target([folder])), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testDeletingSomethingThatIsAlreadyGoneIsNotAnError() {
        XCTAssertEqual(Cleaner.clean(target([root.appendingPathComponent("missing")])), [])
    }

    func testPathsOutsideTheHomeFolderAreRefused() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("devsweep-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let errors = Cleaner.clean(target([outside]))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Blocked for safety"), errors[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testReadOnlyTreesAreStillRemoved() throws {
        // Go's module cache marks everything read-only; the cleaner chmods and retries.
        let file = try makeFile("readonly/pkg/file.bin")
        let folder = root.appendingPathComponent("readonly")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: file.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: file.path)

        XCTAssertEqual(Cleaner.clean(target([folder])), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testCommandsRunAndCanBeFollowedByDeletion() throws {
        let marker = root.appendingPathComponent("ran.txt")
        let folder = try makeFile("data/file.bin").deletingLastPathComponent()

        let errors = Cleaner.clean(target(
            [folder],
            method: .commands([["/bin/sh", "-c", "echo done > \(marker.path)"]], thenDelete: true)
        ))
        XCTAssertEqual(errors, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testFailingCommandsAreReportedAndPathsSurvive() throws {
        let folder = try makeFile("keep/file.bin").deletingLastPathComponent()
        let errors = Cleaner.clean(target([folder], method: .commands([["/bin/ls", "/definitely/not/here"]], thenDelete: false)))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasPrefix("/bin/ls"), errors[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testSizeCalculatorMeasuresOnlyExistingPaths() throws {
        let big = try makeFile("sized/big.bin", kilobytes: 200)
        let missing = root.appendingPathComponent("sized/missing.bin")

        let size = SizeCalculator.size(of: [big, missing])
        XCTAssertGreaterThanOrEqual(size, 200 * 1024)
        XCTAssertLessThan(size, 400 * 1024)
        XCTAssertEqual(SizeCalculator.size(of: []), 0)
        XCTAssertEqual(SizeCalculator.size(of: [missing]), 0)
    }

    func testSafeDeleteAllowsThrowawayFoldersInsideHome() {
        XCTAssertTrue(SafeDelete.isAllowed(root))
        XCTAssertNil(SafeDelete.remove(root.appendingPathComponent("not-there")))
    }
}

/// The cleanup log is what makes "something on my machine broke after a clean" answerable.
final class CleanupLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ item: String, paths: [String] = ["/p/one"], errors: [String] = []) -> CleanupLog.Entry {
        CleanupLog.Entry(date: Date(), item: item, risk: "redownload", method: "delete", paths: paths, errors: errors)
    }

    func testEntriesAppendAndReadBack() {
        CleanupLog.record(entry("pub-cache", paths: ["/p/hosted/http-1.2.0"]), in: directory)
        CleanupLog.record(entry("cocoapods-cache", errors: ["boom"]), in: directory)

        let entries = CleanupLog.read(in: directory)
        XCTAssertEqual(entries.map(\.item), ["pub-cache", "cocoapods-cache"])
        XCTAssertEqual(entries.first?.paths, ["/p/hosted/http-1.2.0"])
        XCTAssertEqual(entries.last?.errors, ["boom"])
    }

    func testLogStaysBounded() {
        for index in 0..<520 {
            CleanupLog.record(entry("item-\(index)"), in: directory)
        }
        let entries = CleanupLog.read(in: directory)
        XCTAssertEqual(entries.count, 500)
        XCTAssertEqual(entries.last?.item, "item-519", "the newest entries are the ones kept")
    }

    func testCleaningRecordsWhatItTouched() throws {
        let victim = directory.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)

        let target = StorageTarget(
            id: "test-item", stack: StackInfo(id: "s", name: "S", icon: "gear", order: 1),
            title: "Test", detail: "", risk: .safe, paths: [victim]
        )
        _ = Cleaner.clean(target)

        let entries = CleanupLog.read()
        XCTAssertEqual(entries.last?.item, "test-item")
        XCTAssertEqual(entries.last?.paths, [victim.path])
    }
}

/// Shell configuration is never a cache. These paths must be unreachable no matter what a
/// stack file asks for, because a broken shell is not something a "clean" should ever cause.
final class ShellConfigProtectionTests: XCTestCase {
    private func home(_ relative: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relative)
    }

    func testShellConfigurationIsNeverDeletable() {
        let forbidden = [
            ".oh-my-zsh", ".oh-my-zsh/cache", ".oh-my-zsh/custom/themes", ".zshrc", ".zshenv",
            ".zprofile", ".zcompdump-somehost-5.9", ".zcompdump-somehost-5.9.zwc", ".p10k.zsh",
            ".bashrc", ".bash_profile", ".gitconfig", ".netrc", ".poshthemes/theme.omp.json",
        ]
        for path in forbidden {
            XCTAssertFalse(SafeDelete.isAllowed(home(path)), "\(path) must never be deletable")
        }
    }

    func testOrdinaryCachesAreStillDeletable() {
        for path in [".pub-cache/hosted/pub.dev/http-1.2.0", ".gradle/caches/build-cache-1", ".npm/_cacache"] {
            XCTAssertTrue(SafeDelete.isAllowed(home(path)), "\(path) is a cache and must stay cleanable")
        }
    }
}
