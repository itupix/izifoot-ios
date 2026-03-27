import SwiftUI

struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login = "Connexion"
        case register = "Inscription"
        var id: String { rawValue }
    }

    @EnvironmentObject private var authStore: AuthStore

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var clubName = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case clubName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { currentMode in
                            Text(currentMode.rawValue).tag(currentMode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Identifiants")
                            .font(.headline)

                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onSubmit {
                                focusedField = .password
                            }

                        SecureField("Mot de passe", text: $password)
                            .submitLabel(mode == .register ? .next : .go)
                            .focused($focusedField, equals: .password)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onSubmit {
                                if mode == .register {
                                    focusedField = .clubName
                                } else {
                                    submit()
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if mode == .register {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Club")
                                .font(.headline)

                            TextField("Nom du club", text: $clubName)
                                .submitLabel(.go)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .focused($focusedField, equals: .clubName)
                                .onSubmit {
                                    submit()
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        if authStore.isAuthenticating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(mode == .login ? "Se connecter" : "Créer le compte")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)

                    if let errorMessage = authStore.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("izifoot")
        }
    }

    private var canSubmit: Bool {
        if mode == .register {
            return !email.isEmpty && !password.isEmpty && !clubName.isEmpty && !authStore.isAuthenticating
        }
        return !email.isEmpty && !password.isEmpty && !authStore.isAuthenticating
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        let clubName = clubName.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            if mode == .login {
                await authStore.login(email: email, password: password)
            } else {
                await authStore.register(email: email, password: password, clubName: clubName)
            }
        }
    }
}
