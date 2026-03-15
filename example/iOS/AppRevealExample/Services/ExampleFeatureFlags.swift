import Foundation

#if DEBUG
import AppReveal
#endif

class ExampleFeatureFlags {

    static let shared = ExampleFeatureFlags()

    private let flags: [String: Any] = [
        "new_checkout_flow": true,
        "dark_mode_v2": false,
        "catalog_grid_layout": true,
        "order_tracking_map": false,
        "push_promo_enabled": true,
        "max_cart_items": 50,
        "api_version": "v2",
        "ab_test_group": "B",
    ]

    private init() {}

    func isEnabled(_ flag: String) -> Bool {
        flags[flag] as? Bool ?? false
    }
}

#if DEBUG
extension ExampleFeatureFlags: FeatureFlagProviding {
    func allFlags() -> [String: AnyCodable] {
        flags.mapValues { AnyCodable($0) }
    }
}
#endif
