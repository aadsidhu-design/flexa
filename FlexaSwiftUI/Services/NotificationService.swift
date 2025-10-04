import UserNotifications
import Foundation

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    private override init() {
        super.init()
        requestNotificationPermission()
    }
    
    deinit {
        // Cancel all pending notifications when service is deallocated
        cancelAllNotifications()
        print("🧹 [NotificationService] Deinitializing and cleaning up notifications")
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                FlexaLog.notifications.error("Notification permission error: \(error.localizedDescription)")
                return
            }
            FlexaLog.notifications.info("Notification permission \(granted ? "granted" : "denied")")
        }
    }
    
    func scheduleStreakReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Don't lose your streak! 🔥"
        content.body = "Keep your rehabilitation progress going strong"
        content.sound = .default
        
        // Schedule for 7 PM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "streak_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FlexaLog.notifications.error("Schedule streak reminder failed: \(error.localizedDescription)")
            } else {
                FlexaLog.notifications.info("Scheduled streak reminder at 19:00 daily")
            }
        }
    }
    
    func scheduleExerciseReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time for your exercises! 💪"
        content.body = "A few minutes of movement can make a big difference"
        content.sound = .default
        
        // Schedule for 2 PM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 14
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "exercise_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FlexaLog.notifications.error("Schedule exercise reminder failed: \(error.localizedDescription)")
            } else {
                FlexaLog.notifications.info("Scheduled exercise reminder at 14:00 daily")
            }
        }
    }
    
    func scheduleWeeklyMotivation() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Progress Check 📊"
        content.body = "See how much you've improved this week!"
        content.sound = .default
        
        // Schedule for Sunday 10 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 10
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly_motivation", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FlexaLog.notifications.error("Schedule weekly motivation failed: \(error.localizedDescription)")
            } else {
                FlexaLog.notifications.info("Scheduled weekly motivation Sunday 10:00")
            }
        }
    }
    
    func scheduleMissedDayReminder() {
        // Only trigger if user hasn't exercised in 2 days
        let content = UNMutableNotificationContent()
        content.title = "We miss you! 🌟"
        content.body = "Your rehabilitation journey is waiting for you"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 172800, repeats: false) // 48 hours
        let request = UNNotificationRequest(identifier: "missed_day_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                FlexaLog.notifications.error("Schedule missed day reminder failed: \(error.localizedDescription)")
            } else {
                FlexaLog.notifications.info("Scheduled missed day reminder in 48h")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        FlexaLog.notifications.info("Cancelled all pending notifications")
    }
    
    func setupDefaultNotifications() {
        FlexaLog.notifications.info("Setting up default notifications")
        scheduleStreakReminder()
        scheduleExerciseReminder()
        scheduleWeeklyMotivation()
    }
}
