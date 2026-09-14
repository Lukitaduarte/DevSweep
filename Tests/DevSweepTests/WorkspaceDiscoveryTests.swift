import XCTest
@testable import DevSweep

/// The first-run folder list decides what later looks abandoned, so what goes into it matters.
final class WorkspaceDiscoveryTests: XCTestCase {
    private var home: URL!
    private var support: URL!

    override func setUpWithError() throws {
        home = try TestSupport.temporaryDirectory()
        support = home.appendingPathComponent("Library/Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeDirectory(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(relative), withIntermediateDirectories: true
        )
    }

    private func roots(maximum: Int = 8) -> [String] {
        WorkspaceDiscovery.suggestedRoots(home: home.path, applicationSupport: support.path, maximum: maximum)
    }

    func testOnlyConventionalFoldersThatExistAreOffered() throws {
        try makeDirectory("IdeaProjects")
        try makeDirectory("StudioProjects")
        XCTAssertEqual(roots(), ["~/StudioProjects", "~/IdeaProjects"], "in the order the list declares them")
    }

    func testAFileNamedLikeAWorkspaceIsNotAFolder() throws {
        try "not a folder".write(to: home.appendingPathComponent("code"), atomically: true, encoding: .utf8)
        XCTAssertTrue(roots().isEmpty)
    }

    func testFoldersTheEditorHasOpenAreDiscovered() throws {
        try makeDirectory("unusual-place/checkout-app")
        let storage = support.appendingPathComponent("Cursor/User/globalStorage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let project = home.appendingPathComponent("unusual-place/checkout-app").path
        try """
        {"backupWorkspaces": {"folders": [{"folderUri": "file://\(project)"}]},
         "windowsState": {"lastActiveWindow": {"folder": "file://\(project)"}}}
        """.write(to: storage.appendingPathComponent("storage.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(roots(), ["~/unusual-place"], "the parent of an opened project, not the project itself")
    }

    func testJetBrainsRecentProjectsAreDiscovered() throws {
        try makeDirectory("clients/app")
        let options = support.appendingPathComponent("Google/AndroidStudio2025.1/options")
        try FileManager.default.createDirectory(at: options, withIntermediateDirectories: true)
        try #"<entry key="$USER_HOME$/clients/app" value="..." />"#
            .write(to: options.appendingPathComponent("recentProjects.xml"), atomically: true, encoding: .utf8)

        XCTAssertEqual(roots(), ["~/clients"])
    }

    func testAFolderAlreadyCoveredIsNotAddedTwice() throws {
        try makeDirectory("Projects/team/app")
        let storage = support.appendingPathComponent("Code/User/globalStorage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let project = home.appendingPathComponent("Projects/team/app").path
        try #"{"backupWorkspaces": {"folders": [{"folderUri": "file://\#(project)"}]}}"#
            .write(to: storage.appendingPathComponent("storage.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(roots(), ["~/Projects"], "~/Projects/team is already inside ~/Projects")
    }

    func testTheHomeFolderItselfIsNeverOffered() throws {
        try makeDirectory("loose-app")
        let storage = support.appendingPathComponent("Code/User/globalStorage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let project = home.appendingPathComponent("loose-app").path
        try #"{"backupWorkspaces": {"folders": [{"folderUri": "file://\#(project)"}]}}"#
            .write(to: storage.appendingPathComponent("storage.json"), atomically: true, encoding: .utf8)

        XCTAssertTrue(roots().isEmpty, "scanning the whole home folder is not a sane default")
    }

    func testOnlyFolderKeysCount() {
        let json = try! JSONSerialization.jsonObject(with: Data("""
        {"someFile": "file:///p/a/file.txt", "folder": "file:///p/app", "other": "not a uri"}
        """.utf8))
        XCTAssertEqual(WorkspaceDiscovery.folderURIs(in: json), ["file:///p/app"])
    }

    func testAnEditorFolderSurvivesWhenConventionalOnesFillTheList() throws {
        for name in ["Project", "Projects", "Developer", "dev", "code", "workspace", "src", "work"] {
            try makeDirectory(name)
        }
        try makeDirectory("unusual-place/checkout-app")
        let storage = support.appendingPathComponent("Code/User/globalStorage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let project = home.appendingPathComponent("unusual-place/checkout-app").path
        try #"{"backupWorkspaces": {"folders": [{"folderUri": "file://\#(project)"}]}}"#
            .write(to: storage.appendingPathComponent("storage.json"), atomically: true, encoding: .utf8)

        let found = roots()
        XCTAssertEqual(found.count, 8)
        XCTAssertEqual(found.first, "~/unusual-place", "the folder actually in use outranks a convention")
    }

    func testAFolderLinkingOutsideHomeIsNotOffered() throws {
        let outside = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("code"), withDestinationURL: outside
        )
        XCTAssertTrue(roots().isEmpty, "DevSweep could never clean there, so it must not offer it")
    }

    func testOnlyRootsThatExistCountAsConfirmable() throws {
        try makeDirectory("Projects")
        let typed = "~/Projects\n~/Porjects\n\n  \n"
        XCTAssertEqual(
            WorkspaceDiscovery.existingRoots(in: typed, home: home.path), ["~/Projects"],
            "a typo must not be enough to turn recommendations on"
        )
    }

    func testTheListIsCapped() throws {
        for name in ["Project", "Projects", "Developer", "dev", "code", "workspace", "src", "work", "git"] {
            try makeDirectory(name)
        }
        XCTAssertEqual(roots(maximum: 4).count, 4)
    }
}
