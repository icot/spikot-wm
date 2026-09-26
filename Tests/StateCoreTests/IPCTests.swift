import Dispatch
import Foundation
import Testing

@testable import StateCore

@Suite("Line framing")
struct LineFramerTests {

    @Test("A single complete line comes back whole")
    func singleLine() throws {
        var framer = LineFramer()
        let lines = try framer.append(Data("hello\n".utf8))
        #expect(lines.count == 1)
        #expect(String(decoding: lines[0], as: UTF8.self) == "hello")
        #expect(framer.pending == 0)
    }

    @Test("A request split across two writes is reassembled")
    func splitAcrossWrites() throws {
        // A socket read returns whatever arrived, so this is the normal case, not an edge one.
        var framer = LineFramer()
        #expect(try framer.append(Data(#"{"v":1,"cmd":"pi"#.utf8)).isEmpty)
        #expect(framer.pending > 0)

        let lines = try framer.append(Data("ng\"}\n".utf8))
        #expect(lines.count == 1)
        let request = try LineFramer.decode(Request.self, from: lines[0])
        #expect(request.cmd == "ping")
    }

    @Test("Several lines in one write all come back, in order")
    func severalLines() throws {
        var framer = LineFramer()
        let lines = try framer.append(Data("one\ntwo\nthree\n".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["one", "two", "three"])
    }

    @Test("A trailing partial line is held back")
    func trailingPartial() throws {
        var framer = LineFramer()
        let lines = try framer.append(Data("complete\npartial".utf8))
        #expect(lines.count == 1)
        #expect(framer.pending == 7)
    }

    @Test("Blank lines are ignored rather than decoded as empty messages")
    func blankLines() throws {
        var framer = LineFramer()
        #expect(try framer.append(Data("\n\n".utf8)).isEmpty)
    }

    @Test("An unterminated line beyond the limit is rejected and the buffer dropped")
    func oversizedLine() throws {
        var framer = LineFramer(limit: 64)
        #expect(throws: IPCError.self) {
            _ = try framer.append(Data(repeating: UInt8(ascii: "x"), count: 65))
        }
        #expect(framer.pending == 0, "the buffer is released rather than held")
    }

    @Test("Many small messages do not trip the limit")
    func manySmallMessages() throws {
        // The check runs after extracting complete lines, so only a single oversized
        // message fails, not a large batch of valid ones.
        var framer = LineFramer(limit: 64)
        let batch = Data(String(repeating: "ab\n", count: 50).utf8)
        #expect(try framer.append(batch).count == 50)
    }

    @Test("Encode appends exactly one newline")
    func encodeFrames() throws {
        let data = try LineFramer.encode(Request(cmd: "ping", id: "x"))
        #expect(data.last == UInt8(ascii: "\n"))
        #expect(data.dropLast().last != UInt8(ascii: "\n"))
    }

    @Test("Decoding junk reports a malformed message, not a crash")
    func decodeJunk() {
        #expect(throws: IPCError.self) {
            _ = try LineFramer.decode(Request.self, from: Data("not json".utf8))
        }
    }
}

@Suite("Protocol shape")
struct ProtocolTests {

    @Test("A request round-trips through JSON")
    func requestRoundTrip() throws {
        let original = Request(cmd: "focus", args: ["target": "left"], id: "abc")
        let decoded = try JSONDecoder().decode(
            Request.self, from: try JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("The version key is v on the wire, to keep lines short")
    func wireKeys() throws {
        let json = String(decoding: try JSONEncoder().encode(Request(cmd: "ping", id: "x")), as: UTF8.self)
        #expect(json.contains("\"v\":1"))
        #expect(!json.contains("\"version\""))
    }

    @Test("A minimal request decodes, so a hand-typed line works")
    func minimalRequest() throws {
        // What someone would paste into `nc -U`.
        let request = try LineFramer.decode(Request.self, from: Data(#"{"cmd":"ping"}"#.utf8))
        #expect(request.cmd == "ping")
        #expect(request.version == IPC.version, "version defaults rather than failing")
        #expect(request.args.isEmpty)
    }

    @Test("A request without cmd is rejected")
    func missingCommand() {
        #expect(throws: IPCError.self) {
            _ = try LineFramer.decode(Request.self, from: Data(#"{"v":1}"#.utf8))
        }
    }

    @Test("Error codes map onto distinct exit codes")
    func exitCodes() {
        #expect(ExitStatus(errorCode: "noDaemon") == .noDaemon)
        #expect(ExitStatus(errorCode: "noPermission") == .noPermission)
        #expect(ExitStatus(errorCode: "emptyStack") == .notFound)
        #expect(ExitStatus(errorCode: "stackOutOfRange") == .notFound)
        #expect(ExitStatus(errorCode: "something new") == .failure, "unknown codes are generic")
    }

    @Test("The socket path stays inside the sun_path limit")
    func socketPathLength() throws {
        // sockaddr_un.sun_path is 104 bytes; exceeding it is a confusing runtime failure.
        #expect(IPC.socketURL.path.utf8.count < 104)
        #expect(throws: IPCError.self) {
            _ = try SocketServer.address(for: String(repeating: "x", count: 200))
        }
    }
}

@Suite("Socket transport", .serialized)
struct SocketTransportTests {

    /// A socket in a fresh temporary directory, so tests cannot collide with each other or
    /// with a real agent.
    private func temporaryPath() -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-ipc-\(UUID().uuidString.prefix(8))")
        return dir.appendingPathComponent("agent.sock").path
    }

    @Test("A request reaches the handler and the reply comes back")
    func roundTrip() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }

        try server.start { request in
            .success(id: request.id, text: "pong", data: ["cmd": request.cmd])
        }

        let response = try SocketClient(path: path).send(Request(cmd: "ping", id: "req-1"))
        #expect(response.ok)
        #expect(response.id == "req-1", "the id is echoed so a client can match its own reply")
        #expect(response.text == "pong")
        #expect(response.data?["cmd"] == "ping")
    }

    @Test("A failing command returns ok false with a code")
    func failureResponse() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { request in
            .failure(id: request.id, code: "emptyStack", message: "stack 2 has no windows")
        }

        let response = try SocketClient(path: path).send(Request(cmd: "focus", id: "req-2"))
        #expect(!response.ok)
        #expect(response.error?.code == "emptyStack")
        #expect(ExitStatus(errorCode: response.error!.code) == .notFound)
    }

