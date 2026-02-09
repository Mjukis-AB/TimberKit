import SwiftUI
import Network

/// Result of the pairing process
public enum TimberPairingResult: Equatable {
    case connected(TimberService)
    case cancelled
    case failed(String)

    public static func == (lhs: TimberPairingResult, rhs: TimberPairingResult) -> Bool {
        switch (lhs, rhs) {
        case (.connected(let a), .connected(let b)):
            return a == b
        case (.cancelled, .cancelled):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// SwiftUI view for discovering and connecting to Timber viewers
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct TimberPairingView: View {
    @StateObject private var viewModel = TimberPairingViewModel()
    private let onResult: (TimberPairingResult) -> Void

    public init(onResult: @escaping (TimberPairingResult) -> Void) {
        self.onResult = onResult
    }

    public var body: some View {
        NavigationView {
            List {
                statusSection
                servicesSection
                pinSection
            }
            .navigationTitle("Connect to Viewer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.stopSearching()
                        onResult(.cancelled)
                    }
                }
            }
            #endif
        }
        .onAppear {
            viewModel.startSearching()
        }
        .onDisappear {
            viewModel.stopSearching()
        }
        .onChange(of: viewModel.connectionResult) { result in
            if let result = result {
                onResult(result)
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                if viewModel.isSearching {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Searching for viewers...")
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("Not searching")
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var servicesSection: some View {
        Section {
            if viewModel.services.isEmpty {
                Text("No viewers found")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.services) { service in
                    Button {
                        viewModel.connect(to: service)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(service.name)
                                    .font(.headline)
                                if let app = service.metadata["app"] {
                                    Text(app)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if viewModel.isConnecting && viewModel.selectedService?.id == service.id {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(viewModel.isConnecting)
                }
            }
        } header: {
            Text("Available Viewers")
        }
    }

    @ViewBuilder
    private var pinSection: some View {
        if viewModel.showPINEntry {
            Section {
                TextField("Enter PIN", text: $viewModel.pinInput)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.roundedBorder)

                Button("Submit") {
                    viewModel.submitPIN()
                }
                .disabled(viewModel.pinInput.count != PINGenerator.defaultLength)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Enter the \(PINGenerator.defaultLength)-digit PIN shown on the viewer")
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
class TimberPairingViewModel: ObservableObject, TimberAuthDelegate {
    private let browser = TimberBrowser()
    private var currentHandler: SecureStreamHandler?
    private var pinCompletion: ((String?) -> Void)?

    @Published var services: [TimberService] = []
    @Published var isSearching = false
    @Published var isConnecting = false
    @Published var selectedService: TimberService?
    @Published var showPINEntry = false
    @Published var pinInput = ""
    @Published var connectionResult: TimberPairingResult?
    @Published var errorMessage: String?

    init() {
        browser.onServicesChanged = { [weak self] services in
            DispatchQueue.main.async {
                self?.services = services
            }
        }
    }

    func startSearching() {
        browser.startBrowsing()
        isSearching = true
    }

    func stopSearching() {
        browser.stopBrowsing()
        isSearching = false
    }

    func connect(to service: TimberService) {
        selectedService = service
        isConnecting = true
        showPINEntry = false
        pinInput = ""
        errorMessage = nil

        // Create handler with auth enabled and self as delegate
        let handler = browser.connect(
            to: service,
            authDelegate: self,
            authEnabled: true
        )
        currentHandler = handler

        // Monitor connection state
        handler.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateChange(state)
            }
        }
    }

    private func handleStateChange(_ state: ConnectionState) {
        switch state {
        case .connected:
            // Auth succeeded, set as global handler
            if let handler = currentHandler {
                Timber.streamHandler = handler
            }
            isConnecting = false
            showPINEntry = false
            if let service = selectedService {
                connectionResult = .connected(service)
            }

        case .failed(let message):
            isConnecting = false
            showPINEntry = false
            errorMessage = message
            connectionResult = .failed(message)

        case .authenticating(let phase):
            // Update UI based on auth phase
            switch phase {
            case .awaitingPINInput:
                // PIN entry is handled via delegate
                break
            default:
                break
            }

        case .connecting, .disconnected:
            break
        }
    }

    func submitPIN() {
        guard !pinInput.isEmpty else { return }

        // Call the stored completion with the entered PIN
        pinCompletion?(pinInput)
        pinCompletion = nil
        showPINEntry = false
        isConnecting = true
    }

    func cancelPINEntry() {
        pinCompletion?(nil)
        pinCompletion = nil
        showPINEntry = false
        isConnecting = false
        currentHandler?.close()
        currentHandler = nil
    }

    // MARK: - TimberAuthDelegate

    func timber(
        _ handler: SecureStreamHandler,
        requiresPINFor serviceName: String,
        completion: @escaping (String?) -> Void
    ) {
        pinCompletion = completion
        isConnecting = false
        showPINEntry = true
    }

    func timber(_ handler: SecureStreamHandler, didAuthenticateTo serviceName: String) {
        // Handled via onStateChange
    }

    func timber(_ handler: SecureStreamHandler, authenticationFailedWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

#if DEBUG
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct TimberPairingView_Previews: PreviewProvider {
    static var previews: some View {
        TimberPairingView { result in
            print("Result: \(result)")
        }
    }
}
#endif
