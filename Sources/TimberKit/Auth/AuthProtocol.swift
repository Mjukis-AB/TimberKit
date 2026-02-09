import Foundation

/// Wire protocol messages for authentication handshake
public enum AuthMessage: Codable, Sendable {
    case hello(HelloMessage)
    case authChallenge(AuthChallengeMessage)
    case authResponse(AuthResponseMessage)
    case authResult(AuthResultMessage)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case MessageType.hello:
            self = .hello(try HelloMessage(from: decoder))
        case MessageType.authChallenge:
            self = .authChallenge(try AuthChallengeMessage(from: decoder))
        case MessageType.authResponse:
            self = .authResponse(try AuthResponseMessage(from: decoder))
        case MessageType.authOK, MessageType.authFailed:
            self = .authResult(try AuthResultMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .hello(let msg):
            try msg.encode(to: encoder)
        case .authChallenge(let msg):
            try msg.encode(to: encoder)
        case .authResponse(let msg):
            try msg.encode(to: encoder)
        case .authResult(let msg):
            try msg.encode(to: encoder)
        }
    }
}

/// Initial hello message from client
public struct HelloMessage: Codable, Sendable {
    public let type: String
    public let version: Int
    public let app: String
    public let subsystem: String

    public init(app: String, subsystem: String, version: Int = 1) {
        self.type = MessageType.hello
        self.version = version
        self.app = app
        self.subsystem = subsystem
    }
}

/// Authentication challenge from server
public struct AuthChallengeMessage: Codable, Sendable {
    public let type: String
    public let method: String

    public init(method: AuthMethod) {
        self.type = MessageType.authChallenge
        switch method {
        case .none:
            self.method = AuthMethodIdentifier.none
        case .pin:
            self.method = AuthMethodIdentifier.pin
        case .token:
            self.method = AuthMethodIdentifier.token
        }
    }
}

/// Authentication response from client
public struct AuthResponseMessage: Codable, Sendable {
    public let type: String
    public let pin: String?
    public let token: String?

    public init(pin: String) {
        self.type = MessageType.authResponse
        self.pin = pin
        self.token = nil
    }

    public init(token: String) {
        self.type = MessageType.authResponse
        self.pin = nil
        self.token = token
    }

    public init() {
        self.type = MessageType.authResponse
        self.pin = nil
        self.token = nil
    }
}

/// Authentication result from server
public struct AuthResultMessage: Codable, Sendable {
    public let type: String
    public let reason: String?

    public var success: Bool { type == MessageType.authOK }

    public static func success() -> AuthResultMessage {
        AuthResultMessage(type: MessageType.authOK, reason: nil)
    }

    public static func failure(reason: String) -> AuthResultMessage {
        AuthResultMessage(type: MessageType.authFailed, reason: reason)
    }
}
