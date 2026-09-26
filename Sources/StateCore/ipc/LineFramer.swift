import Foundation

/// Splits a byte stream into newline-terminated messages.
///
/// A socket read returns whatever happened to arrive, which may be half a message, several
/// messages, or a message split mid-character. The framer buffers until it sees a newline
/// and refuses to buffer past `limit`, so a peer that never sends one cannot make the agent
/// grow without bound.
public struct LineFramer {
    private var buffer = Data()
    private let limit: Int

    public init(limit: Int = IPC.maxLineBytes) {
        self.limit = limit
    }

    /// Bytes buffered so far, awaiting a newline.
    public var pending: Int { buffer.count }

    /// Adds bytes and returns every complete message they completed.
    ///
    /// Throws `IPCError.lineTooLong` once the unterminated remainder exceeds the limit. The
    /// check runs after extracting whatever was complete, so a large batch of small
    /// messages is fine and only a single oversized one fails.
    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            // A blank line is padding, not a message.
            if !line.isEmpty {
                lines.append(Data(line))
            }
        }

        if buffer.count > limit {
            let overflowed = buffer.count
            buffer.removeAll(keepingCapacity: false)
            throw IPCError.lineTooLong(overflowed)
        }
        return lines
    }

    /// Discards anything buffered, for reuse across connections.
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}

extension LineFramer {
    /// Encodes a value as one framed line.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Decodes one framed line, translating a decode failure into an `IPCError`.
    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: line)
        } catch {
            throw IPCError.malformed("\(error)")
        }
    }
}
