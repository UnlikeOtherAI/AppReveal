import SwiftUI

#if DEBUG

@MainActor
public struct AppRevealDebugOverlay: View {
    @State private var isExpanded = false
    @State private var refreshID = UUID()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(
                action: { isExpanded.toggle() },
                label: {
                    Label(statusTitle, systemImage: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                }
            )
            .buttonStyle(.borderedProminent)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    row("Endpoint", AppReveal.sessionURL ?? AppReveal.url ?? "Stopped")
                    row("Session", AppReveal.sessionToken.map(redactToken) ?? "Unavailable")
                    row("Screen", currentScreen.screenKey)
                    row("Title", currentScreen.screenTitle)
                    row("Source", currentScreen.source)

                    Button("Refresh") {
                        refreshID = UUID()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                }
                .id(refreshID)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }

    private var statusTitle: String {
        AppReveal.url == nil ? "AppReveal stopped" : "AppReveal running"
    }

    private var statusIcon: String {
        AppReveal.url == nil ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
    }

    private var currentScreen: ScreenInfo {
        #if os(iOS)
        return ScreenResolver.shared.resolve()
        #elseif os(macOS)
        return MacOSScreenResolver.shared.resolve()
        #else
        return ScreenInfo(
            screenKey: "unknown",
            screenTitle: "Unknown",
            frameworkType: "unknown",
            controllerChain: [],
            activeTab: nil,
            navigationDepth: 0,
            presentedModals: [],
            confidence: 0,
            source: "unavailable",
            appBarTitle: nil
        )
        #endif
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func redactToken(_ token: String) -> String {
        guard token.count > 8 else { return "Present" }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }
}

#endif
