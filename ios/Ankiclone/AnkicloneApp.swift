import Observation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Which lesson a tapped notification should open.
@MainActor
@Observable
final class AppRouter {
  static let shared = AppRouter()
  var lessonDate: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  static let sync = SyncEngine()

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    Task { await AppDelegate.sync.registerDevice(token: token) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let date = response.notification.request.content.userInfo["lessonDate"] as? String
    await MainActor.run { AppRouter.shared.lessonDate = date }
  }
}

@main
struct AnkicloneApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environment(AppDelegate.sync)
        .environment(AppRouter.shared)
    }
    .modelContainer(for: [DeckRecord.self, NoteRecord.self, CardRecord.self, LessonRecord.self, PendingReview.self])
  }
}

extension Font {
  /// PingFang SC, so characters always use their simplified mainland forms.
  static func hanzi(_ size: CGFloat) -> Font { .custom("PingFang SC", size: size) }
}
