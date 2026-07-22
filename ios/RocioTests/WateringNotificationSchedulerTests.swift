import XCTest
import UserNotifications
@testable import Rocio

@MainActor
final class WateringNotificationSchedulerTests: XCTestCase {
    func testFirstCareReminderBecomesAvailableWithoutRequestingPermissionOnLoad() async {
        var didRequestAuthorization = false
        let controller = FirstCareReminderController(
            authorizationStatus: { .notDetermined },
            requestAuthorization: {
                didRequestAuthorization = true
                return true
            },
            refreshNotifications: { _ in }
        )

        await controller.refreshAuthorization(currentPlants: { [] })

        XCTAssertEqual(controller.state, .available)
        XCTAssertFalse(didRequestAuthorization)
    }

    func testFirstCareReminderSchedulesOnlyAfterExplicitGrantedTap() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        var didRequestAuthorization = false
        var scheduledPlantIDs: [UUID] = []
        let controller = FirstCareReminderController(
            authorizationStatus: { .notDetermined },
            requestAuthorization: {
                didRequestAuthorization = true
                return true
            },
            refreshNotifications: { plants in
                scheduledPlantIDs = plants.map(\.id)
            }
        )

        await controller.refreshAuthorization(currentPlants: { [plant] })
        XCTAssertTrue(scheduledPlantIDs.isEmpty)

        await controller.enable(currentPlants: { [plant] })

        XCTAssertTrue(didRequestAuthorization)
        XCTAssertEqual(scheduledPlantIDs, [plant.id])
        XCTAssertEqual(controller.state, .enabled)
    }

    func testFirstCareReminderDoesNotScheduleWhenPermissionIsDenied() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        var didSchedule = false
        let controller = FirstCareReminderController(
            authorizationStatus: { .notDetermined },
            requestAuthorization: { false },
            refreshNotifications: { _ in didSchedule = true }
        )

        await controller.refreshAuthorization(currentPlants: { [plant] })
        await controller.enable(currentPlants: { [plant] })

        XCTAssertEqual(controller.state, .denied)
        XCTAssertFalse(didSchedule)
    }

    func testFirstCareReminderReschedulesAfterAuthorizationIsEnabledInSettings() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        var status: UNAuthorizationStatus = .denied
        var scheduledPlantIDs: [UUID] = []
        let controller = FirstCareReminderController(
            authorizationStatus: { status },
            requestAuthorization: { false },
            refreshNotifications: { plants in
                scheduledPlantIDs = plants.map(\.id)
            }
        )

        await controller.refreshAuthorization(currentPlants: { [plant] })
        XCTAssertEqual(controller.state, .denied)
        XCTAssertTrue(scheduledPlantIDs.isEmpty)

        status = .authorized
        await controller.refreshAuthorization(currentPlants: { [plant] })

        XCTAssertEqual(controller.state, .enabled)
        XCTAssertEqual(scheduledPlantIDs, [plant.id])
    }

    func testFirstCareReminderReadsCurrentPlantsAfterAuthorizationCompletes() async {
        let originalPlant = GardenPlant(flowerId: "rosa", nickname: "Original")
        let currentPlant = GardenPlant(flowerId: "lavanda", nickname: "Current")
        let authorizationGate = NotificationAuthorizationGate()
        var currentPlants = [originalPlant]
        var scheduledPlantIDs: [UUID] = []
        let controller = FirstCareReminderController(
            authorizationStatus: { .notDetermined },
            requestAuthorization: {
                await authorizationGate.request()
            },
            refreshNotifications: { plants in
                scheduledPlantIDs = plants.map(\.id)
            }
        )

        await controller.refreshAuthorization(currentPlants: { currentPlants })
        let enableTask = Task {
            await controller.enable(currentPlants: { currentPlants })
        }
        await authorizationGate.waitUntilRequested()

        currentPlants = [currentPlant]
        await authorizationGate.resolve(granted: true)
        await enableTask.value

        XCTAssertEqual(scheduledPlantIDs, [currentPlant.id])
        XCTAssertEqual(controller.state, .enabled)
    }

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

private actor NotificationAuthorizationGate {
    private var didRequest = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var resolution: Bool?
    private var resolutionWaiters: [CheckedContinuation<Bool, Never>] = []

    func request() async -> Bool {
        didRequest = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if let resolution { return resolution }
        return await withCheckedContinuation { continuation in
            resolutionWaiters.append(continuation)
        }
    }

    func waitUntilRequested() async {
        guard !didRequest else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resolve(granted: Bool) {
        guard resolution == nil else { return }
        resolution = granted
        let waiters = resolutionWaiters
        resolutionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: granted) }
    }
}
