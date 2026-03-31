import Foundation

#if DEBUG
import AppReveal
#endif

final class ExampleStateContainer {

    static let shared = ExampleStateContainer()

    var isLoggedIn = true
    var userName = ExampleUserProfile.sample.name
    var userEmail = ExampleUserProfile.sample.email
    var selectedSection: ExampleSection = .orders
    var cartItemCount = 2

    private init() {}
}

#if DEBUG
extension ExampleStateContainer: StateProviding {
    func snapshot() -> [String: AnyCodable] {
        [
            "isLoggedIn": AnyCodable(isLoggedIn),
            "userName": AnyCodable(userName),
            "selectedSection": AnyCodable(selectedSection.rawValue),
            "cartItemCount": AnyCodable(cartItemCount),
        ]
    }
}
#endif
