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

    func testCatalogFiltersEasyFlowers() {
        let flowers = FlowerCatalog.filteredFlowers(searchText: "", filter: .easy)

        XCTAssertFalse(flowers.isEmpty)
        XCTAssertTrue(flowers.allSatisfy { $0.difficulty == 1 })
    }

    func testCatalogFiltersMexicoFlowers() {
        let flowers = FlowerCatalog.filteredFlowers(searchText: "", filter: .mexico)
        let ids = Set(flowers.map(\.id))

        XCTAssertTrue(ids.contains("cempasuchil"))
        XCTAssertTrue(ids.contains("girasol"))
        XCTAssertFalse(ids.contains("orquidea"))
    }

    func testSearchAndFilterCanCombine() {
        let flowers = FlowerCatalog.filteredFlowers(searchText: "rosa", filter: .fullSun)

        XCTAssertEqual(flowers.map(\.id), ["rosa"])
    }

    func testScannerConfidenceBandsStayReviewSafe() {
        XCTAssertEqual(IdentificationConfidenceBand(confidence: 60, isUncertain: true), .experimental)
        XCTAssertEqual(IdentificationConfidenceBand(confidence: 72, isUncertain: false), .possible)
        XCTAssertEqual(IdentificationConfidenceBand(confidence: 90, isUncertain: false), .probable)
        XCTAssertEqual(IdentificationConfidenceBand(confidence: 90, isUncertain: true).reviewSafeCopy, "Usa esto como pista, no como diagnostico.")
    }
}
