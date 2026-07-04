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
}

