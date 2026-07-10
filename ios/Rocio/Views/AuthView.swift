import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false

    private var heroFlower: Flower? { FlowerCatalog.flower(id: "rosa") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        if let heroFlower {
                            FlowerArtwork(flower: heroFlower, height: 250)
                        } else {
                            Color.rocioLeafAction.frame(height: 250)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Label("Rocio", systemImage: "camera.macro")
                                .font(.rocioDisplay)
                            Text(L10n.text("auth.subtitle", fallback: "Your flower garden, synced and ready wherever you grow."))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.48))
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Picker(L10n.text("auth.signin", fallback: "Sign in"), selection: $isCreatingAccount) {
                            Text(L10n.text("auth.signin", fallback: "Sign in")).tag(false)
                            Text(L10n.text("auth.create", fallback: "Create account")).tag(true)
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 12) {
                            AuthField(systemImage: "envelope") {
                                TextField(L10n.text("auth.email", fallback: "Email"), text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            AuthField(systemImage: "lock") {
                                SecureField(L10n.text("auth.password", fallback: "Password"), text: $password)
                                    .textContentType(isCreatingAccount ? .newPassword : .password)
                            }
                        }

                        if let error = sessionStore.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isWorking { ProgressView().tint(.white) }
                                Text(isCreatingAccount
                                     ? L10n.text("auth.create", fallback: "Create account")
                                     : L10n.text("auth.signin", fallback: "Sign in"))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(RocioPrimaryButtonStyle())
                        .disabled(!isValid || isWorking)

                        Label {
                            Text(L10n.text("auth.privacy", fallback: "An account is required to sync your garden and enforce fair AI scan limits. Rocio does not sell your data or use advertising trackers."))
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(Color.rocioTeal)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            }
            .background(Color.rocioCanvas.ignoresSafeArea())
        }
    }

    private var isValid: Bool {
        email.contains("@") && password.count >= 8
    }

    @MainActor
    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        if isCreatingAccount {
            await sessionStore.signUp(email: email, password: password, gardenStore: gardenStore)
        } else {
            await sessionStore.signIn(email: email, password: password, gardenStore: gardenStore)
        }
    }
}

private struct AuthField<Content: View>: View {
    let systemImage: String
    let content: () -> Content

    init(systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.rocioLeafDeep)
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }
}
struct CloudConfigurationRequiredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Rocio Cloud", systemImage: "cloud.slash")
        } description: {
            Text("This development build is missing its Supabase anonymous key.")
        }
    }
}
