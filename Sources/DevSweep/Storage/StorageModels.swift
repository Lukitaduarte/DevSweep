import Foundation

enum Risk: String, Comparable, Sendable {
    /// Regenerated automatically, nothing to download.
    case safe
    /// Comes back on the next build/install, but has to be downloaded again.
    case redownload
    /// Removes state the user might want (simulator data, archives, open apps).
    case dataLoss = "data_loss"

    private var rank: Int {
        switch self {
        case .safe: 0
        case .redownload: 1
        case .dataLoss: 2
        }
    }

    static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rank < rhs.rank }

    var label: String {
        switch self {
        case .safe: tr("risk.safe")
        case .redownload: tr("risk.redownload")
        case .dataLoss: tr("risk.data_loss")
        }
    }
}

enum CleanMethod: Sendable {
    case delete
    case trash
    /// Runs each command (first element is the tool) and optionally deletes the paths afterwards.
    case commands([[String]], thenDelete: Bool)
}

struct StorageTarget: Identifiable, Sendable {
    let id: String
    let stack: StackInfo
    let title: String
    let detail: String
    let risk: Risk
    let paths: [URL]
    var method: CleanMethod = .delete
    /// Substrings of process command lines to terminate before cleaning (e.g. Gradle daemons).
    var stopProcesses: [String] = []
    var autoRecommend: Bool = true
    /// Per-target suggestion threshold; falls back to the global preference.
    var recommendMinBytes: Int64? = nil
}
