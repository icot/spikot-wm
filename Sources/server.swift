
import Network
import Dispatch

public final class TCPServer {
    
    let queue: DispatchQueue
    let listener: NWListener

    private func _stateHandler(state: NWListener.State) {
        switch state {
            case .setup: break
            case .waiting: break
            case .ready: break
            case .cancelled: _cancel()
            case .failed: _cancel()
            @unknown default: break
        }
    }

    private func _connectionHandler(conn: NWConnection) {
        debugPrint("Received Connection")
        debugPrint(conn)
        dump(conn)
        // conn.send(content: "ping", isComplete: true, completion:NWConnection.SendCompletion.idempotent)
    }
    
    private func _cancel() {
        listener.cancel()
    }
    
    public init(port: NWEndpoint.Port = 1234) {
        let options = NWProtocolTCP.Options()
        let params = NWParameters(tls:nil, tcp: options)
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

let server = TCPServer.init(port:1235)

server.run()



