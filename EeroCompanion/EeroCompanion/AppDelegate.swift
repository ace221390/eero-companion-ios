import UIKit
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?

	func application(_ application: UIApplication,
					 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		BGTaskScheduler.shared.register(forTaskWithIdentifier: EeroCompanionService.bgTaskID, using: nil) { task in
			EeroCompanionService.shared.handleBGRefresh(task: task as! BGAppRefreshTask)
		}
		EeroCompanionService.shared.start()

		window = UIWindow(frame: UIScreen.main.bounds)
		window?.rootViewController = PasswordViewController()
		window?.makeKeyAndVisible()
		return true
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		EeroCompanionService.shared.start()
	}
}

// ── Password display screen ───────────────────────────────────────────────────

class PasswordViewController: UIViewController {

	private let passwordLabel: UILabel = {
		let l = UILabel()
		l.text = "—"
		l.font = UIFont.monospacedSystemFont(ofSize: 30, weight: .bold)
		l.textColor = UIColor(red: 0, green: 0.9, blue: 0.46, alpha: 1)
		l.textAlignment = .center
		l.numberOfLines = 0
		l.isUserInteractionEnabled = true
		l.translatesAutoresizingMaskIntoConstraints = false
		return l
	}()

	private let timestampLabel: UILabel = {
		let l = UILabel()
		l.font = UIFont.systemFont(ofSize: 13)
		l.textColor = UIColor(white: 0.4, alpha: 1)
		l.textAlignment = .center
		l.translatesAutoresizingMaskIntoConstraints = false
		return l
	}()

	private let statusLabel: UILabel = {
		let l = UILabel()
		l.text = "Watching for WiFi password changes…"
		l.font = UIFont.systemFont(ofSize: 13)
		l.textColor = UIColor(white: 0.35, alpha: 1)
		l.textAlignment = .center
		l.translatesAutoresizingMaskIntoConstraints = false
		return l
	}()

	private let copyHintLabel: UILabel = {
		let l = UILabel()
		l.text = "Long-press password to copy"
		l.font = UIFont.systemFont(ofSize: 11)
		l.textColor = UIColor(white: 0.25, alpha: 1)
		l.textAlignment = .center
		l.translatesAutoresizingMaskIntoConstraints = false
		return l
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = UIColor(white: 0.06, alpha: 1)
		buildLayout()
		loadSavedPassword()

		// Long press on password label → copy to clipboard
		let lp = UILongPressGestureRecognizer(target: self, action: #selector(copyPassword))
		passwordLabel.addGestureRecognizer(lp)

		// Listen for new passwords from the service
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleNewPassword(_:)),
			name: EeroCompanionService.newPasswordNotification,
			object: nil)
	}

	private func buildLayout() {
		let titleLabel = UILabel()
		titleLabel.text = "Eero Companion"
		titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
		titleLabel.textColor = .white
		titleLabel.textAlignment = .center
		titleLabel.translatesAutoresizingMaskIntoConstraints = false

		let sectionLabel = UILabel()
		sectionLabel.text = "CURRENT WIFI PASSWORD"
		sectionLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
		sectionLabel.textColor = UIColor(white: 0.5, alpha: 1)
		sectionLabel.textAlignment = .center
		sectionLabel.translatesAutoresizingMaskIntoConstraints = false

		let divider = UIView()
		divider.backgroundColor = UIColor(white: 0.15, alpha: 1)
		divider.translatesAutoresizingMaskIntoConstraints = false

		[titleLabel, sectionLabel, passwordLabel, timestampLabel, divider, statusLabel, copyHintLabel]
			.forEach { view.addSubview($0) }

		NSLayoutConstraint.activate([
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
			titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

			sectionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 60),
			sectionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

			passwordLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 16),
			passwordLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
			passwordLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

			timestampLabel.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 12),
			timestampLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

			divider.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 50),
			divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),

			statusLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 50),
			statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

			copyHintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
			copyHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
		])
	}

	private func loadSavedPassword() {
		if let pass = UserDefaults.standard.string(forKey: EeroCompanionService.passwordKey) {
			let ts = UserDefaults.standard.string(forKey: EeroCompanionService.timestampKey) ?? ""
			updateUI(password: pass, timestamp: ts)
		}
	}

	@objc private func handleNewPassword(_ notification: Notification) {
		guard let pass = notification.userInfo?["password"] as? String,
			  let ts   = notification.userInfo?["timestamp"] as? String else { return }
		updateUI(password: pass, timestamp: ts)
	}

	private func updateUI(password: String, timestamp: String) {
		passwordLabel.text = password
		timestampLabel.text = timestamp.isEmpty ? "" : "Received: \(timestamp)"
		statusLabel.text = "Active ✓"
		statusLabel.textColor = UIColor(red: 0, green: 0.9, blue: 0.46, alpha: 1)
	}

	@objc private func copyPassword(_ gesture: UILongPressGestureRecognizer) {
		guard gesture.state == .began,
			  let pass = passwordLabel.text, pass != "—" else { return }
		UIPasteboard.general.string = pass
		let banner = UILabel()
		banner.text = "Copied!"
		banner.font = UIFont.systemFont(ofSize: 13, weight: .medium)
		banner.textColor = .white
		banner.backgroundColor = UIColor(white: 0.2, alpha: 0.95)
		banner.textAlignment = .center
		banner.layer.cornerRadius = 10
		banner.clipsToBounds = true
		banner.frame = CGRect(x: 0, y: 0, width: 100, height: 36)
		banner.center = view.center
		view.addSubview(banner)
		UIView.animate(withDuration: 0.3, delay: 1.2, options: [], animations: {
			banner.alpha = 0
		}, completion: { _ in banner.removeFromSuperview() })
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
