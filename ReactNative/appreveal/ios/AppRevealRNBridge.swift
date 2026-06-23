// Main Swift coordinator for the React Native AppReveal module.
// Replaces AppReveal.swift — no #if DEBUG guard; the JS layer controls start/stop.

import Foundation
import UIKit

@objc(AppRevealRNBridge)
@MainActor
public final class AppRevealRNBridge: NSObject {

    @objc public static let shared = AppRevealRNBridge()

    private var server: MCPServer?

    private override init() {}

    @objc public var sessionToken: String? {
        server?.sessionToken
    }

    @objc public var url: String? {
        server?.url
    }

    @objc public var sessionURL: String? {
        server?.sessionURL
    }

    // MARK: - Lifecycle

    @objc public func start(port: Int) {
        if let server {
            let endpoint = server.sessionURL ?? server.url ?? "starting"
            print("[AppReveal] start ignored; already running at \(endpoint)")
            return
        }

        registerBuiltInTools()
        registerWebViewTools()
        let portValue: UInt16? = port > 0 ? UInt16(port) : nil
        let server = MCPServer(port: portValue)
        self.server = server
        if !server.start() {
            self.server = nil
        }
    }

    @objc public func stop() {
        server?.stop()
        server = nil
    }

    // MARK: - Screen

    @objc public func setScreen(key: String, title: String, confidence: Double) {
        ScreenResolver.shared.setJSScreen(key: key, title: title, confidence: confidence)
    }

    // MARK: - State

    @objc public func setState(_ state: [String: Any]) {
        StateBridge.shared.state = state.mapValues { AnyCodable($0) }
    }

    // MARK: - Navigation

    @objc public func setNavigationStack(_ routes: [Any], current: String, modals: [Any]) {
        let routeStrings = routes.compactMap { $0 as? String }
        let modalStrings = modals.compactMap { $0 as? String }
        StateBridge.shared.navigationStack = routeStrings
        StateBridge.shared.currentRoute = current
        StateBridge.shared.presentedModals = modalStrings
    }

    // MARK: - Feature flags

    @objc public func setFeatureFlags(_ flags: [String: Any]) {
        StateBridge.shared.featureFlags = flags.mapValues { AnyCodable($0) }
    }

    // MARK: - Network calls

    @objc public func captureNetworkCall(_ call: [String: Any]) {
        NetworkObserverService.shared.addCall(call)
    }

    // MARK: - Error capture

    @objc public func captureError(domain: String, message: String, stackTrace: String?) {
        DiagnosticsBridge.shared.captureError(domain: domain, message: message, stackTrace: stackTrace)
    }
}
