import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs command-line tools with a PATH that mirrors a typical dev shell,
/// since apps launched from Finder/launchd don't inherit the user's shell PATH.
enum Shell {
    static let searchPath: String = {
        let home = NSHomeDirectory()
        var parts = [
            "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/fvm/default/bin", "\(home)/.pub-cache/bin",
            "\(home)/go/bin", "/usr/local/go/bin",
            "\(home)/Library/Android/sdk/platform-tools",
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/Library/pnpm",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm),
           let latest = versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }).first {
            parts.append("\(nvm)/\(latest)/bin")
        }
        parts += ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return parts.joined(separator: ":")
    }()

    static func which(_ tool: String) -> String? {
        for dir in searchPath.split(separator: ":") {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private final class Buffer: @unchecked Sendable { var data = Data() }

    @discardableResult
    static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 120) -> ShellResult {
        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
        } else if let path = which(executable) {
            process.executableURL = URL(fileURLWithPath: path)
        } else {
            return ShellResult(status: 127, stdout: "", stderr: tr("error.command_not_found", ["command": executable]))
        }
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        env["LC_ALL"] = "C"
        process.environment = env

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain both pipes concurrently so a chatty tool can't fill the buffer and deadlock.
        let outBuf = Buffer(), errBuf = Buffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outBuf.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errBuf.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        // Daemons forked by the tool may keep the pipe open; don't wait on them forever.
        _ = group.wait(timeout: .now() + 5)

        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outBuf.data, as: UTF8.self),
            stderr: String(decoding: errBuf.data, as: UTF8.self)
        )
    }
}
