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

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { currentMode in
                        Text(currentMode.rawValue).tag(currentMode)
                    }
                }
                .pickerStyle(.segmented)

                Section("Identifiants") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)

                    SecureField("Mot de passe", text: $password)
                }

                if mode == .register {
                    Section("Club") {
                        TextField("Nom du club", text: $clubName)
                    }
                }

                Section {
                    Button {
                        Task {
                            if mode == .login {
                                await authStore.login(email: email, password: password)
                            } else {
                                await authStore.register(email: email, password: password, clubName: clubName)
                            }
                        }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                        } else {
                            Text(mode == .login ? "Se connecter" : "Créer le compte")
                        }
                    }
                    .disabled(!canSubmit)
                }

                if let errorMessage = authStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("izifoot")
        }
    }

    private var canSubmit: Bool {
        if mode == .register {
            return !email.isEmpty && !password.isEmpty && !clubName.isEmpty && !authStore.isLoading
        }
        return !email.isEmpty && !password.isEmpty && !authStore.isLoading
    }
}
