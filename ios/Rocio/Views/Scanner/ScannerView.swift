import PhotosUI
import SwiftUI
import UIKit

struct ScannerView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("rocio.cloud.photoConsent") private var hasCloudPhotoConsent = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var result: IdentificationResult?
    @State private var selectedFlower: Flower?
    @State private var isShowingCamera = false
    @State private var isProcessing = false
    @State private var cameraUnavailableMessage: String?
    @State private var pendingConsentImage: UIImage?
    @State private var isShowingPhotoConsent = false

    private let identifier = HybridFlowerIdentifier()
    private var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScannerPromiseCard()

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(maxHeight: 320)
                    } else {
                        scannerPlaceholder
                    }

                    HStack {
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
                        .buttonStyle(.borderedProminent)

                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label(L10n.text("scanner.choose", fallback: "Choose photo"), systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let cameraUnavailableMessage {
                        Text(cameraUnavailableMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isProcessing {
                        ProgressView(L10n.text("scanner.processing", fallback: "Checking colors and candidates"))
                    }

                    if let result {
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
            .navigationTitle(L10n.text("scanner.title", fallback: "Scanner"))
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    selectedImage = image
                    requestAnalysis(image)
                }
            }
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
            }
            .alert(L10n.text("scanner.consent.title", fallback: "Use cloud identification?"), isPresented: $isShowingPhotoConsent) {
                Button(L10n.text("scanner.consent.continue", fallback: "Send this photo")) {
                    hasCloudPhotoConsent = true
                    if let image = pendingConsentImage { Task { await analyze(image) } }
                    pendingConsentImage = nil
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {
                    pendingConsentImage = nil
                }
            } message: {
                Text(L10n.text("scanner.consent.copy", fallback: "Rocio will send a compressed copy of this flower photo to Plant.id through Rocio Cloud. The photo is used for identification and is not stored by Rocio."))
            }
            .onChange(of: selectedItem) { _, item in
                Task { await load(item) }
            }
        }
    }

    private var scannerPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.macro")
                .font(.system(size: 52))
                .foregroundStyle(Color.rocioLeaf)
            Text(L10n.text("scanner.placeholder.title", fallback: "Frame an open flower"))
                .font(.title3.bold())
            Text(L10n.text("scanner.placeholder.copy", fallback: "Use natural light and a clean background to improve the on-device match."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.rocioLeafSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        selectedImage = image
        requestAnalysis(image)
    }

    private func requestAnalysis(_ image: UIImage) {
        guard hasCloudPhotoConsent else {
            pendingConsentImage = image
            isShowingPhotoConsent = true
            return
        }
        Task { await analyze(image) }
    }

    @MainActor
    private func analyze(_ image: UIImage) async {
        isProcessing = true
        defer { isProcessing = false }
        result = await identifier.identify(image: image, sessionStore: sessionStore)
    }
}

private struct ScannerPromiseCard: View {
    private var sampleFlower: Flower? {
        FlowerCatalog.flower(id: "girasol")
    }

    var body: some View {
        RocioCard {
            HStack(spacing: 14) {
                if let sampleFlower {
                    FlowerImage(flower: sampleFlower, size: 76)
                } else {
                    Image(systemName: "camera.macro")
                        .font(.title)
                        .foregroundStyle(Color.rocioLeafDeep)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("scanner.promise.title", fallback: "An honest scanner"))
                        .font(.headline)
                    Text(L10n.text("scanner.promise.copy", fallback: "Rocio compares visible traits and shows candidates. It does not promise a perfect diagnosis."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
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
                        .foregroundStyle(result.confidenceBand == .experimental ? .orange : Color.rocioLeafDeep)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: min(100, max(0, result.confidence)), total: 100)
                    .tint(result.confidenceBand == .experimental ? .orange : Color.rocioLeafDeep)
                HStack {
                    Text(L10n.format("scanner.match", fallback: "%d%% visual match", Int(result.confidence.rounded())))
                    Spacer()
                    Text(result.confidenceBand.reviewSafeCopy)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Label(result.provider.label, systemImage: result.provider == .cloud ? "sparkles" : "iphone")
                Spacer()
                if let remaining = result.remainingCloudScans {
                    Text(L10n.format("scanner.remaining", fallback: "%d cloud scans left", remaining))
                }
            }
            .font(.caption)
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
