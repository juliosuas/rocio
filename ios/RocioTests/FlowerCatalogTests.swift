import XCTest
@testable import Rocio

final class FlowerCatalogTests: XCTestCase {
    func testCatalogHasExpectedFlowers() {
        XCTAssertEqual(FlowerCatalog.all.count, 15)
        XCTAssertNotNil(FlowerCatalog.flower(id: "rosa"))
        XCTAssertNotNil(FlowerCatalog.flower(id: "cempasuchil"))
    }

    func testWateringIntervalsArePositive() {
        for flower in FlowerCatalog.all {
            XCTAssertGreaterThan(flower.waterDays, 0, flower.name)
            XCTAssertGreaterThan(flower.waterMl, 0, flower.name)
        }
    }
}

