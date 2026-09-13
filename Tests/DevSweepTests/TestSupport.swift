import Foundation
@testable import DevSweep

enum TestSupport {
    /// Repository root, derived from this file's location (test-only; never compiled into the app).
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var stacksDirectory: URL { root.appendingPathComponent("stacks") }
    static var localesDirectory: URL { root.appendingPathComponent("locales") }

    static func useEnglish() {
        L10n.shared.reload(directories: [localesDirectory], preference: "en")
    }

    static let definitions: Definitions = {
        useEnglish()
        return DefinitionLoader.load(from: [stacksDirectory])
    }()

    static var rules: [ProcessRule] { definitions.processRules }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devsweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
