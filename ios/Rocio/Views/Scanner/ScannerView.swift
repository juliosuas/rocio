import PhotosUI
import SwiftUI
import UIKit

struct ScannerView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    // Tab switches must not cancel an in-flight scan; this object owns it until replacement or completion.
    @StateObject private var analysisCoordinator = ScannerAnalysisCoordinator()
    @State private var pickerSelection = ScannerPhotoPickerSelectionState<PhotosPickerItem>()
    @State private var presentationState = ScannerPresentationState()
    @State private var selectedFlower: Flower?
    @State private var isShowingCamera = false
    @State private var cameraUnavailableMessage: String?
    @State private var photoConsent = ScannerPhotoConsentState()
    @State private var imageLoadTask: Task<Void, Never>?
    @State private var imagePreparationGeneration = ScannerImagePreparationGeneration()

    private let identifier = HybridFlowerIdentifier()
    private let imageProcessor = ScannerImageProcessor()
    private var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScannerPromiseCard()

#if DEBUG
                    if sessionStore.isDemoMode {
                        Label(L10n.text("demo.scanner.notice", fallback: "Demo uses on-device matching. No photo leaves this iPhone."), systemImage: "iphone.gen3")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.rocioLeafDeep)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.rocioLeafSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
#endif

                    if let selectedImage = presentationState.selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        scannerPlaceholder
                    }

                    HStack(spacing: 10) {
                        Button {
                            guard canUseCamera else {
                                cameraUnavailableMessage = L10n.text("scanner.camera.unavailable", fallback: "The camera is unavailable on this device. You can choose a photo instead.")
                                return
                            }
                            cameraUnavailableMessage = nil
                            isShowingCamera = true
                        } label: {
                            Label(L10n.text("scanner.camera", fallback: "Take photo"), systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RocioPrimaryButtonStyle())

                        PhotosPicker(selection: $pickerSelection.item, matching: .images) {
                            Label(L10n.text("scanner.choose", fallback: "Choose photo"), systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RocioSecondaryButtonStyle())
                    }

                    if let cameraUnavailableMessage {
                        Text(cameraUnavailableMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if analysisCoordinator.isProcessing {
                        ProgressView(L10n.text("scanner.processing", fallback: "Checking plant candidates"))
                    }

                    if let result = analysisCoordinator.result {
                        ScannerResultCard(
                            result: result,
                            canSave: gardenStore.canAcceptLocalChanges,
                            onReview: { identity, careProfile, confidence in
                                presentationState.beginReview(
                                    result: result,
                                    identity: identity,
                                    careProfile: careProfile,
                                    confidence: confidence
                                )
                            },
                            onSelectFlower: { flower in
                                selectedFlower = flower
                            }
                        )
                    }

                    Text(L10n.text("scanner.disclaimer", fallback: "Plant identification is probabilistic. Cloud results use Plant.id when available; Rocio falls back to a simple on-device flower match. Always verify before acting."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color.rocioCanvas)
            .navigationTitle(L10n.text("scanner.title", fallback: "Scanner"))
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    prepareCapturedImage(image)
                }
            }
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
            }
            .sheet(item: $presentationState.reviewDraft) { draft in
                ScannedPlantReviewView(
                    draft: draft,
                    onCancel: {
                        presentationState.cancelReview()
                    },
                    onSave: { nickname, wateringSelection in
                        save(
                            draft: draft,
                            nickname: nickname,
                            wateringSelection: wateringSelection
                        )
                    }
                )
            }
            .alert(
                L10n.text("scanner.consent.title", fallback: "How should Rocio identify this photo?"),
                isPresented: Binding(
                    get: { photoConsent.isPresented },
                    set: { if !$0 { photoConsent.discard() } }
                )
            ) {
                Button(L10n.text("scanner.consent.continue", fallback: "Send this photo")) {
                    if let image = photoConsent.takeImage() {
                        startAnalysis(image, destination: .cloud)
                    }
                }
                Button(L10n.text("scanner.consent.on_device", fallback: "Analyze on this iPhone")) {
                    if let image = photoConsent.takeImage() {
                        startAnalysis(image, destination: .onDevice)
                    }
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {
                    photoConsent.discard()
                    presentationState.clearSelectedImage()
                    pickerSelection.item = nil
                }
            } message: {
                Text(L10n.text("scanner.consent.copy", fallback: "For this photo, choose Plant.id through Rocio Cloud or keep the analysis entirely on this iPhone. Rocio does not store the photo."))
            }
            .onChange(of: pickerSelection.item) { _, item in
                load(item)
            }
        }
    }

    private var scannerPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.rocioRose)
            Text(L10n.text("scanner.placeholder.title", fallback: "Frame the plant clearly"))
                .font(.rocioTitle)
            Text(L10n.text("scanner.placeholder.copy", fallback: "Include leaves, flowers, or fruit in natural light against a clean background."))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .padding(24)
        .background(Color.rocioLeafAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let generation = beginImagePreparation()
        let imageProcessor = imageProcessor

        imageLoadTask = Task {
            defer {
                if imagePreparationGeneration.isCurrent(generation) {
                    imageLoadTask = nil
                }
                // Clear both successful and failed loads so PhotosPicker can
                // deliver the same asset again. An older load may never clear
                // a newer selection.
                pickerSelection.clearAfterLoading(item)
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = await imageProcessor.prepare(data: data),
                  !Task.isCancelled,
                  imagePreparationGeneration.isCurrent(generation) else { return }
            acceptPreparedImage(image)
        }
    }

    private func prepareCapturedImage(_ image: UIImage) {
        let generation = beginImagePreparation()
        let imageProcessor = imageProcessor

        imageLoadTask = Task {
            guard let image = await imageProcessor.prepare(image: image),
                  !Task.isCancelled,
                  imagePreparationGeneration.isCurrent(generation) else { return }
            imageLoadTask = nil
            acceptPreparedImage(image)
        }
    }

    private func acceptPreparedImage(_ image: UIImage) {
        presentationState.acceptPreparedImage(image)
        requestAnalysis(image)
    }

    private func beginImagePreparation() -> UInt {
        let generation = imagePreparationGeneration.begin()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        analysisCoordinator.cancel()
        photoConsent.discard()
        presentationState.cancelReview()
        return generation
    }

    private func requestAnalysis(_ image: UIImage) {
#if DEBUG
        if sessionStore.isDemoMode {
            startAnalysis(image, destination: .onDevice)
            return
        }
#endif
        photoConsent.begin(image)
    }

    private func startAnalysis(
        _ image: UIImage,
        destination: ScannerAnalysisDestination
    ) {
        let identifier = identifier
        let sessionStore = sessionStore
        analysisCoordinator.start {
            await identifier.identify(
                image: image,
                destination: destination,
                sessionStore: sessionStore
            )
        }
    }

    private func save(
        draft: ScannedPlantReviewDraft,
        nickname: String,
        wateringSelection: PlantWateringSelection
    ) -> Bool {
        guard presentationState.completeReview(
            draft: draft,
            nickname: nickname,
            wateringSelection: wateringSelection,
            gardenStore: gardenStore,
            router: router,
            analysisCoordinator: analysisCoordinator
        ) != nil else { return false }

        clearCompletedScan()
        return true
    }

    private func clearCompletedScan() {
        _ = imagePreparationGeneration.begin()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        photoConsent.discard()
        pickerSelection.item = nil
        presentationState.clearScan()
        selectedFlower = nil
        cameraUnavailableMessage = nil
    }
}

