import Foundation
import UserNotifications

/// 앱이 열려 있을 때도 퀵알람 알림이 배너·소리로 보이게 한다(기본은 앱이 켜져 있으면 표시하지 않는다).
/// 무음 스위치·집중 모드는 시스템이 그대로 적용한다.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
