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

    func body(content: Content) -> some View {
        content
            .toolbar {
                if showsBranding {
                    ToolbarItem(placement: .topBarLeading) {
                        Label {
                            Text("izifoot")
                                .font(.headline.weight(.semibold))
                        } icon: {
                            Image(systemName: "soccerball")
                                .imageScale(.medium)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }

                if showTeamScopePicker {
                    ToolbarItem(placement: .topBarTrailing) {
                        TeamScopePicker()
                    }
                }

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
    func appChrome(showTeamScopePicker: Bool = true, showsBranding: Bool = true) -> some View {
        modifier(AppChromeModifier(showTeamScopePicker: showTeamScopePicker, showsBranding: showsBranding))
    }
}
