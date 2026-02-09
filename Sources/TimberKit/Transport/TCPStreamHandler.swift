import Foundation
import Network

/// TCP-based handler for streaming logs (plain, no TLS)
/// Useful for local development with tools like `nc -l <port>`
public final class TCPStreamHandler: StreamHandler, @unchecked Sendable {
    private let endpoint: NWEndpoint
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "timber.tcp")

    /// Creates a TCP stream handler
    /// - Parameters:
    ///   - host: Target host (default: "127.0.0.1")
    ///   - port: Target port (default: 9999)
    /// - Throws: TimberError.invalidConfiguration if port is invalid
    public init(
        host: String = "127.0.0.1",
        port: UInt16 = 9999
    ) throws {
        self.endpoint = try makeEndpoint(host: host, port: port)
        connect()
    }

    private func connect() {
        let params = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                TimberDiagnostics.emit(.connectionStateChanged(.connected))
            case .failed(let error):
                TimberDiagnostics.reportConnectionFailed(error)
                // Attempt reconnect after delay
                self?.queue.asyncAfter(deadline: .now() + Constants.tcpReconnectDelay) {
                    self?.connect()
                }
            case .cancelled:
                TimberDiagnostics.emit(.connectionStateChanged(.disconnected))
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    public func send(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            bundleIdentifier: bundleIdentifier,
            subsystem: Timber.subsystem,
            category: Timber.category,
            file: file,
            function: function,
            line: line
        )

        queue.async { [weak self] in
            guard let self = self,
                  let connection = self.connection,
                  connection.state == .ready else {
                return
            }

            guard let data = LogEntryEncoder.shared.encode(entry) else {
                TimberDiagnostics.reportEncodingFailed(message: message)
                return
            }

            connection.send(content: data, completion: .contentProcessed { _ in
                // Connection will handle reconnection via state handler
            })
        }
    }

    public func close() {
        connection?.cancel()
        connection = nil
    }

    deinit {
        close()
    }
}
