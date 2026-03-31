// Element model for UI element inventory

import Foundation

#if DEBUG

/// Type of UI element.
public enum ElementType: String, Codable {
    case button
    case textField
    case label
    case image
    case toggle
    case slider
    case stepper
    case picker
    case scrollView
    case tableView
    case collectionView
    case cell
    case navigationBar
    case tabBar
    case other
}

/// Describes a visible interactive element on screen.
public struct ElementInfo: Codable {
    public let id: String
    public let type: ElementType
    public let label: String?
    public let value: String?
    public let enabled: Bool
    public let visible: Bool
    public let tappable: Bool
    public let frame: ElementFrame
    public let containerId: String?
    public let actions: [String]
    /// How the id was derived: "explicit", "text", "semantics", "tooltip", "derived"
    public let idSource: String

    public struct ElementFrame: Codable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }
}

#endif
