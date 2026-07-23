import XCTest
import UIKit
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

    func testPickerDataIsDownsampledBeforeScannerStateRetainsIt() async throws {
        let source = image(width: 1_200, height: 600, color: .systemPink)
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))

        let preparedImage = await ScannerImageProcessor().prepare(
            data: data,
            maximumPixelDimension: 320
        )
        let prepared = try XCTUnwrap(preparedImage)
        let dimensions = ScannerImageProcessor.pixelDimensions(of: prepared)

        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), 320)
        XCTAssertEqual(dimensions.width / dimensions.height, 2, accuracy: 0.03)
        XCTAssertEqual(prepared.imageOrientation, .up)
    }

    func testCameraImageIsDownsampledWithoutLosingItsOrientation() async throws {
        let rendered = image(width: 1_200, height: 600, color: .systemGreen)
        let cgImage = try XCTUnwrap(rendered.cgImage)
        let cameraImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let preparedImage = await ScannerImageProcessor().prepare(
            image: cameraImage,
            maximumPixelDimension: 300
        )
        let prepared = try XCTUnwrap(preparedImage)
        let dimensions = ScannerImageProcessor.pixelDimensions(of: prepared)

        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), 300)
        XCTAssertEqual(prepared.imageOrientation, .right)
    }

    func testOnDeviceChoiceProducesLocalResultWithoutAnAuthenticatedSession() async throws {
        let source = image(width: 240, height: 240, color: .systemRed)
        let sessionStore = SessionStore(configuration: nil)

        let identification = await HybridFlowerIdentifier().identify(
            image: source,
            destination: .onDevice,
            sessionStore: sessionStore
        )
        let result = try XCTUnwrap(identification)

        XCTAssertEqual(result.provider, .onDevice)
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertNil(result.remainingCloudScans)
    }

    func testCloudChoiceUsesFallbackWhenCloudSessionIsUnavailable() async throws {
        let source = image(width: 240, height: 240, color: .systemPurple)
        let sessionStore = SessionStore(configuration: nil)

        let identification = await HybridFlowerIdentifier().identify(
            image: source,
            destination: .cloud,
            sessionStore: sessionStore
        )
        let result = try XCTUnwrap(identification)

        XCTAssertEqual(result.provider, .onDeviceFallback)
    }

    func testEveryPreparedPhotoCreatesANewConsentDecision() {
        let first = image(width: 120, height: 120, color: .systemPink)
        let second = image(width: 120, height: 120, color: .systemBlue)
        var consent = ScannerPhotoConsentState()

        consent.begin(first)
        XCTAssertTrue(consent.isPresented)
        XCTAssertNotNil(consent.takeImage())
        XCTAssertFalse(consent.isPresented)

        consent.begin(second)
        XCTAssertTrue(consent.isPresented)
        consent.discard()
        XCTAssertFalse(consent.isPresented)
    }

    func testNewPreparationOrCancelInvalidatesEveryOlderImageGeneration() {
        var generations = ScannerImagePreparationGeneration()

        let slowPhoto = generations.begin()
        let replacementPhoto = generations.begin()

        XCTAssertFalse(generations.isCurrent(slowPhoto))
        XCTAssertTrue(generations.isCurrent(replacementPhoto))

        _ = generations.begin() // Cancel/discard uses the same invalidation boundary.

        XCTAssertFalse(generations.isCurrent(replacementPhoto))
    }

    func testPickerLoadCompletionClearsOnlyItsSelectionAndAllowsTheSameAssetAgain() {
        var selection = ScannerPhotoPickerSelectionState<String>()
        selection.item = "first-photo"

        selection.item = "replacement-photo"
        XCTAssertFalse(selection.clearAfterLoading("first-photo"))
        XCTAssertEqual(selection.item, "replacement-photo")

        XCTAssertTrue(selection.clearAfterLoading("replacement-photo"))
        XCTAssertNil(selection.item)

        selection.item = "replacement-photo"
        XCTAssertEqual(selection.item, "replacement-photo")
    }

    func testExternalCandidateBuildsDurablePlantIDIdentity() {
        let candidate = IdentificationResult.ExternalCandidate(
            id: "plant-id-123",
            sourceID: "plant-id-123",
            name: "Swiss cheese plant",
            scientificName: "Monstera deliciosa",
            confidence: 91,
            rank: "species",
            nameLocale: "en"
        )

        XCTAssertEqual(candidate.identity.source, .plantID)
        XCTAssertEqual(candidate.identity.sourceID, "plant-id-123")
        XCTAssertEqual(candidate.identity.commonName, "Swiss cheese plant")
        XCTAssertEqual(candidate.identity.scientificName, "Monstera deliciosa")
        XCTAssertEqual(candidate.identity.rank, "species")
        XCTAssertEqual(candidate.identity.nameLocale, "en")
    }

    func testTopExternalSuggestionIsNotRepeatedAsAnAlternateSaveChoice() throws {
        let flower = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))
        let top = IdentificationResult.ExternalCandidate(
            id: "plant-id-rose",
            sourceID: "plant-id-rose",
            name: "Rose",
            scientificName: "Rosa spp.",
            confidence: 96,
            rank: "species",
            nameLocale: "en"
        )
        let alternate = IdentificationResult.ExternalCandidate(
            id: "plant-id-camellia",
            sourceID: "plant-id-camellia",
            name: "Camellia",
            scientificName: "Camellia japonica",
            confidence: 72,
            rank: "species",
            nameLocale: "en"
        )
        let result = IdentificationResult(
            flower: flower,
            confidence: top.confidence,
            candidates: [],
            isUncertain: false,
            provider: .cloud,
            externalName: top.name,
            externalScientificName: top.scientificName,
            externalCandidates: [top, alternate],
            identity: top.identity,
            careProfile: .bundled(flower),
            isPlant: true
        )

        XCTAssertEqual(result.alternateExternalCandidates, [alternate])
    }

    func testCloudNotPlantResultCannotBeSavedToGarden() throws {
        let flower = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))
        let result = IdentificationResult(
            flower: flower,
            confidence: 96,
            candidates: [],
            isUncertain: true,
            provider: .cloud,
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "provider-candidate",
                commonName: "Candidate"
            ),
            careProfile: PlantCareProfile(source: .plantID),
            isPlant: false
        )

        XCTAssertFalse(result.canSaveToGarden)
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

    private func image(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
