import UIKit

#if DEBUG
import AppReveal
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        #if DEBUG
        // One-line AppReveal integration
        AppReveal.start()

        // Register providers
        AppReveal.registerStateProvider(ExampleStateContainer.shared)
        AppReveal.registerNavigationProvider(ExampleRouter.shared)
        AppReveal.registerFeatureFlagProvider(ExampleFeatureFlags.shared)
        AppReveal.registerNetworkObservable(ExampleNetworkClient.shared)
        #endif

        return true
    }

    // MARK: - UISceneSession

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
