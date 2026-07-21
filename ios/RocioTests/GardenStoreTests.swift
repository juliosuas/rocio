import XCTest
@testable import Rocio

@MainActor
final class GardenStoreTests: XCTestCase {
    func testAddAndWaterPlant() {
        let store = GardenStore(plants: [])
        let flower = FlowerCatalog.all[0]

        store.add(flower)
        XCTAssertEqual(store.plants.count, 1)

        let plant = store.plants[0]
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.water(plant, at: newDate)

        XCTAssertEqual(store.plants[0].lastWateredAt, newDate)
    }

    func testUpdateNormalizesLocalPlantAndCloudUpsertPayload() {
        let original = GardenPlant(flowerId: "rosa", nickname: "Original")
        let store = GardenStore(plants: [original])
        var upsertedPlants: [GardenPlant] = []
        store.cloudChangeHandler = { change in
            guard case let .upsert(plant) = change else { return }
            upsertedPlants.append(plant)
        }
        let composedEmoji = "👨‍👩‍👧‍👦"
        let expectedNickname = String(repeating: composedEmoji, count: 11)
        let expectedNotes = String(repeating: composedEmoji, count: 285)
        XCTAssertEqual(composedEmoji.unicodeScalars.count, 7)

        store.update(
            original,
            nickname: "  \(String(repeating: composedEmoji, count: 12))\n",
            status: .needsSun,
            notes: String(repeating: composedEmoji, count: 286)
        )

        XCTAssertEqual(store.plants[0].nickname, expectedNickname)
        XCTAssertEqual(store.plants[0].nickname.unicodeScalars.count, 77)
        XCTAssertEqual(store.plants[0].status, .needsSun)
        XCTAssertEqual(store.plants[0].notes, expectedNotes)
        XCTAssertEqual(store.plants[0].notes.unicodeScalars.count, 1_995)
        XCTAssertEqual(upsertedPlants.count, 1)
        XCTAssertEqual(upsertedPlants[0].nickname, expectedNickname)
        XCTAssertEqual(upsertedPlants[0].status, .needsSun)
        XCTAssertEqual(upsertedPlants[0].notes, expectedNotes)

        store.update(
            original,
            nickname: " \n\t ",
            status: .healthy,
            notes: "Short note"
        )

        XCTAssertEqual(store.plants[0].nickname, expectedNickname)
        XCTAssertEqual(upsertedPlants.count, 2)
        XCTAssertEqual(upsertedPlants[1].nickname, expectedNickname)
    }

    func testReplaceFromCloudNormalizesLegacyTextBeforePersisting() {
        let composedEmoji = "👨‍👩‍👧‍👦"
        let nicknamePrefix = String(repeating: "n", count: 79)
        let notesPrefix = String(repeating: "x", count: 1_999)
        let legacyPlant = GardenPlant(
            flowerId: "rosa",
            nickname: nicknamePrefix + composedEmoji,
            notes: notesPrefix + composedEmoji
        )
        let store = GardenStore(plants: [legacyPlant])
        defer { GardenPersistence.clearPlants() }

        store.replaceFromCloud([legacyPlant])

        XCTAssertEqual(store.plants[0].nickname, nicknamePrefix)
        XCTAssertEqual(store.plants[0].notes, notesPrefix)
        XCTAssertEqual(GardenPersistence.loadPlants(), store.plants)
    }

