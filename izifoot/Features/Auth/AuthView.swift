import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.98, blue: 1.0),
                        Color(red: 0.92, green: 0.95, blue: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image("LogoHeader")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 210)

                        Text("Connectez-vous avec izifoot.fr")
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("L’app ouvre la page web sécurisée, récupère un code temporaire, puis termine la connexion localement.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        Button {
                            Task {
                                await authStore.signInWithWeb()
                            }
                        } label: {
                            if authStore.isAuthenticating {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Connexion en cours…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Se connecter")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(authStore.isAuthenticating)

                        Text("La création de compte et l’authentification passent par le site web izifoot pour garantir le même parcours que sur le web.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let errorMessage = authStore.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(20)
            }
            .navigationTitle("izifoot")
        }
    }
}
