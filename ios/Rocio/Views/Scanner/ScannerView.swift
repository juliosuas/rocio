import PhotosUI
import SwiftUI
import UIKit

struct ScannerView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    // Tab switches must not cancel an in-flight scan; this object owns it until replacement or completion.
    @StateObject private var analysisCoordinator = ScannerAnalysisCoordinator()
    @State private var pickerSelection = ScannerPhotoPickerSelectionState<PhotosPickerItem>()
    @State private var selectedImage: UIImage?
    @State private var selectedFlower: Flower?
    @State private var isShowingCamera = false
    @State private var cameraUnavailableMessage: String?
    @State private var photoConsent = ScannerPhotoConsentState()
    @State private var imageLoadTask: Task<Void, Never>?
    @State private var imagePreparationGeneration = ScannerImagePreparationGeneration()
    @State private var savedIdentities: Set<PlantIdentity> = []

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

                    if let selectedImage {
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
                            savedIdentities: savedIdentities,
                            canSave: gardenStore.canAcceptLocalChanges,
                            onSave: save,
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
                    selectedImage = nil
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
        selectedImage = image
        requestAnalysis(image)
    }

    private func beginImagePreparation() -> UInt {
        let generation = imagePreparationGeneration.begin()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        analysisCoordinator.cancel()
        photoConsent.discard()
        savedIdentities.removeAll()
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

    private func save(identity: PlantIdentity, careProfile: PlantCareProfile) {
        guard !savedIdentities.contains(identity) else { return }
        guard gardenStore.add(
            identity: identity,
            careProfile: careProfile,
            nickname: identity.commonName
        ) != nil else { return }
        savedIdentities.insert(identity)
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
    let savedIdentities: Set<PlantIdentity>
    let canSave: Bool
    let onSave: (PlantIdentity, PlantCareProfile) -> Void
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
                    onSave(result.identity, result.careProfile)
                } label: {
                    Label(
                        savedIdentities.contains(result.identity)
                            ? L10n.text("scanner.saved", fallback: "Saved to My Garden")
                            : L10n.format(
                                "scanner.save",
                                fallback: "Add %@ to My Garden",
                                result.displayName
                            ),
                        systemImage: savedIdentities.contains(result.identity)
                            ? "checkmark.circle.fill"
                            : "plus.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RocioPrimaryButtonStyle())
                .disabled(!canSave || savedIdentities.contains(result.identity))
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
                                onSave(
                                    candidate.identity,
                                    PlantCareProfile(source: .plantID, fetchedAt: Date())
                                )
                            } label: {
                                Image(
                                    systemName: savedIdentities.contains(candidate.identity)
                                        ? "checkmark.circle.fill"
                                        : "plus.circle"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                !canSave ||
                                    result.isPlant == false ||
                                    savedIdentities.contains(candidate.identity)
                            )
                            .accessibilityLabel(
                                savedIdentities.contains(candidate.identity)
                                    ? L10n.format(
                                        "scanner.candidate.saved",
                                        fallback: "%@ saved",
                                        candidate.name
                                    )
                                    : L10n.format(
                                        "scanner.candidate.add",
                                        fallback: "Add %@ to My Garden",
                                        candidate.name
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
