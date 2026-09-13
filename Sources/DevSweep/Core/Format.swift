import Foundation

enum Fmt {
    /// Disk sizes use base 1000, matching Finder.
    static func disk(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// Memory sizes use base 1024, matching Activity Monitor.
    static func memory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .memory)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return tr("duration.minutes", ["value": max(1, minutes)]) }
        let hours = minutes / 60
        if hours < 48 { return tr("duration.hours", ["value": hours]) }
        return tr("duration.days", ["value": hours / 24])
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.shared.language)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}
