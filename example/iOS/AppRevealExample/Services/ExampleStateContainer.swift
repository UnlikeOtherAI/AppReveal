import Foundation

#if DEBUG
import AppReveal
#endif

class ExampleStateContainer {

    static let shared = ExampleStateContainer()

    var isLoggedIn: Bool = false
    var userEmail: String = ""
    var userName: String = "Test User"
    var selectedTab: Int = 0
    var cartItemCount: Int = 2
    var lastSyncDate: Date = Date()

    private init() {}
}

#if DEBUG
extension ExampleStateContainer: StateProviding {
    func snapshot() -> [String: AnyCodable] {
        [
            "isLoggedIn": AnyCodable(isLoggedIn),
            "userEmail": AnyCodable(userEmail),
            "userName": AnyCodable(userName),
            "selectedTab": AnyCodable(selectedTab),
            "cartItemCount": AnyCodable(cartItemCount),
            "lastSyncDate": AnyCodable(lastSyncDate.ISO8601Format()),
        ]
    }
}
#endif
