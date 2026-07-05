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
        XCTAssertEqual(summary.statusLabel, "Toca regar")
        XCTAssertEqual(summary.nextWateringDate, calendar.date(byAdding: .day, value: 3, to: overdueDate))
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
}
