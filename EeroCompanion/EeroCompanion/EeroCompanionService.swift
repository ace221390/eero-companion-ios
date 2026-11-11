import Foundation
import UserNotifications
import BackgroundTasks

public final class EeroCompanionService {
	public static let shared = EeroCompanionService()
	private init() {}

	private let ntfyURL = URL(string: "https://ntfy.sh/eero-ipad-xk9q2mn4rj/json?since=10m")!
	private let ackURL  = URL(string: "https://ntfy.sh/eero-ack-xk9q2mn4rj")!
	static let bgTaskID = "com.eero.companion.refresh"

	static let passwordKey   = "eero_last_password"
	static let timestampKey  = "eero_last_timestamp"
	static let newPasswordNotification = Notification.Name("EeroNewPassword")

	private var seenIDs = Set<String>()

	public func start() {
		requestNotificationPermission()
		poll()
		scheduleBGRefresh()
	}

	public func handleBGRefresh(task: BGAppRefreshTask) {
		scheduleBGRefresh()
		fetchOnce { done in task.setTaskCompleted(success: done) }
	}

	// ── Polling ───────────────────────────────────────────────────────────

	private func poll() {
		var req = URLRequest(url: ntfyURL, timeoutInterval: 70)
		req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
			guard let self = self else { return }
			if error != nil {
				DispatchQueue.global().asyncAfter(deadline: .now() + 10) { self.poll() }
				return
			}
			if let data = data { self.processChunk(data) }
			DispatchQueue.global().asyncAfter(deadline: .now() + 1) { self.poll() }
		}.resume()
	}

	private func fetchOnce(completion: @escaping (Bool) -> Void) {
		var req = URLRequest(url: ntfyURL, timeoutInterval: 25)
		req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
			if let data = data { self?.processChunk(data) }
			completion(error == nil)
		}.resume()
	}

	// ── Parsing ───────────────────────────────────────────────────────────

	private func processChunk(_ data: Data) {
		guard let text = String(data: data, encoding: .utf8) else { return }
		for line in text.components(separatedBy: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty,
				  let lineData = trimmed.data(using: .utf8),
				  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
				  json["event"] as? String == "message",
				  let id = json["id"] as? String, !seenIDs.contains(id)
			else { continue }
			seenIDs.insert(id)
			var msg = (json["message"] as? String ?? "").trimmingCharacters(in: .whitespaces)
			if msg.contains(":") {
				msg = String(msg.split(separator: ":", maxSplits: 1).last ?? Substring(msg))
					.trimmingCharacters(in: .whitespaces)
			}
			guard !msg.isEmpty else { continue }
			savePassword(msg)
			showNotification(password: msg)
			sendAck(password: msg)
		}
	}

	// ── Storage ───────────────────────────────────────────────────────────

	private func savePassword(_ password: String) {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		let timestamp = formatter.string(from: Date())

		UserDefaults.standard.set(password,  forKey: Self.passwordKey)
		UserDefaults.standard.set(timestamp, forKey: Self.timestampKey)

		DispatchQueue.main.async {
			NotificationCenter.default.post(
				name: Self.newPasswordNotification,
				object: nil,
				userInfo: ["password": password, "timestamp": timestamp]
			)
		}
	}

	// ── Notification ──────────────────────────────────────────────────────

	private func requestNotificationPermission() {
		UNUserNotificationCenter.current()
			.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
	}

	private func showNotification(password: String) {
		let content = UNMutableNotificationContent()
		content.title = "WiFi Password Changed"
		content.body  = "New password: \(password)"
		content.sound = .default
		UNUserNotificationCenter.current().add(
			UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil),
			withCompletionHandler: nil)
	}

	// ── ACK ───────────────────────────────────────────────────────────────

	private func sendAck(password: String) {
		var req = URLRequest(url: ackURL, timeoutInterval: 10)
		req.httpMethod = "POST"
		req.httpBody   = "ipad_ack:\(password)".data(using: .utf8)
		req.setValue("iPad ACK",         forHTTPHeaderField: "Title")
		req.setValue("white_check_mark", forHTTPHeaderField: "Tags")
		URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
	}

	// ── Background refresh ────────────────────────────────────────────────

	private func scheduleBGRefresh() {
		let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
		request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
		try? BGTaskScheduler.shared.submit(request)
	}
}
