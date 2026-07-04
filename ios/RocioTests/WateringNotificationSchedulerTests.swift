import XCTest
@testable import Rocio

final class WateringNotificationSchedulerTests: XCTestCase {
    func testFutureDueDateSchedulesForNineInTheMorning() {
        let scheduler = WateringNotificationScheduler()
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 10, minute: 0))!
        let dueDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 18, minute: 0))!

        let fireDate = scheduler.scheduledFireDate(for: dueDate, now: now)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 30)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testOverduePlantSchedulesSoonInsteadOfInThePast() {
        let scheduler = WateringNotificationScheduler()
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 10, minute: 0))!
        let dueDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 18, minute: 0))!

        let fireDate = scheduler.scheduledFireDate(for: dueDate, now: now)

        XCTAssertGreaterThan(fireDate, now)
    }
}
