import PhotosUI
import SwiftUI
import UIKit

struct ScannerView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var result: IdentificationResult?
    @State private var selectedFlower: Flower?
    @State private var isShowingCamera = false
    @State private var isProcessing = false
    @State private var cameraUnavailableMessage: String?

    private let identifier = FlowerIdentifier()
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

                    Text(L10n.text("scanner.disclaimer", fallback: "Rocio's on-device identification is experimental. It uses color and simple visual traits; always verify the care guide before acting."))
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
                    analyze(image)
                }
            }
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
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
        analyze(image)
    }

    private func analyze(_ image: UIImage) {
        isProcessing = true
        defer { isProcessing = false }
        result = identifier.identify(image: image)
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
                FlowerImage(flower: result.flower, size: 64)
                VStack(alignment: .leading) {
                    Text(result.flower.name)
                        .font(.title3.bold())
                    Text(result.flower.scientific)
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
                    Text(L10n.format("scanner.match", fallback: "%d%% on-device match", Int(result.confidence.rounded())))
                    Spacer()
                    Text(result.confidenceBand.reviewSafeCopy)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                onSelectFlower(result.flower)
            } label: {
                Label(
                    L10n.format("scanner.view.guide", fallback: "View %@ care guide", result.flower.name),
                    systemImage: "doc.text"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

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
