import UIKit
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var privacyOverlay: UIView?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupScreenshotAndCaptureProtection()
        return true
    }

    private func setupScreenshotAndCaptureProtection() {
        // Notification lors d'une tentative de capture d'écran
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        // Notification lors d'un enregistrement d'écran ou capture AirPlay
        if #available(iOS 11.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenCaptureChanged),
                name: UIScreen.capturedDidChangeNotification,
                object: nil
            )
        }
    }

    @objc private func didTakeScreenshot() {
        let alert = UIAlertController(
            title: "Capture d'écran interdite",
            message: "Pour protéger l'intimité et la sécurité des membres sur Chari, les captures d'écran sont strictement interdites.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "J'ai compris", style: .default, handler: nil))
        window?.rootViewController?.present(alert, animated: true, completion: nil)
    }

    @objc private func screenCaptureChanged() {
        if #available(iOS 11.0, *) {
            if UIScreen.main.isCaptured {
                showPrivacyOverlay(message: "Enregistrement d'écran interdit sur Chari")
            } else {
                hidePrivacyOverlay()
            }
        }
    }

    private func showPrivacyOverlay(message: String = "Contenu protégé") {
        guard let window = self.window, privacyOverlay == nil else { return }
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        
        let label = UILabel()
        label.text = "🔒 \(message)\nChari protège la vie privée de ses membres."
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -24)
        ])
        
        window.addSubview(overlay)
        self.privacyOverlay = overlay
    }

    private func hidePrivacyOverlay() {
        privacyOverlay?.removeFromSuperview()
        privacyOverlay = nil
    }

    func applicationWillResignActive(_ application: UIApplication) {
        showPrivacyOverlay(message: "Chari · Confidentialité protégée")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if #available(iOS 11.0, *), UIScreen.main.isCaptured {
            return
        }
        hidePrivacyOverlay()
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}