    func testGardenSummaryCountsAttentionAndNextWatering() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9))!
        let overdueDate = calendar.date(byAdding: .day, value: -5, to: now)!
        let freshDate = calendar.date(byAdding: .day, value: -1, to: now)!
        let plants = [
            GardenPlant(flowerId: "rosa", nickname: "Rosa", lastWateredAt: overdueDate),
            GardenPlant(flowerId: "lavanda", nickname: "Lavanda", lastWateredAt: freshDate)
        ]
        let store = GardenStore(plants: plants)

        let summary = store.summary(now: now)

        XCTAssertEqual(summary.plantCount, 2)
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.statusLabel, L10n.text("garden.summary.overdue", fallback: "Time to water"))
        XCTAssertEqual(summary.nextWateringDate, calendar.date(byAdding: .day, value: 3, to: overdueDate))
    }

    func testWateringScheduleSeparatesPlantOverdueByThreeDaysAndCountsIt() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
        let lastWateredAt = calendar.date(byAdding: .day, value: -6, to: now)!
        let overduePlant = GardenPlant(flowerId: "rosa", nickname: "Rosa", lastWateredAt: lastWateredAt)
        let store = GardenStore(plants: [overduePlant])

        let schedule = store.wateringSchedule(startingAt: now, calendar: calendar)

        XCTAssertEqual(schedule.overduePlants.map(\.id), [overduePlant.id])
        XCTAssertTrue(schedule.days.allSatisfy(\.plants.isEmpty))
        XCTAssertEqual(schedule.totalDueCount, 1)
    }

    func testWateringSchedulePreservesTodayThroughNextSixDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
        let dueToday = GardenPlant(
            flowerId: "rosa",
            nickname: "Rosa",
            lastWateredAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
        let dueOnLastVisibleDay = GardenPlant(
            flowerId: "orquidea",
            nickname: "Orquidea",
            lastWateredAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let dueOutsideVisibleRange = GardenPlant(
            flowerId: "orquidea",
            nickname: "Orquidea futura",
            lastWateredAt: now
        )
        let store = GardenStore(plants: [dueToday, dueOnLastVisibleDay, dueOutsideVisibleRange])

        let schedule = store.wateringSchedule(startingAt: now, calendar: calendar)

        XCTAssertEqual(schedule.days.count, 7)
        XCTAssertEqual(schedule.days[0].plants.map(\.id), [dueToday.id])
        XCTAssertEqual(schedule.days[6].plants.map(\.id), [dueOnLastVisibleDay.id])
        XCTAssertFalse(schedule.days.flatMap(\.plants).contains { $0.id == dueOutsideVisibleRange.id })
        XCTAssertEqual(schedule.totalDueCount, 2)
    }

    func testGardenExportPayloadContainsLocalData() {
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plant = GardenPlant(flowerId: "cempasuchil", nickname: "Cempasuchil")

        let payload = GardenExport.payload(plants: [plant], exportedAt: exportedAt)

        XCTAssertTrue(payload.contains("\"bundleIdentifier\" : \"com.juliosuas.rocio\""))
        XCTAssertTrue(payload.contains("\"flowerId\" : \"cempasuchil\""))
        XCTAssertTrue(payload.contains("\"plants\""))
    }

    func testResetClearsPlants() {
        let store = GardenStore(plants: [GardenPlant(flowerId: "rosa", nickname: "Rosa")])

        store.reset()

        XCTAssertTrue(store.plants.isEmpty)
    }

    func testLocalDataResetClearsPlantsAndCancelsPendingNotifications() {
        let store = GardenStore(plants: [GardenPlant(flowerId: "rosa", nickname: "Rosa")])
        var didCancelPendingNotifications = false
        let resetter = LocalDataResetter {
            didCancelPendingNotifications = true
        }

        resetter.reset(gardenStore: store)

        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertTrue(didCancelPendingNotifications)
    }

#if DEBUG
    func testDemoGardenIsEphemeralAndRestoresExistingPlants() {
        let existing = GardenPlant(flowerId: "girasol", nickname: "My sunflower")
        let store = GardenStore(plants: [existing])
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.beginDemo(now: now)

        XCTAssertTrue(store.isDemoMode)
        XCTAssertEqual(store.plants.count, 3)
        XCTAssertFalse(store.plants.contains(existing))

        store.water(store.plants[0], at: now)
        store.endDemo()

        XCTAssertFalse(store.isDemoMode)
        XCTAssertEqual(store.plants, [existing])
    }
#endif
}