struct ScannerPhotoPickerSelectionState<Item: Equatable> {
    var item: Item?

    @discardableResult
    mutating func clearAfterLoading(_ loadedItem: Item) -> Bool {
        guard item == loadedItem else { return false }
        item = nil
        return true
    }
}

struct ScannerPhotoConsentState {
    private(set) var pendingImage: UIImage?

    var isPresented: Bool { pendingImage != nil }

    mutating func begin(_ image: UIImage) {
        pendingImage = image
    }

    mutating func takeImage() -> UIImage? {
        defer { pendingImage = nil }
        return pendingImage
    }

    mutating func discard() {
        pendingImage = nil
    }
}

struct ScannerImagePreparationGeneration {
    private(set) var current: UInt = 0

    mutating func begin() -> UInt {
        current &+= 1
        return current
    }

    func isCurrent(_ generation: UInt) -> Bool {
        generation == current
    }
}

@MainActor
final class ScannerAnalysisCoordinator: ObservableObject {
    @Published private(set) var result: IdentificationResult?
    @Published private(set) var isProcessing = false

    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    deinit {
        task?.cancel()
    }

    func start(operation: @escaping @MainActor () async -> IdentificationResult?) {
        generation &+= 1
        let requestGeneration = generation
        task?.cancel()
        result = nil
        isProcessing = true

        task = Task { [weak self] in
            let nextResult = await operation()
            guard let self,
                  !Task.isCancelled,
                  requestGeneration == self.generation else { return }
            self.result = nextResult
            self.isProcessing = false
            self.task = nil
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        result = nil
        isProcessing = false
    }
}

struct ScannedPlantReviewDraft: Identifiable, Equatable {
    let id: UUID
    let identity: PlantIdentity
    let careProfile: PlantCareProfile
    let confidence: Double
    let provider: IdentificationProvider

