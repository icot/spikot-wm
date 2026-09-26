import Darwin
import Dispatch
import Foundation

/// A unix-domain socket listener.
///
/// Raw BSD sockets rather than Network.framework: `NWListener` needs an awkward
/// `requiredLocalEndpoint` dance for unix sockets, and Network.framework is what failed in
/// the abandoned attempt removed in 84a175f.
public final class SocketServer {
    private let path: String
    private let queue: DispatchQueue
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    /// Handles one request and returns the reply. Runs on `queue`.
    public typealias Handler = (Request) -> Response

    public init(path: String, queue: DispatchQueue = DispatchQueue(label: "org.traf.spikot-wm.ipc")) {
        self.path = path
        self.queue = queue
    }

    deinit {
        stop()
    }

    /// Binds and starts accepting.
    ///
    /// A leftover socket file from a crashed agent would make `bind` fail with EADDRINUSE,
    /// so a stale path is removed first. It is only removed when connecting to it fails:
    /// if something answers, another agent is live and this one must not steal its path.
    public func start(handler: @escaping Handler) throws {
        try Self.prepareDirectory(for: path)

        if FileManager.default.fileExists(atPath: path) {
            if Self.isLive(path: path) {
                throw IPCError.socketFailure("another agent is already listening at \(path)")
            }
            logger.debug("Removing stale socket at \(path)")
            try? FileManager.default.removeItem(atPath: path)
        }

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw IPCError.socketFailure("socket() failed: \(String(cString: strerror(errno)))")
        }

        var addr = try Self.address(for: path)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let detail = String(cString: strerror(errno))
            close(listenFD)
            listenFD = -1
            throw IPCError.socketFailure("bind(\(path)) failed: \(detail)")
        }

        // Owner-only: window management should not be drivable by other accounts.
        chmod(path, 0o600)

        guard listen(listenFD, 16) == 0 else {
            let detail = String(cString: strerror(errno))
            stop()
            throw IPCError.socketFailure("listen() failed: \(detail)")
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(handler: handler) }
        source.resume()
        acceptSource = source
        logger.info("Listening on \(path)")
    }

    /// Closes the listener and removes the socket file.
    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Serves one connection: read a line, reply, close.
    ///
    /// One request per connection keeps the agent from holding state per client and means a
    /// client that dies mid-exchange costs nothing.
    private func accept(handler: @escaping Handler) {
        let clientFD = Darwin.accept(listenFD, nil, nil)
        guard clientFD >= 0 else {
            if errno != EWOULDBLOCK && errno != EINTR {
                logger.error("accept() failed: \(String(cString: strerror(errno)))")
            }
            return
        }
        defer { close(clientFD) }

        var framer = LineFramer()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(clientFD, &buffer, buffer.count)
            if count == 0 { return }  // peer closed without sending a full line
            if count < 0 {
                if errno == EINTR { continue }
                logger.error("read() failed: \(String(cString: strerror(errno)))")
                return
            }

            let lines: [Data]
            do {
                lines = try framer.append(Data(buffer[0..<count]))
            } catch {
                Self.write(Response.failure(id: "", code: "protocol", message: "\(error)"), to: clientFD)
                return
            }

            guard let line = lines.first else { continue }
            Self.write(Self.reply(to: line, handler: handler), to: clientFD)
            return
        }
    }

    /// Decodes a request, checks the version, and runs the handler.
    private static func reply(to line: Data, handler: Handler) -> Response {
        let request: Request
        do {
            request = try LineFramer.decode(Request.self, from: line)
        } catch {
            return .failure(id: "", code: "protocol", message: "\(error)")
        }
        guard request.version == IPC.version else {
            return .failure(
                id: request.id, code: "protocol",
                message: IPCError.versionMismatch(got: request.version, expected: IPC.version)
                    .description)
        }
        return handler(request)
    }

    private static func write(_ response: Response, to fileDescriptor: Int32) {
        guard let data = try? LineFramer.encode(response) else { return }
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let wrote = Darwin.write(fileDescriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if wrote <= 0 {
                    if errno == EINTR { continue }
                    return
                }
                sent += wrote
            }
        }
    }

    /// Builds a `sockaddr_un`, rejecting a path too long for `sun_path`.
    static func address(for path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else {
            throw IPCError.socketFailure("socket path is \(bytes.count) bytes, limit is \(capacity - 1)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        return addr
    }

    static func prepareDirectory(for path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// Whether something is accepting connections at `path`.
    static func isLive(path: String) -> Bool {
        guard let addr = try? address(for: path) else { return false }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        var mutable = addr
        let connected = withUnsafePointer(to: &mutable) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return connected == 0
    }
}

/// Sends one request and reads one reply.
public struct SocketClient {
    private let path: String
    private let timeout: TimeInterval

    public init(path: String = IPC.socketURL.path, timeout: TimeInterval = 5) {
        self.path = path
        self.timeout = timeout
    }

    /// Connects, sends, reads one line, closes.
    ///
    /// Throws `IPCError.noDaemon` when nothing is listening, which is what lets the CLI fall
    /// back to running the command in-process.
    public func send(_ request: Request) throws -> Response {
        let fileDescriptor = try connect()
        defer { close(fileDescriptor) }
        try writeAll(try LineFramer.encode(request), to: fileDescriptor)
        return try readResponse(from: fileDescriptor)
    }

    /// Opens the socket with send and receive timeouts applied.
    ///
    /// ENOENT means no socket file and ECONNREFUSED means the file exists but nothing is
    /// accepting. Both mean the same to a caller, so both become `noDaemon`: that is what
    /// lets the CLI fall back to running the command itself.
    private func connect() throws -> Int32 {
        var addr = try SocketServer.address(for: path)
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw IPCError.socketFailure("socket() failed: \(String(cString: strerror(errno)))")
        }

        let whole = Int(timeout)
        var limit = timeval(
            tv_sec: whole, tv_usec: Int32((timeout - Double(whole)) * 1_000_000))
        setsockopt(
            fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(
            fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            close(fileDescriptor)
            if code == ENOENT || code == ECONNREFUSED {
                throw IPCError.noDaemon(path: path)
            }
            throw IPCError.socketFailure(
                "connect(\(path)) failed: \(String(cString: strerror(code)))")
        }
        return fileDescriptor
    }

    /// Writes every byte, retrying short writes and EINTR.
    private func writeAll(_ payload: Data, to fileDescriptor: Int32) throws {
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let wrote = Darwin.write(
                    fileDescriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if wrote <= 0 {
                    if errno == EINTR { continue }
                    throw IPCError.socketFailure(
                        "write() failed: \(String(cString: strerror(errno)))")
                }
                sent += wrote
            }
        }
    }

    /// Reads until one complete line has arrived.
    private func readResponse(from fileDescriptor: Int32) throws -> Response {
        var framer = LineFramer()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fileDescriptor, &buffer, buffer.count)
            if count == 0 { throw IPCError.malformed("the agent closed without replying") }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw IPCError.timedOut }
                throw IPCError.socketFailure("read() failed: \(String(cString: strerror(errno)))")
            }
            if let line = try framer.append(Data(buffer[0..<count])).first {
                return try LineFramer.decode(Response.self, from: line)
            }
        }
    }
}
