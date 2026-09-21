import Foundation

public struct PingviFrameDecoder: Sendable {
    private var buffer = Data()
    private let maximumSize: Int

    public init(maximumSize: Int = PingviProtocol.maximumFrameSize) {
        self.maximumSize = maximumSize
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let size = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard size <= maximumSize else { throw PingviLinkError.frameTooLarge(size) }
            guard buffer.count >= size + 4 else { break }
            frames.append(Data(buffer[4..<(size + 4)]))
            buffer.removeSubrange(0..<(size + 4))
        }
        return frames
    }
}

public enum PingviFraming {
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= PingviProtocol.maximumFrameSize else {
            throw PingviLinkError.frameTooLarge(payload.count)
        }
        var size = UInt32(payload.count).bigEndian
        var result = withUnsafeBytes(of: &size) { Data($0) }
        result.append(payload)
        return result
    }
}
