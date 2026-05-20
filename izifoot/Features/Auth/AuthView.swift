import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(colorScheme == .dark ? 0.52 : 1)
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image("LogoHeader")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 210)

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
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.06),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: colorScheme == .dark ? .clear : Color.black.opacity(0.08),
                    radius: 18,
                    y: 6
                )
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.11, blue: 0.16),
                Color(red: 0.03, green: 0.05, blue: 0.09),
            ]
        }

        return [
            Color(red: 0.96, green: 0.98, blue: 1.0),
            Color(red: 0.92, green: 0.95, blue: 1.0),
        ]
    }
}
