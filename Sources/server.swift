import Foundation
import Network
import Dispatch

@available(macOS, introduced: 10.14)

public final class TCPConn {

    private let conn: NWConnection
    private var queue: DispatchQueue?

    private func _stateUpdateHandler(state: NWConnection.State) {
        switch state {
        case .setup: break
        case .waiting(let error):
                print("Connection waiting error: \(error)")
        case .preparing: break
        case .ready: print("Connection Ready")
        case .failed(let error):
                print("Connection error: \(error)")
                self.close()
        case .cancelled: print("Connection cancelled")
        @unknown default: break
        }
    }

    init(connection: NWConnection) {
        self.conn = connection
        self.queue = nil
    }

    func start(queue: DispatchQueue) {
        self.queue = queue
        self.conn.stateUpdateHandler = self._stateUpdateHandler(state:)
        self.conn.start(queue: queue)
    }

    func close() {
        self.conn.stateUpdateHandler = nil
        self.conn.cancel()
    }

    func send(data: Data) {
        print("Sending \(data.count) bytes")
        self.conn.send(content: data,
                       contentContext: NWConnection.ContentContext.finalMessage,
                       completion: .contentProcessed(
                         { error in
                             if let error = error {
                                 print("Error sending data: \(error)")
                                 return
                             }
                         }))
    }

}

@available(macOS, introduced: 10.14)
public final class TCPServer {

    let queue: DispatchQueue
    let listener: NWListener

    private func _stateHandler(state: NWListener.State) {
        switch state {
        case .setup:
            print("Listener setup")
        case .waiting:
            print("Listener waiting")
        case .ready:
            print("Listener ready")
        case .failed(let error):
            print("server error: \(error)")
            _cancel()
        case .cancelled: self._cancel()
        @unknown default: break
        }
    }

    private func _connectionHandler(connection: NWConnection) {
        debugPrint(connection)
        dump(connection)
        let conn: TCPConn = TCPConn(connection: connection)
        conn.start(queue: self.queue)
        // Respond
        let data: Data = Data("[\(Date())] - ping!".utf8)
        conn.send(data: data)
        /*
         TODO This works for the purpose of actually pinging back the client
         but
         1) I'm not closing the connection (which I guess is OK as the object should be
         be GC'ed?
         2) The Server registers a Failed state (POSIXErrorCode(rawValue: 50): Network is down)
         */
        usleep(1000000)
        conn.close()
    }

    private func _cancel() {
        print("Listener cancelled")
        listener.cancel()
    }

    public init(port: NWEndpoint.Port = 1234) {
        let options = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: options)
        self.queue = DispatchQueue.main
        self.listener = try! NWListener.init(using: params, on: port)
        self.listener.stateUpdateHandler = self._stateHandler
        self.listener.newConnectionHandler = self._connectionHandler
    }

    public func run() -> Never {
        debugPrint(listener)
        listener.start(queue: self.queue)
        dispatchMain()
    }

}

// let server = TCPServer.init(port:1235)
// server.run()
