import AuthenticationServices
import CryptoKit
import SwiftUI

struct LoginView: View {
    private enum Field {
        case username, password
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var username = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showPasswordReset = false
    /// Одноразовое случайное значение входа через Apple: в запрос уходит его SHA-256, на сервер — оно само.
    /// Так перехваченный identityToken нельзя подсунуть серверу повторно.
    @State private var appleNonce = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    form
                    footer
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(AuroraBackground().ignoresSafeArea())
            .tint(.brand)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showPasswordReset) {
                PasswordResetView()
            }
            .sheet(item: $authViewModel.pendingGoogleRegistration) { registration in
                GoogleRegistrationView(registration: registration)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(.brandFill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.brand.opacity(0.4), radius: 24, y: 12)
                .accessibilityHidden(true)
            Text("Бо Хам")
                .font(.display(size: 34, weight: .bold))
                .padding(.top, 8)
            Text("Знакомства для серьёзных отношений, переписка и звонки — в одном месте")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
    }

    private var form: some View {
        GlassGroup(spacing: 12) {
            VStack(spacing: 12) {
                AppField(systemImage: "person") {
                    TextField("Username или почта", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                }

                AppField(systemImage: "lock") {
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(login)
                }

                if let errorMessage = authViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.app(.footnote))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Button(action: login) {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Войти")
                        }
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(!canLogin)
                .padding(.top, 4)

                SignInWithAppleButton(.signIn) { request in
                    appleNonce = Self.makeNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(appleNonce)
                } onCompletion: { result in
                    let nonce = appleNonce
                    Task { await authViewModel.signInWithApple(result, nonce: nonce) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: AppMetrics.buttonHeight)
                .clipShape(Capsule())
                .disabled(authViewModel.isLoading)

                if GoogleAuth.isEnabled {
                    Button {
                        Task { await authViewModel.signInWithGoogle() }
                    } label: {
                        Label("Войти через Google", systemImage: "g.circle.fill")
                    }
                    .buttonStyle(.appSecondary)
                    .disabled(authViewModel.isLoading)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button("Создать аккаунт") { showRegister = true }
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(Color.brand)
            Button("Забыли пароль?") { showPasswordReset = true }
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
        }
    }

    private static func makeNonce() -> String {
        // UInt8.random берёт байты из SystemRandomNumberGenerator — криптостойкого генератора системы.
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var canLogin: Bool {
        !username.isEmpty && !password.isEmpty && !authViewModel.isLoading
    }

    private func login() {
        guard canLogin else { return }
        Task { await authViewModel.login(username: username, password: password) }
    }
}
