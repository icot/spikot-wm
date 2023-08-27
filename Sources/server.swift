
import Foundation
import Network
import Dispatch


public final class TCPConn {
    
    private let conn: NWConnection
    private var queue: DispatchQueue?

    private func _stateUpdateHandler(state: NWConnection.State) {
        switch state {
            case .setup: break
            case .waiting: break
            case .preparing: break
            case .ready: break
            case .failed(let error):
                print("server error: \(error)")
                self.close()
            case .cancelled: break
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
        self.conn.start(queue:queue)
    }

    func close() {
        self.conn.stateUpdateHandler = nil
        self.conn.cancel()
    }
    
    func send(data:Data) {
        print("Sending \(data.count) bytes")
        self.conn.send(content: data,
                       completion: .contentProcessed(
                         { error in
                             if let error = error {
                                 print("Error sending data: \(error)")
                                 return
                             }
                         }))
    }

}

public final class TCPServer {
    
    let queue: DispatchQueue
    let listener: NWListener

    private func _stateHandler(state: NWListener.State) {
        switch state {
            case .setup: break
            case .waiting: break
            case .ready: break
            case .failed(let error):
                print("server error: \(error)")
                _cancel()
            case .cancelled: self._cancel()
            @unknown default: break
        }
    }

    private func _connectionHandler(connection: NWConnection) {
        debugPrint("Received Connection")
        debugPrint(connection)
        dump(connection)
        let conn: TCPConn = TCPConn(connection: connection)
        conn.start(queue:self.queue)
        // Respond
        let data:Data = Data("[\(Date())] - ping!".utf8)
        conn.send(data: data)
        conn.close()
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



