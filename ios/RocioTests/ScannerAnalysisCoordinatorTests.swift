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

    func testCancellingReviewDoesNotMutateGardenOrRouteAwayAndKeepsScanForRetry() throws {
        let identification = result(flowerID: "rosa")
        let scanImage = image(width: 120, height: 120, color: .systemPink)
        var presentation = ScannerPresentationState()
        presentation.acceptPreparedImage(scanImage)
        XCTAssertTrue(presentation.beginReview(
            result: identification,
            identity: identification.identity,
            careProfile: identification.careProfile,
            confidence: identification.confidence
        ))

        let store = GardenStore(plants: [])
        let router = AppRouter()
        router.selectedTab = .scanner

        presentation.cancelReview()

        XCTAssertNil(presentation.reviewDraft)
        XCTAssertNotNil(presentation.selectedImage)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(router.selectedTab, .scanner)
    }

    func testScanReviewKeepsProviderIdentitySeparateFromSpecimenNickname() {
        let identity = PlantIdentity(
            source: .plantID,
            sourceID: "plant-id-monstera",
            commonName: "Swiss cheese plant",
            scientificName: "Monstera deliciosa",
            rank: "species",
            nameLocale: "en"
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = ScannedPlantReviewDraft(
            identity: identity,
            careProfile: PlantCareProfile(source: .plantID, fetchedAt: fetchedAt),
            confidence: 91,
            provider: .cloud
        )
        let store = GardenStore(plants: [])
        let router = AppRouter()
        router.selectedTab = .scanner

        let added = ScannerFirstCareFlow.addToGarden(
            draft: draft,
            nickname: "Office Monstera",
            wateringSelection: .medium,
            gardenStore: store,
            router: router,
            at: fetchedAt
        )

        XCTAssertEqual(added?.nickname, "Office Monstera")
        XCTAssertEqual(added?.identity, identity)
        XCTAssertEqual(added?.careProfile.wateringPreference, .medium)
        XCTAssertEqual(added?.careProfile.source, .plantID)
        XCTAssertEqual(added?.careProfile.fetchedAt, fetchedAt)
        XCTAssertEqual(store.plants.count, 1)
        XCTAssertEqual(store.plants.first, added)
        XCTAssertEqual(router.selectedTab, .garden)
    }

    func testUserConfirmedScanCareOverridesExactValuesWithoutInventingPrecision() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = ScannedPlantReviewDraft(
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "plant-id-rose",
                commonName: "Rose",
                scientificName: "Rosa spp."
            ),
            careProfile: PlantCareProfile(
                wateringIntervalDays: 4,
                waterAmountMl: 180,
                source: .bundled,
                fetchedAt: fetchedAt
            ),
            confidence: 94,
            provider: .cloud
        )

        let userConfirmed = draft.reviewedCareProfile(wateringSelection: .dry)
        XCTAssertEqual(userConfirmed.wateringPreference, .dry)
        XCTAssertNil(userConfirmed.wateringIntervalDays)
        XCTAssertNil(userConfirmed.waterAmountMl)
        XCTAssertEqual(userConfirmed.reminderIntervalDays, 14)
        XCTAssertEqual(userConfirmed.source, .bundled)
        XCTAssertEqual(userConfirmed.fetchedAt, fetchedAt)

        let noUserPreference = draft.reviewedCareProfile(wateringSelection: .notSet)
        XCTAssertNil(noUserPreference.wateringPreference)
        XCTAssertEqual(noUserPreference.wateringIntervalDays, 4)
        XCTAssertEqual(noUserPreference.waterAmountMl, 180)
    }

    func testEachScanReviewConfirmationAddsExactlyOneIndependentSpecimen() {
        let draft = ScannedPlantReviewDraft(
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "plant-id-prayer-plant",
                commonName: "Prayer plant",
                scientificName: "Maranta leuconeura"
            ),
            careProfile: PlantCareProfile(source: .plantID),
            confidence: 88,
            provider: .cloud
        )
        let store = GardenStore(plants: [])
        let router = AppRouter()

        let first = ScannerFirstCareFlow.addToGarden(
            draft: draft,
            nickname: "Bedroom plant",
            wateringSelection: .notSet,
            gardenStore: store,
            router: router
        )
        XCTAssertNotNil(first)
        XCTAssertEqual(store.plants.count, 1)

        router.selectedTab = .scanner
        let second = ScannerFirstCareFlow.addToGarden(
            draft: draft,
            nickname: "Kitchen plant",
            wateringSelection: .wet,
            gardenStore: store,
            router: router
        )

        XCTAssertNotNil(second)
        XCTAssertEqual(store.plants.count, 2)
        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertEqual(store.plants.map(\.identity), [draft.identity, draft.identity])
        XCTAssertEqual(store.plants.map(\.nickname), ["Bedroom plant", "Kitchen plant"])
        XCTAssertEqual(router.selectedTab, .garden)
    }

    func testRejectedScanReviewDoesNotMutateGardenOrRouteAway() {
        let draft = ScannedPlantReviewDraft(
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "plant-id-rejected",
                commonName: "Rejected candidate"
            ),
            careProfile: PlantCareProfile(source: .plantID),
            confidence: 80,
            provider: .cloud
        )
        let store = GardenStore(plants: [])
        store.cloudChangeHandler = { _ in false }
        let router = AppRouter()
        router.selectedTab = .scanner
        let coordinator = ScannerAnalysisCoordinator()
        var presentation = ScannerPresentationState(
            selectedImage: image(width: 120, height: 120, color: .systemGreen),
            reviewDraft: draft
        )

        let added = presentation.completeReview(
            draft: draft,
            nickname: "Must not save",
            wateringSelection: .medium,
            gardenStore: store,
            router: router,
            analysisCoordinator: coordinator
        )

        XCTAssertNil(added)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(router.selectedTab, .scanner)
        XCTAssertNotNil(store.mutationErrorMessage)
        XCTAssertEqual(presentation.reviewDraft, draft)
        XCTAssertNotNil(presentation.selectedImage)
    }

    func testSuccessfulReviewAddsOnceRoutesToGardenAndClearsScanPresentation() async throws {
        let identification = result(flowerID: "tulipan")
        let analysisCompleted = expectation(description: "Analysis result published")
        let coordinator = ScannerAnalysisCoordinator()
        coordinator.start {
            analysisCompleted.fulfill()
            return identification
        }
        await fulfillment(of: [analysisCompleted], timeout: 1)
        for _ in 0..<10 where coordinator.result == nil {
            await Task.yield()
        }
        XCTAssertEqual(coordinator.result, identification)

        var presentation = ScannerPresentationState()
        presentation.acceptPreparedImage(
            image(width: 120, height: 120, color: .systemOrange)
        )
        XCTAssertTrue(presentation.beginReview(
            result: identification,
            identity: identification.identity,
            careProfile: identification.careProfile,
            confidence: identification.confidence
        ))
        let draft = try XCTUnwrap(presentation.reviewDraft)
        let store = GardenStore(plants: [])
        let router = AppRouter()
        router.selectedTab = .scanner
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let added = presentation.completeReview(
            draft: draft,
            nickname: "Window tulip",
            wateringSelection: .notSet,
            gardenStore: store,
            router: router,
            analysisCoordinator: coordinator,
            at: savedAt
        )

        XCTAssertEqual(added?.nickname, "Window tulip")
        XCTAssertEqual(store.plants.count, 1)
        XCTAssertEqual(router.selectedTab, .garden)
        XCTAssertNil(presentation.selectedImage)
        XCTAssertNil(presentation.reviewDraft)
        XCTAssertNil(coordinator.result)
        XCTAssertFalse(coordinator.isProcessing)

        XCTAssertNil(presentation.completeReview(
            draft: draft,
            nickname: "Duplicate submission",
            wateringSelection: .wet,
            gardenStore: store,
            router: router,
            analysisCoordinator: coordinator,
            at: savedAt
        ))
        XCTAssertEqual(store.plants.count, 1)
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
        var presentation = ScannerPresentationState()
        presentation.acceptPreparedImage(
            image(width: 120, height: 120, color: .systemGray)
        )
        XCTAssertFalse(presentation.beginReview(
            result: result,
            identity: result.identity,
            careProfile: result.careProfile,
            confidence: result.confidence
        ))
        XCTAssertNil(presentation.reviewDraft)
        XCTAssertNotNil(presentation.selectedImage)
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
