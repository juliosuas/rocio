import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false
    @State private var showingPasswordReset = false

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

                        if !isCreatingAccount {
                            Button(L10n.text("auth.forgot_password", fallback: "Forgot your password?")) {
                                showingPasswordReset = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
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

#if DEBUG
                        Button {
                            sessionStore.enterDemo(gardenStore: gardenStore)
                        } label: {
                            Label(L10n.text("demo.enter", fallback: "Explore local demo"), systemImage: "ladybug")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RocioSecondaryButtonStyle())
#endif

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
        .sheet(isPresented: $showingPasswordReset) {
            PasswordResetRequestView(initialEmail: email)
                .environmentObject(sessionStore)
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

private struct PasswordResetRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var email: String

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label {
                        Text(L10n.text("auth.recovery.title", fallback: "Reset your password"))
                            .font(.title2.bold())
                    } icon: {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Color.rocioLeafDeep)
                    }

                    switch sessionStore.passwordResetRequestState {
                    case .sent:
                        Label {
                            Text(L10n.text(
                                "auth.recovery.sent",
                                fallback: "If an account exists for that email, a password reset link is on its way."
                            ))
                        } icon: {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(Color.rocioTeal)
                        }
                        .font(.body)

                        Button(L10n.text("action.close", fallback: "Close")) {
                            dismiss()
                        }
                        .buttonStyle(RocioPrimaryButtonStyle())
                    case .idle, .sending, .failed:
                        Text(L10n.text(
                            "auth.recovery.copy",
                            fallback: "Enter your email and Rocio will send a secure link to choose a new password."
                        ))
                        .foregroundStyle(.secondary)

                        AuthField(systemImage: "envelope") {
                            TextField(L10n.text("auth.email", fallback: "Email"), text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        if case let .failed(message) = sessionStore.passwordResetRequestState {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await sessionStore.requestPasswordReset(email: email) }
                        } label: {
                            HStack {
                                if sessionStore.passwordResetRequestState == .sending {
                                    ProgressView().tint(.white)
                                }
                                Text(L10n.text("auth.recovery.send", fallback: "Send reset link"))
                                Spacer()
                                Image(systemName: "paperplane.fill")
                            }
                        }
                        .buttonStyle(RocioPrimaryButtonStyle())
                        .disabled(
                            !AuthInputValidator.isValidEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
                                || sessionStore.passwordResetRequestState == .sending
                        )
                    }
                }
                .padding(20)
            }
            .background(Color.rocioCanvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("action.close", fallback: "Close")) { dismiss() }
                }
            }
            .onAppear { sessionStore.preparePasswordResetRequest() }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PasswordRecoveryView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isPasswordUpdated {
                        successContent
                    } else {
                        updateContent
                    }
                }
                .padding(20)
            }
            .background(Color.rocioCanvas.ignoresSafeArea())
            .toolbar {
                if case .recoveringPassword = sessionStore.state {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text("action.cancel", fallback: "Cancel")) {
                            Task { await sessionStore.cancelPasswordRecovery(gardenStore: gardenStore) }
                        }
                        .disabled(isWorking)
                    }
                }
            }
        }
    }

    private var updateContent: some View {
        Group {
            Label {
                Text(L10n.text("auth.recovery.choose", fallback: "Choose a new password"))
                    .font(.title2.bold())
            } icon: {
                Image(systemName: "lock.rotation")
                    .foregroundStyle(Color.rocioLeafDeep)
            }

            if let email = recoveryEmail {
                Text(email)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(L10n.text(
                "auth.recovery.requirements",
                fallback: "Use at least eight characters and avoid reusing an old password."
            ))
            .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                AuthField(systemImage: "lock") {
                    SecureField(L10n.text("auth.recovery.new_password", fallback: "New password"), text: $password)
                        .textContentType(.newPassword)
                }
                AuthField(systemImage: "lock.shield") {
                    SecureField(L10n.text("auth.recovery.confirm_password", fallback: "Confirm password"), text: $confirmation)
                        .textContentType(.newPassword)
                }
            }

            if !confirmation.isEmpty, password != confirmation {
                Label(
                    L10n.text("error.auth.password_mismatch", fallback: "The passwords do not match."),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.red)
            }

            if let error = sessionStore.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await updatePassword() }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text(L10n.text("auth.recovery.update", fallback: "Update password"))
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                }
            }
            .buttonStyle(RocioPrimaryButtonStyle())
            .disabled(!AuthInputValidator.isValidNewPassword(password, confirmation: confirmation) || isWorking)
        }
    }

    private var successContent: some View {
        Group {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.rocioTeal)

            Text(L10n.text("auth.recovery.success", fallback: "Your password is updated"))
                .font(.title2.bold())

            Text(L10n.text(
                requiresSignIn ? "auth.recovery.success_sign_in_copy" : "auth.recovery.success_copy",
                fallback: requiresSignIn
                    ? "Your password changed, but Rocio could not save the session securely. Sign in again to continue."
                    : "You can continue to your garden with this account."
            ))
            .foregroundStyle(.secondary)

            Button {
                Task { await sessionStore.completePasswordRecovery(gardenStore: gardenStore) }
            } label: {
                HStack {
                    Text(L10n.text(
                        requiresSignIn ? "auth.recovery.back_to_sign_in" : "auth.recovery.continue",
                        fallback: requiresSignIn ? "Back to sign in" : "Continue to Rocio"
                    ))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(RocioPrimaryButtonStyle())
        }
    }

    private var recoveryEmail: String? {
        guard case let .recoveringPassword(session) = sessionStore.state else { return nil }
        return session.user.email
    }

    private var isPasswordUpdated: Bool {
        switch sessionStore.state {
        case .passwordUpdated, .passwordUpdatedRequiresSignIn:
            true
        default:
            false
        }
    }

    private var requiresSignIn: Bool {
        sessionStore.state == .passwordUpdatedRequiresSignIn
    }

    @MainActor
    private func updatePassword() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await sessionStore.updateRecoveredPassword(password, gardenStore: gardenStore)
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
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore

    var body: some View {
#if DEBUG
        ContentUnavailableView {
            Label("Rocio Cloud", systemImage: "icloud.slash")
        } description: {
            Text(L10n.text("cloud.configuration.missing", fallback: "This build is missing its Supabase anonymous key."))
        } actions: {
            Button {
                sessionStore.enterDemo(gardenStore: gardenStore)
            } label: {
                Label(L10n.text("demo.enter", fallback: "Explore local demo"), systemImage: "ladybug")
            }
            .buttonStyle(.borderedProminent)
        }
#else
        ContentUnavailableView {
            Label("Rocio Cloud", systemImage: "icloud.slash")
        } description: {
            Text(L10n.text("cloud.configuration.missing", fallback: "This build is missing its Supabase anonymous key."))
        }
#endif
    }
}
