import XCTest
@testable import DevSweep

/// Keeps personal data out of the open-source repository.
final class PrivacyTests: XCTestCase {
    private let skippedFolders: Set<String> = [".build", "build", ".git", ".swiftpm"]

    func testRepositoryContainsNoPersonalPathsOrEmails() throws {
        // Built from pieces so this file doesn't flag itself.
        var needles = ["/Users" + "/", "/home" + "/"]
        if ProcessInfo.processInfo.environment["CI"] == nil {
            needles += [NSHomeDirectory(), NSUserName()].filter { $0.count >= 4 }
        }
        // Domain labels must start with a letter, so version strings like toolchain@v0.0.1-go1.24.darwin don't match.
        let email = try NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)*\.[A-Za-z]{2,}\b"#)

        var findings: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: TestSupport.root, includingPropertiesForKeys: [.isDirectoryKey]))
        while let file = enumerator.nextObject() as? URL {
            if skippedFolders.contains(file.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = file.path.replacingOccurrences(of: TestSupport.root.path + "/", with: "")
            for needle in needles where text.contains(needle) {
                findings.append("\(relative): contains a personal path or username")
            }
            if email.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                findings.append("\(relative): contains an email address")
            }
        }
        XCTAssertEqual(findings, [])
    }
}
