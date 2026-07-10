import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "camera.macro")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.rocioLeafDeep)
                        Text("Rocio")
                            .font(.largeTitle.bold())
                        Text(L10n.text("auth.subtitle", fallback: "Your flower garden, synced and ready wherever you grow."))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 14) {
                        TextField(L10n.text("auth.email", fallback: "Email"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField(L10n.text("auth.password", fallback: "Password"), text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                    }
                    .textFieldStyle(.roundedBorder)

                    if let error = sessionStore.errorMessage {
                        Text(error)
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
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RocioPrimaryButtonStyle())
                    .disabled(!isValid || isWorking)

                    Button(isCreatingAccount
                           ? L10n.text("auth.existing", fallback: "Already have an account? Sign in")
                           : L10n.text("auth.new", fallback: "New to Rocio? Create an account")) {
                        isCreatingAccount.toggle()
                    }
                    .frame(maxWidth: .infinity)

                    Text(L10n.text("auth.privacy", fallback: "An account is required to sync your garden and enforce fair AI scan limits. Rocio does not sell your data or use advertising trackers."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
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
struct CloudConfigurationRequiredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Rocio Cloud", systemImage: "cloud.slash")
        } description: {
            Text("This development build is missing its Supabase anonymous key.")
        }
    }
}