    @Test("Several requests in sequence each get their own reply")
    func sequentialRequests() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { .success(id: $0.id, text: $0.cmd) }

        let client = SocketClient(path: path)
        for index in 0..<5 {
            let response = try client.send(Request(cmd: "cmd\(index)", id: "id\(index)"))
            #expect(response.id == "id\(index)")
            #expect(response.text == "cmd\(index)")
        }
    }

    @Test("No listener reports noDaemon, which is what lets the CLI fall back")
    func noDaemon() {
        let path = temporaryPath()
        #expect(throws: IPCError.noDaemon(path: path)) {
            _ = try SocketClient(path: path).send(Request(cmd: "ping"))
        }
    }

    @Test("A wrong protocol version is rejected rather than guessed at")
    func versionMismatch() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { _ in .success(id: "unused", text: "handler should not run") }

        let response = try SocketClient(path: path).send(
            Request(cmd: "ping", id: "req-3", version: 999))
        #expect(!response.ok)
        #expect(response.error?.code == "protocol")
    }

    @Test("Malformed JSON gets a protocol error, and the agent stays up")
    func malformedRequest() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { .success(id: $0.id, text: "ok") }

        // Bypass SocketClient to send something it would never produce.
        let raw = try Self.sendRaw("{not json}\n", to: path)
        #expect(raw.contains("\"ok\":false"))
        #expect(raw.contains("protocol"))

        // The listener survived, which is the point.
        let after = try SocketClient(path: path).send(Request(cmd: "ping", id: "after"))
        #expect(after.ok)
    }

    @Test("A hand-typed minimal line works end to end, as nc -U sends it")
    func rawMinimalRequest() throws {
        // Mirrors `printf '{"cmd":"ping"}\n' | nc -U <path>`: no version, no id, no args.
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { .success(id: $0.id, text: "pong cmd=\($0.cmd)") }

        let reply = try Self.sendRaw("{\"cmd\":\"ping\"}\n", to: path)
        #expect(reply.contains("\"ok\":true"))
        #expect(reply.contains("pong cmd=ping"))
        #expect(reply.hasSuffix("\n"), "the reply is newline-framed")
    }

    @Test("The socket file is owner-only")
    func permissions() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { .success(id: $0.id) }

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]
        #expect((mode as? NSNumber)?.int16Value == 0o600)
    }

    @Test("stop removes the socket file")
    func stopCleansUp() throws {
        let path = temporaryPath()
        let server = SocketServer(path: path)
        try server.start { .success(id: $0.id) }
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("A stale socket file is replaced, not treated as a live agent")
    func staleSocketReplaced() throws {
        let path = temporaryPath()
        try SocketServer.prepareDirectory(for: path)
        // A plain file where the socket belongs, as a crashed agent would leave behind.
        try Data().write(to: URL(fileURLWithPath: path))

        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { .success(id: $0.id, text: "took over") }
        #expect(try SocketClient(path: path).send(Request(cmd: "ping")).text == "took over")
    }

    @Test("A second agent refuses to steal a live socket")
    func liveSocketNotStolen() throws {
        let path = temporaryPath()
        let first = SocketServer(path: path)
        defer { first.stop() }
        try first.start { .success(id: $0.id, text: "first") }

        let second = SocketServer(path: path)
        #expect(throws: IPCError.self) {
            try second.start { .success(id: $0.id, text: "second") }
        }
        // The original is still serving.
        #expect(try SocketClient(path: path).send(Request(cmd: "ping")).text == "first")
    }

    /// Writes bytes to the socket without going through `SocketClient`, and reads the reply.
    private static func sendRaw(_ text: String, to path: String) throws -> String {
        var addr = try SocketServer.address(for: path)
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fileDescriptor) }
        _ = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        _ = Data(text.utf8).withUnsafeBytes { Darwin.write(fileDescriptor, $0.baseAddress!, $0.count) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fileDescriptor, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer[0..<count], as: UTF8.self) : ""
    }
}
