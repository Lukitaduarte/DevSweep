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
