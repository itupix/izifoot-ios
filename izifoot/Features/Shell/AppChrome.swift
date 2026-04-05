import SwiftUI

private enum AppChromeDestination: String, Identifiable {
    case account
    case club

    var id: String { rawValue }
}

private struct AppChromeModifier: ViewModifier {
    @EnvironmentObject private var authStore: AuthStore
    @State private var destination: AppChromeDestination?

    let showTeamScopePicker: Bool
    let showsBranding: Bool
    let showsTrailingMenu: Bool

    private var showsAccountShortcutOnly: Bool {
        guard let role = authStore.me?.role else { return false }
        return role == .player || role == .parent
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsBranding {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 0) {
                            Image("LogoHeader")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 150, height: 30, alignment: .leading)
                                .allowsHitTesting(false)
                                .accessibilityLabel("izifoot")
                            Spacer(minLength: 0)
                        }
                        .frame(width: 220, alignment: .leading)
                    }
                }

                if showTeamScopePicker {
                    ToolbarItem(placement: .topBarTrailing) {
                        TeamScopePicker()
                    }
                }

                if showsTrailingMenu {
                    if showsAccountShortcutOnly {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                destination = .account
                            } label: {
                                Image(systemName: "person.circle")
                            }
                            .accessibilityLabel("Mon compte")
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Mon compte") {
                                    destination = .account
                                }

                                if authStore.me?.role == .direction {
                                    Button("Mon club") {
                                        destination = .club
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $destination) { item in
                switch item {
                case .account:
                    AccountView()
                case .club:
                    ClubHomeView()
                }
            }
    }
}

extension View {
    func appChrome(
        showTeamScopePicker: Bool = true,
        showsBranding: Bool = true,
        showsTrailingMenu: Bool = true
    ) -> some View {
        modifier(
            AppChromeModifier(
                showTeamScopePicker: showTeamScopePicker,
                showsBranding: showsBranding,
                showsTrailingMenu: showsTrailingMenu
            )
        )
    }
}