    init(
        id: UUID = UUID(),
        identity: PlantIdentity,
        careProfile: PlantCareProfile,
        confidence: Double,
        provider: IdentificationProvider
    ) {
        self.id = id
        self.identity = identity
        self.careProfile = careProfile
        self.confidence = confidence
        self.provider = provider
    }

    var initialWateringSelection: PlantWateringSelection {
        PlantWateringSelection(preference: careProfile.wateringPreference)
    }

    func reviewedCareProfile(
        wateringSelection: PlantWateringSelection
    ) -> PlantCareProfile {
        var reviewed = careProfile
        reviewed.wateringPreference = wateringSelection.preference

        // A user-confirmed preference becomes the source of the reminder
        // cadence. Remove exact catalog values so they cannot silently win
        // over that choice or imply a precise amount for an arbitrary plant.
        if wateringSelection.preference != nil {
            reviewed.wateringIntervalDays = nil
            reviewed.waterAmountMl = nil
        }

        return reviewed.normalized
    }
}

@MainActor
struct ScannerPresentationState {
    var selectedImage: UIImage?
    var reviewDraft: ScannedPlantReviewDraft?

    mutating func acceptPreparedImage(_ image: UIImage) {
        selectedImage = image
    }

    @discardableResult
    mutating func beginReview(
        result: IdentificationResult,
        identity: PlantIdentity,
        careProfile: PlantCareProfile,
        confidence: Double
    ) -> Bool {
        guard result.canSaveToGarden else { return false }
        reviewDraft = ScannedPlantReviewDraft(
            identity: identity,
            careProfile: careProfile,
            confidence: confidence,
            provider: result.provider
        )
        return true
    }

    mutating func cancelReview() {
        reviewDraft = nil
    }

    mutating func clearSelectedImage() {
        selectedImage = nil
    }

    mutating func clearScan() {
        selectedImage = nil
        reviewDraft = nil
    }

    @discardableResult
    mutating func completeReview(
        draft: ScannedPlantReviewDraft,
        nickname: String,
        wateringSelection: PlantWateringSelection,
        gardenStore: GardenStore,
        router: AppRouter,
        analysisCoordinator: ScannerAnalysisCoordinator,
        at date: Date = Date()
    ) -> GardenPlant? {
        guard reviewDraft?.id == draft.id else { return nil }
        guard let plant = ScannerFirstCareFlow.addToGarden(
            draft: draft,
            nickname: nickname,
            wateringSelection: wateringSelection,
            gardenStore: gardenStore,
            router: router,
            at: date
        ) else { return nil }

        analysisCoordinator.cancel()
        clearScan()
        return plant
    }
}

@MainActor
enum ScannerFirstCareFlow {
    @discardableResult
    static func addToGarden(
        draft: ScannedPlantReviewDraft,
        nickname: String,
        wateringSelection: PlantWateringSelection,
        gardenStore: GardenStore,
        router: AppRouter,
        at date: Date = Date()
    ) -> GardenPlant? {
        guard let plant = gardenStore.add(
            identity: draft.identity,
            careProfile: draft.reviewedCareProfile(
                wateringSelection: wateringSelection
            ),
            nickname: nickname,
            at: date
        ) else { return nil }

        router.selectedTab = .garden
        return plant
    }
}

private struct ScannedPlantReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let draft: ScannedPlantReviewDraft
    let onCancel: () -> Void
    let onSave: (String, PlantWateringSelection) -> Bool

