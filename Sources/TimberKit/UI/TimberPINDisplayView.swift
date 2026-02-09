import SwiftUI

// MARK: - Platform Colors

#if os(iOS) || os(tvOS)
import UIKit
private let secondaryBackgroundColor = Color(UIColor.secondarySystemBackground)
private let backgroundColor = Color(UIColor.systemBackground)
#elseif os(macOS)
import AppKit
private let secondaryBackgroundColor = Color(NSColor.controlBackgroundColor)
private let backgroundColor = Color(NSColor.windowBackgroundColor)
#else
private let secondaryBackgroundColor = Color.gray.opacity(0.2)
private let backgroundColor = Color.white
#endif

/// SwiftUI view for displaying the authentication PIN on the viewer side
///
/// This view shows a large, clear PIN display that users can read
/// and enter on their app device.
///
/// ```swift
/// @State private var displayedPIN: String?
/// @State private var connectingApp: String?
///
/// var body: some View {
///     ZStack {
///         myViewerContent
///
///         if let pin = displayedPIN, let app = connectingApp {
///             TimberPINDisplayView(pin: pin, appName: app) {
///                 displayedPIN = nil
///             }
///         }
///     }
/// }
/// ```
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct TimberPINDisplayView: View {
    let pin: String
    let appName: String
    let onCancel: () -> Void

    public init(pin: String, appName: String, onCancel: @escaping () -> Void) {
        self.pin = pin
        self.appName = appName
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Connection Request")
                    .font(.headline)

                Text("from \(appName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // PIN display
            VStack(spacing: 12) {
                Text("Enter this PIN on your device")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { index, digit in
                        Text(String(digit))
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .frame(width: 48, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(secondaryBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            )
                    }
                }
            }
            .padding(.vertical, 16)

            // Cancel button
            Button(role: .cancel) {
                onCancel()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(radius: 20)
        )
        .frame(maxWidth: 360)
    }
}

/// Overlay modifier for easily showing PIN display
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public extension View {
    /// Overlay a PIN display when a PIN needs to be shown
    ///
    /// ```swift
    /// myView
    ///     .timberPINOverlay(pin: viewModel.displayedPIN, appName: viewModel.connectingApp) {
    ///         viewModel.cancelPINDisplay()
    ///     }
    /// ```
    func timberPINOverlay(
        pin: String?,
        appName: String?,
        onCancel: @escaping () -> Void
    ) -> some View {
        ZStack {
            self

            if let pin = pin, let app = appName {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                TimberPINDisplayView(pin: pin, appName: app, onCancel: onCancel)
            }
        }
    }
}

#if DEBUG
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct TimberPINDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()

            TimberPINDisplayView(
                pin: "123456",
                appName: "MyApp"
            ) {
                print("Cancelled")
            }
        }
    }
}
#endif
