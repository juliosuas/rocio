import Foundation
import UserNotifications

struct WateringNotificationPlan: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

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
            guard let plan = notificationPlan(for: plant, now: now) else { continue }
            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireDate
            )

            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func notificationPlan(
        for plant: GardenPlant,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WateringNotificationPlan? {
        guard let intervalDays = plant.resolvedWateringIntervalDays,
              let dueDate = calendar.date(
                byAdding: .day,
                value: intervalDays,
                to: plant.lastWateredAt
              ) else {
            return nil
        }

        let body: String
        if let amount = plant.careProfile.waterAmountMl, amount > 0 {
            body = L10n.format(
                "notification.watering.body",
                fallback: "%@ needs %d ml of water today.",
                plant.displayName,
                amount
            )
        } else {
            body = L10n.format(
                "notification.watering.body.generic",
                fallback: "It is time to water %@.",
                plant.displayName
            )
        }

        return WateringNotificationPlan(
            identifier: notificationIdentifier(for: plant.id),
            fireDate: scheduledFireDate(for: dueDate, now: now, calendar: calendar),
            title: L10n.text("notification.watering.title", fallback: "Rocio watering reminder"),
            body: body
        )
    }

    func scheduledFireDate(
        for dueDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let morning = morningDate(for: dueDate, calendar: calendar)
        if morning > now { return morning }
        return calendar.date(byAdding: .minute, value: 1, to: now) ?? now
    }

    private func morningDate(for date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func notificationIdentifier(for id: UUID) -> String {
        "rocio.watering.\(id.uuidString)"
    }
}
