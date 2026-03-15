import UIKit

#if DEBUG
import AppReveal
#endif

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let ordersNav = UINavigationController(rootViewController: OrdersListViewController())
        ordersNav.tabBarItem = UITabBarItem(title: "Orders", image: UIImage(systemName: "list.bullet"), tag: 0)

        let catalogNav = UINavigationController(rootViewController: CatalogViewController())
        catalogNav.tabBarItem = UITabBarItem(title: "Catalog", image: UIImage(systemName: "square.grid.2x2"), tag: 1)

        let profileNav = UINavigationController(rootViewController: ProfileViewController())
        profileNav.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person.circle"), tag: 2)

        let settingsNav = UINavigationController(rootViewController: SettingsViewController())
        settingsNav.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 3)

        let webViewNav = UINavigationController(rootViewController: WebViewDemoViewController())
        webViewNav.tabBarItem = UITabBarItem(title: "Web", image: UIImage(systemName: "globe"), tag: 4)

        viewControllers = [ordersNav, catalogNav, profileNav, settingsNav, webViewNav]

        // Check if user is logged in; if not, present login
        if !ExampleStateContainer.shared.isLoggedIn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let loginVC = LoginViewController()
                loginVC.modalPresentationStyle = .fullScreen
                self.present(loginVC, animated: true)
            }
        }
    }
}
