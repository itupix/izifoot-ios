import SwiftUI

private enum AuthViewTheme {
    static let lightBackgroundTop = Color(red: 244 / 255, green: 246 / 255, blue: 248 / 255)
    static let lightBackgroundBottom = Color(red: 223 / 255, green: 230 / 255, blue: 239 / 255)
    static let lightGlow = Color(red: 15 / 255, green: 122 / 255, blue: 67 / 255).opacity(0.12)
    static let lightLogoGlow = Color.white.opacity(0.45)
    static let lightCard = Color.white.opacity(0.92)
    static let lightCardBorder = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.08)
    static let lightShadow = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.14)
    static let lightLogoShadow = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.12)
    static let lightText = Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255)
    static let lightMuted = Color(red: 95 / 255, green: 105 / 255, blue: 120 / 255)
    static let lightPrimaryTop = Color(red: 15 / 255, green: 122 / 255, blue: 67 / 255)
    static let lightPrimaryBottom = Color(red: 9 / 255, green: 90 / 255, blue: 49 / 255)
    static let lightPrimaryShadow = Color(red: 15 / 255, green: 122 / 255, blue: 67 / 255).opacity(0.28)

    static let darkBackgroundTop = Color(red: 9 / 255, green: 16 / 255, blue: 24 / 255)
    static let darkBackgroundBottom = Color(red: 19 / 255, green: 29 / 255, blue: 41 / 255)
    static let darkGlow = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.18)
    static let darkLogoGlow = Color.white.opacity(0.14)
    static let darkCard = Color(red: 15 / 255, green: 20 / 255, blue: 27 / 255).opacity(0.92)
    static let darkCardBorder = Color.white.opacity(0.09)
    static let darkShadow = Color.black.opacity(0.44)
    static let darkLogoShadow = Color.black.opacity(0.28)
    static let darkText = Color(red: 243 / 255, green: 245 / 255, blue: 247 / 255)
    static let darkMuted = Color(red: 168 / 255, green: 176 / 255, blue: 189 / 255)
    static let darkPrimaryTop = Color(red: 30 / 255, green: 168 / 255, blue: 93 / 255)
    static let darkPrimaryBottom = Color(red: 19 / 255, green: 114 / 255, blue: 68 / 255)
    static let darkPrimaryShadow = Color(red: 30 / 255, green: 168 / 255, blue: 93 / 255).opacity(0.24)
}

private struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [primaryTop, primaryBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: primaryShadow, radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }

    private var primaryTop: Color {
        colorScheme == .dark ? AuthViewTheme.darkPrimaryTop : AuthViewTheme.lightPrimaryTop
    }

    private var primaryBottom: Color {
        colorScheme == .dark ? AuthViewTheme.darkPrimaryBottom : AuthViewTheme.lightPrimaryBottom
    }

    private var primaryShadow: Color {
        colorScheme == .dark ? AuthViewTheme.darkPrimaryShadow : AuthViewTheme.lightPrimaryShadow
    }
}

struct AuthView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                VStack(spacing: 18) {
                    Spacer(minLength: 28)

                    Image("LogoHeader")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(maxWidth: 208, alignment: .leading)
                        .frame(maxWidth: 460, alignment: .leading)
                        .padding(.leading, 6)
                        .shadow(color: logoShadow, radius: 10, y: 8)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connexion")
                                .font(.system(size: 28, weight: .heavy))
                                .tracking(-1.1)
                                .foregroundStyle(titleColor)

                            Text("Connectez-vous à votre compte izifoot.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(mutedColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            Task {
                                await authStore.signInWithWeb()
                            }
                        } label: {
                            if authStore.isAuthenticating {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Connexion…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Se connecter")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .opacity(authStore.isAuthenticating ? 0.72 : 1)
                        .disabled(authStore.isAuthenticating)

                        Text("La connexion s’ouvre sur izifoot.fr dans une fenêtre sécurisée.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(mutedColor)
                            .fixedSize(horizontal: false, vertical: true)

                        if let errorMessage = authStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 460, alignment: .leading)
                    .padding(26)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(cardBorderColor, lineWidth: 1)
                    }
                    .shadow(color: cardShadow, radius: colorScheme == .dark ? 28 : 24, y: colorScheme == .dark ? 10 : 8)

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [logoGlow, .clear],
                center: .top,
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [fieldGlow, .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 360
            )
            .ignoresSafeArea()
        }
    }

    private var backgroundGradientColors: [Color] {
        colorScheme == .dark
            ? [AuthViewTheme.darkBackgroundTop, AuthViewTheme.darkBackgroundBottom]
            : [AuthViewTheme.lightBackgroundTop, AuthViewTheme.lightBackgroundBottom]
    }

    private var fieldGlow: Color {
        colorScheme == .dark ? AuthViewTheme.darkGlow : AuthViewTheme.lightGlow
    }

    private var logoGlow: Color {
        colorScheme == .dark ? AuthViewTheme.darkLogoGlow : AuthViewTheme.lightLogoGlow
    }

    private var cardBackground: Color {
        colorScheme == .dark ? AuthViewTheme.darkCard : AuthViewTheme.lightCard
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? AuthViewTheme.darkCardBorder : AuthViewTheme.lightCardBorder
    }

    private var cardShadow: Color {
        colorScheme == .dark ? AuthViewTheme.darkShadow : AuthViewTheme.lightShadow
    }

    private var logoShadow: Color {
        colorScheme == .dark ? AuthViewTheme.darkLogoShadow : AuthViewTheme.lightLogoShadow
    }

    private var titleColor: Color {
        colorScheme == .dark ? AuthViewTheme.darkText : AuthViewTheme.lightText
    }

    private var mutedColor: Color {
        colorScheme == .dark ? AuthViewTheme.darkMuted : AuthViewTheme.lightMuted
    }
}
