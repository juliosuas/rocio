import PhotosUI
import SwiftUI
import UIKit

struct ScannerView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("rocio.cloud.photoConsent") private var hasCloudPhotoConsent = false
    // Tab switches must not cancel an in-flight scan; this object owns it until replacement or completion.
    @StateObject private var analysisCoordinator = ScannerAnalysisCoordinator()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedFlower: Flower?
    @State private var isShowingCamera = false
    @State private var cameraUnavailableMessage: String?
    @State private var pendingConsentImage: UIImage?
    @State private var isShowingPhotoConsent = false
    @State private var imageLoadTask: Task<Void, Never>?
    @State private var imageLoadGeneration: UInt = 0

    private let identifier = HybridFlowerIdentifier()
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

                        PhotosPicker(selection: $selectedItem, matching: .images) {
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
                        ProgressView(L10n.text("scanner.processing", fallback: "Checking colors and candidates"))
                    }

                    if let result = analysisCoordinator.result {
                        ScannerResultCard(result: result) { flower in
                            selectedFlower = flower
                        }
                    }

                    Text(L10n.text("scanner.disclaimer", fallback: "Flower identification is experimental. Cloud results use Plant.id when available; Rocio falls back to a simple on-device visual match. Always verify before acting."))
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
                    accept(image)
                }
            }
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
            }
            .alert(L10n.text("scanner.consent.title", fallback: "Use cloud identification?"), isPresented: $isShowingPhotoConsent) {
                Button(L10n.text("scanner.consent.continue", fallback: "Send this photo")) {
                    hasCloudPhotoConsent = true
                    if let image = pendingConsentImage { startAnalysis(image) }
                    pendingConsentImage = nil
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {
                    pendingConsentImage = nil
                }
            } message: {
                Text(L10n.text("scanner.consent.copy", fallback: "Rocio will send a compressed copy of this flower photo to Plant.id through Rocio Cloud. The photo is used for identification and is not stored by Rocio."))
            }
            .onChange(of: selectedItem) { _, item in
                load(item)
            }
        }
    }

    private var scannerPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.rocioRose)
            Text(L10n.text("scanner.placeholder.title", fallback: "Frame an open flower"))
                .font(.rocioTitle)
            Text(L10n.text("scanner.placeholder.copy", fallback: "Use natural light and a clean background to improve the on-device match."))
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
        imageLoadTask?.cancel()
        imageLoadGeneration &+= 1
        let generation = imageLoadGeneration
        analysisCoordinator.cancel()
        pendingConsentImage = nil

        imageLoadTask = Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  !Task.isCancelled,
                  generation == imageLoadGeneration else { return }
            imageLoadTask = nil
            accept(image, cancellingImageLoad: false)
        }
    }

    private func accept(_ image: UIImage, cancellingImageLoad: Bool = true) {
        if cancellingImageLoad {
            cancelImageLoad()
        }
        analysisCoordinator.cancel()
        pendingConsentImage = nil
        selectedImage = image
        requestAnalysis(image)
    }

    private func cancelImageLoad() {
        imageLoadGeneration &+= 1
        imageLoadTask?.cancel()
        imageLoadTask = nil
    }

    private func requestAnalysis(_ image: UIImage) {
#if DEBUG
        if sessionStore.isDemoMode {
            startAnalysis(image)
            return
        }
#endif
        guard hasCloudPhotoConsent else {
            pendingConsentImage = image
            isShowingPhotoConsent = true
            return
        }
        startAnalysis(image)
    }

    private func startAnalysis(_ image: UIImage) {
        let identifier = identifier
        let sessionStore = sessionStore
        analysisCoordinator.start {
            await identifier.identify(image: image, sessionStore: sessionStore)
        }
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

            if !result.externalCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("scanner.ai.candidates", fallback: "AI candidates"))
                        .font(.headline)
                    ForEach(result.externalCandidates) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.name)
                                Text(candidate.scientificName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(candidate.confidence.rounded()))%")
                                .foregroundStyle(.secondary)
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
