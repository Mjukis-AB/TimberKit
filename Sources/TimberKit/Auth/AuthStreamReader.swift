import Foundation
import Network

/// Reads newline-delimited JSON auth messages from NWConnection
///
/// Handles the low-level reading of data from the connection, buffering
/// partial messages, and parsing complete JSON lines into auth messages.
final class AuthStreamReader: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var isCancelled = false
    private let lock = NSLock()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Read the next auth message from the connection
    /// - Parameter completion: Called with the parsed message or error
    func readNextMessage(completion: @escaping (Result<AuthMessage, Error>) -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            completion(.failure(AuthStreamError.cancelled))
            return
        }
        lock.unlock()

        // Check if we already have a complete message in the buffer
        if let message = tryParseBufferedMessage() {
            completion(.success(message))
            return
        }

        // Need to read more data
        readMoreData(completion: completion)
    }

    /// Cancel any pending reads
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    // MARK: - Private

    private func readMoreData(completion: @escaping (Result<AuthMessage, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            self.lock.lock()
            if self.isCancelled {
                self.lock.unlock()
                completion(.failure(AuthStreamError.cancelled))
                return
            }
            self.lock.unlock()

            if let error = error {
                completion(.failure(AuthStreamError.networkError(error.localizedDescription)))
                return
            }

            if let data = content {
                self.lock.lock()
                self.buffer.append(data)
                self.lock.unlock()

                // Try to parse a complete message
                if let message = self.tryParseBufferedMessage() {
                    completion(.success(message))
                    return
                }
            }

            if isComplete {
                // Connection closed
                completion(.failure(AuthStreamError.connectionClosed))
                return
            }

            // Need more data, keep reading
            self.readMoreData(completion: completion)
        }
    }

    private func tryParseBufferedMessage() -> AuthMessage? {
        lock.lock()
        defer { lock.unlock() }

        // Loop to skip invalid/empty lines and find next valid message
        while let newlineIndex = buffer.firstIndex(of: Constants.jsonlTerminator) {
            // Extract the line (excluding newline)
            let lineData = buffer[buffer.startIndex..<newlineIndex]

            // Remove the processed line from buffer (including newline)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            // Skip empty lines
            guard !lineData.isEmpty else {
                continue
            }

            // Try to parse JSON
            do {
                let message = try JSONDecoder().decode(AuthMessage.self, from: lineData)
                return message
            } catch {
                TimberDiagnostics.logWarning("Failed to parse auth message: \(error)")
                // Continue to try next line if available
                continue
            }
        }

        return nil
    }
}

// MARK: - Errors

enum AuthStreamError: Error, LocalizedError {
    case cancelled
    case connectionClosed
    case networkError(String)
    case invalidMessage(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Read cancelled"
        case .connectionClosed:
            return "Connection closed"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidMessage(let message):
            return "Invalid message: \(message)"
        case .timeout:
            return "Read timeout"
        }
    }
}

// MARK: - Auth Message Writer

/// Writes auth messages to NWConnection
final class AuthStreamWriter: @unchecked Sendable {
    private let connection: NWConnection
    private let encoder: JSONEncoder

    init(connection: NWConnection) {
        self.connection = connection
        self.encoder = JSONEncoder()
    }

    /// Send an auth message
    /// - Parameters:
    ///   - message: The message to send
    ///   - completion: Called when send completes or fails
    func send(_ message: AuthMessage, completion: @escaping (Error?) -> Void) {
        do {
            var data = try encoder.encode(message)
            data.append(Constants.jsonlTerminator)

            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    completion(AuthStreamError.networkError(error.localizedDescription))
                } else {
                    completion(nil)
                }
            })
        } catch {
            completion(AuthStreamError.invalidMessage("Failed to encode message: \(error)"))
        }
    }
}
