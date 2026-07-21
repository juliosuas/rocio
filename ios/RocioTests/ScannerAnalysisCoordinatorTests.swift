import XCTest
@testable import Rocio

@MainActor
final class ScannerAnalysisCoordinatorTests: XCTestCase {
    func testSlowerPreviousRequestCannotReplaceLatestResult() async {
        let coordinator = ScannerAnalysisCoordinator()
        let firstResult = result(flowerID: "rosa")
        let latestResult = result(flowerID: "tulipan")
        let firstStarted = expectation(description: "First analysis started")
        let firstCompleted = expectation(description: "First analysis completed late")
        let latestCompleted = expectation(description: "Latest analysis completed")
        var finishFirst: CheckedContinuation<IdentificationResult?, Never>?

        coordinator.start {
            let result = await withCheckedContinuation { continuation in
                finishFirst = continuation
                firstStarted.fulfill()
            }
            firstCompleted.fulfill()
            return result
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        coordinator.start {
            latestCompleted.fulfill()
            return latestResult
        }
        await fulfillment(of: [latestCompleted], timeout: 1)

        XCTAssertEqual(coordinator.result, latestResult)
        XCTAssertFalse(coordinator.isProcessing)

        finishFirst?.resume(returning: firstResult)
        await fulfillment(of: [firstCompleted], timeout: 1)

        XCTAssertEqual(coordinator.result, latestResult)
        XCTAssertFalse(coordinator.isProcessing)
    }

    private func result(flowerID: String) -> IdentificationResult {
        let flower = FlowerCatalog.flower(id: flowerID)!
        return IdentificationResult(
            flower: flower,
            confidence: 90,
            candidates: [],
            isUncertain: false
        )
    }
}
