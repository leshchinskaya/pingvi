import AppKit

/// References stay in the existing persisted draft and are delivered through CLI text input.
enum AttachmentReference {
    static let prefix = "Прочитай приложенный локальный файл: "

    static func line(for url: URL) throws -> String {
        let url = url.standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        guard url.isFileURL, values.isRegularFile == true, values.isReadable == true else {
            throw NSError(domain: "Attachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Выберите доступный для чтения файл."])
        }
        // JSON quoting preserves spaces, quotes and newlines without shell interpolation.
        let data = try JSONEncoder().encode(url.path)
        return prefix + String(decoding: data, as: UTF8.self)
    }

    static func validate(in text: String) throws {
        for line in text.components(separatedBy: "\n") {
            guard let range = line.range(of: prefix) else { continue }
            let encoded = String(line[range.upperBound...])
            guard let path = try? JSONDecoder().decode(String.self, from: Data(encoded.utf8)) else { continue }
            do { _ = try self.line(for: URL(fileURLWithPath: path)) }
            catch {
                throw NSError(domain: "Attachment", code: 2, userInfo: [NSLocalizedDescriptionKey: "Файл недоступен: \(path). Прикрепите его заново или удалите ссылку из ответа."])
            }
        }
    }

    static func adding(_ urls: [URL], to text: String) throws -> String {
        let additions = try urls.map { try line(for: $0) }
        var lines = text.components(separatedBy: "\n")
        for line in additions where !lines.contains(line) { lines.append(line) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}
