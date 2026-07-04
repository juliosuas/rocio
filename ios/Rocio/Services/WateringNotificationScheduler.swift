import Foundation
import UserNotifications

struct WateringNotificationScheduler {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func refreshNotifications(for plants: [GardenPlant], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for plant in plants {
            guard let flower = FlowerCatalog.flower(id: plant.flowerId) else { continue }
            let dueDate = Calendar.current.date(byAdding: .day, value: flower.waterDays, to: plant.lastWateredAt) ?? Date()
            let fireDate = scheduledFireDate(for: dueDate, now: now)
            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

            let content = UNMutableNotificationContent()
            content.title = "Rocio te recuerda regar"
            content.body = "\(plant.nickname) necesita \(flower.waterMl) ml de agua hoy."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: plant.id),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func scheduledFireDate(for dueDate: Date, now: Date = Date()) -> Date {
        let morning = morningDate(for: dueDate)
        if morning > now { return morning }
        return Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now
    }

    private func morningDate(for date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func notificationIdentifier(for id: UUID) -> String {
        "rocio.watering.\(id.uuidString)"
    }
}