    @State private var nickname: String
    @State private var wateringSelection: PlantWateringSelection
    @State private var isSaving = false

    init(
        draft: ScannedPlantReviewDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, PlantWateringSelection) -> Bool
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _nickname = State(initialValue: draft.identity.commonName)
        _wateringSelection = State(initialValue: draft.initialWateringSelection)
    }

    private var normalizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(
                        L10n.text("scanner.review.match", fallback: "Suggested identity"),
                        value: draft.identity.commonName
                    )
                    if let scientificName = draft.identity.scientificName {
                        LabeledContent(
                            L10n.text("scanner.review.scientific", fallback: "Scientific name"),
                            value: scientificName
                        )
                    }
                    LabeledContent(
                        L10n.text("scanner.review.source", fallback: "Source"),
                        value: draft.provider.label
                    )
                    LabeledContent(
                        L10n.text("scanner.review.confidence", fallback: "Visual match"),
                        value: L10n.format(
                            "scanner.review.confidence.value",
                            fallback: "%d%%",
                            Int(draft.confidence.rounded())
                        )
                    )
                } header: {
                    Text(L10n.text("scanner.review.identity", fallback: "Identification"))
                } footer: {
                    Text(L10n.text(
                        "scanner.review.identity.help",
                        fallback: "Identification is a suggestion. Verify the plant before acting on care guidance."
                    ))
                }

                Section {
                    TextField(
                        L10n.text("scanner.review.nickname", fallback: "Specimen name"),
                        text: $nickname
                    )
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("scanner.review.nickname")
                } header: {
                    Text(L10n.text("scanner.review.specimen", fallback: "Your specimen"))
                } footer: {
                    Text(L10n.text(
                        "scanner.review.nickname.help",
                        fallback: "This name is only for your specimen. It does not change the provider identity."
                    ))
                }

                Section {
                    Picker(
                        L10n.text(
                            "garden.edit.watering.preference",
                            fallback: "Watering preference"
                        ),
                        selection: $wateringSelection
                    ) {
                        ForEach(PlantWateringSelection.allCases) { selection in
                            Text(selection.label).tag(selection)
                        }
                    }
                    .accessibilityIdentifier("scanner.review.watering")
                } header: {
                    Text(L10n.text("garden.manual.care", fallback: "Care (optional)"))
                } footer: {
                    Text(L10n.text(
                        "scanner.review.care.help",
                        fallback: "Choose only what you know. Not sure keeps the plant unscheduled unless a matching Rocio guide provides care."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.rocioCanvas)
            .navigationTitle(
                L10n.text("scanner.review.title", fallback: "Review plant")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("action.cancel", fallback: "Cancel")) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("scanner.review.save", fallback: "Save to Garden")) {
                        save()
                    }
                    .disabled(normalizedNickname.isEmpty || isSaving)
                    .accessibilityIdentifier("scanner.review.save")
                    .accessibilityLabel(
                        L10n.format(
                            "scanner.review.save.accessibility",
                            fallback: "Save %@ to My Garden",
                            normalizedNickname
                        )
                    )
                }
            }
        }
    }

    private func save() {
        guard !normalizedNickname.isEmpty, !isSaving else { return }
        isSaving = true
        guard onSave(normalizedNickname, wateringSelection) else {
            isSaving = false
            return
        }
        dismiss()
    }
}

private struct ScannerPromiseCard: View {
    private var sampleFlower: Flower? {
        FlowerCatalog.flower(id: "girasol")
    }

