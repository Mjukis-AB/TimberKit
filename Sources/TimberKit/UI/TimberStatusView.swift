import SwiftUI

/// A small status indicator for Timber connection state
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct TimberStatusView: View {
    @ObservedObject private var status: TimberStatusObserver

    public init() {
        self.status = TimberStatusObserver.shared
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.2))
        )
    }

    private var statusColor: Color {
        switch status.state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        switch status.state {
        case .connected:
            return "Streaming"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Not connected"
        case .failed:
            return "Failed"
        }
    }
}

/// Observable status for Timber connection
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public class TimberStatusObserver: ObservableObject {
    public static let shared = TimberStatusObserver()

    public enum State {
        case disconnected
        case connecting
        case connected
        case failed
    }

    @Published public var state: State = .disconnected
    @Published public var connectedService: String?

    private init() {}

    public func update(state: State, service: String? = nil) {
        DispatchQueue.main.async {
            self.state = state
            self.connectedService = service
        }
    }
}

#if DEBUG
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct TimberStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TimberStatusView()

            // Simulate different states
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Streaming").font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))

            HStack {
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("Connecting...").font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
        }
        .padding()
    }
}
#endif
