import Foundation
import Darwin

/// File-backed streams cannot deadlock when a helper fills stderr or stops reading stdin.
enum BridgeProcess {
    static func run(executable: String, arguments: [String], input: Data, timeout: TimeInterval = 45) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdin = directory.appendingPathComponent("input")
        let stdout = directory.appendingPathComponent("output")
        let stderr = directory.appendingPathComponent("error")
        try input.write(to: stdin)
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let reader = try FileHandle(forReadingFrom: stdin)
        let writer = try FileHandle(forWritingTo: stdout)
        let errorWriter = try FileHandle(forWritingTo: stderr)
        defer { try? reader.close(); try? writer.close(); try? errorWriter.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = reader; process.standardOutput = writer; process.standardError = errorWriter
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw NSError(domain: "Bridge", code: 408, userInfo: [NSLocalizedDescriptionKey: "Интеграция не ответила вовремя. Если отправляли ответ, проверьте исходную сессию перед повтором."])
        }
        process.waitUntilExit()
        let data = try Data(contentsOf: stdout)
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw NSError(domain: "Bridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить интеграции. Проверьте Python в настройках подключений."])
        }
        return data
    }
}