    var body: some View {
        HStack(spacing: 14) {
            if let sampleFlower {
                FlowerImage(flower: sampleFlower, size: 72)
            } else {
                Image(systemName: "camera.macro")
                    .font(.title)
                    .foregroundStyle(Color.rocioLeafDeep)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("scanner.promise.title", fallback: "An honest scanner"))
                    .font(.rocioTitle)
                Text(L10n.text("scanner.promise.copy", fallback: "Rocio compares visible traits and shows candidates. It does not promise a perfect diagnosis."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ScannerResultCard: View {
    let result: IdentificationResult
    let canSave: Bool
    let onReview: (PlantIdentity, PlantCareProfile, Double) -> Void
    let onSelectFlower: (Flower) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if result.usesExternalSuggestion {
                    Image(systemName: "camera.macro")
                        .font(.title)
                        .foregroundStyle(Color.rocioLeafDeep)
                        .frame(width: 64, height: 64)
                        .background(Color.rocioLeafSoft, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    FlowerImage(flower: result.flower, size: 64)
                }
                VStack(alignment: .leading) {
                    Text(result.displayName)
                        .font(.title3.bold())
                    Text(result.displayScientificName)
                        .foregroundStyle(.secondary)
                    Label(result.confidenceBand.label, systemImage: "waveform.path.ecg")
                        .font(.caption.bold())
                        .foregroundStyle(result.confidenceBand == .experimental ? Color.rocioAmber : Color.rocioLeafDeep)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: min(100, max(0, result.confidence)), total: 100)
                    .tint(result.confidenceBand == .experimental ? Color.rocioAmber : Color.rocioLeafDeep)
                HStack {
                    Text(L10n.format("scanner.match", fallback: "%d%% visual match", Int(result.confidence.rounded())))
                    Spacer()
                    Text(result.confidenceBand.reviewSafeCopy)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                RocioStatusBadge(
                    title: result.provider.label,
                    systemImage: result.provider == .cloud ? "sparkles" : "iphone",
                    tint: result.provider == .cloud ? .rocioRose : .rocioTeal
                )
                Spacer()
                if let remaining = result.remainingCloudScans {
                    Text(L10n.format("scanner.remaining", fallback: "%d cloud scans left", remaining))
                }
            }
            .foregroundStyle(.secondary)

            if result.isPlant == false {
                Label(
                    L10n.text(
                        "scanner.not_plant",
                        fallback: "Plant.id did not detect a plant in this photo. Try another photo before saving."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.rocioAmber)
            } else {
                Button {
                    onReview(result.identity, result.careProfile, result.confidence)
                } label: {
                    Label(
                        L10n.format(
                            "scanner.review.action",
                            fallback: "Review and add %@",
                            result.displayName
                        ),
                        systemImage: "checkmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RocioPrimaryButtonStyle())
                .disabled(!canSave)
                .accessibilityIdentifier("scanner.review.primary")
                .accessibilityHint(
                    L10n.text(
                        "scanner.review.action.hint",
                        fallback: "Review the specimen name and watering preference before saving."
                    )
                )
            }

            Button {
                onSelectFlower(result.flower)
            } label: {
                Label(
                    result.usesExternalSuggestion
                        ? L10n.format("scanner.view.closest.guide", fallback: "View closest Rocio guide: %@", result.flower.name)
                        : L10n.format("scanner.view.guide", fallback: "View %@ care guide", result.flower.name),
                    systemImage: "doc.text"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if !result.alternateExternalCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("scanner.ai.candidates", fallback: "AI candidates"))
                        .font(.headline)
                    ForEach(result.alternateExternalCandidates) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.name)
                                Text(candidate.scientificName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(candidate.confidence.rounded()))%")
                                .foregroundStyle(.secondary)
                            Button {
                                onReview(
                                    candidate.identity,
                                    PlantCareProfile(source: .plantID, fetchedAt: Date()),
                                    candidate.confidence
                                )
                            } label: {
                                HStack(spacing: 4) {
                                    Text(L10n.text(
                                        "scanner.candidate.review.action",
                                        fallback: "Review"
                                    ))
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave || result.isPlant == false)
                            .accessibilityLabel(
                                L10n.format(
                                    "scanner.candidate.review",
                                    fallback: "Review %@ before adding",
                                    candidate.name
                                )
                            )
                            .accessibilityHint(
                                L10n.text(
                                    "scanner.review.action.hint",
                                    fallback: "Review the specimen name and watering preference before saving."
                                )
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("scanner.candidates", fallback: "Candidates"))
                    .font(.headline)
                ForEach(result.candidates) { candidate in
                    Button {
                        onSelectFlower(candidate.flower)
                    } label: {
                        HStack {
                            Text(candidate.flower.name)
                            Spacer()
                            Text("\(Int(candidate.confidence.rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.rocioLine)
        )
    }
}
