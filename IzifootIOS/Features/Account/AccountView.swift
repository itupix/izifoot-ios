import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        NavigationStack {
            List {
                if let me = authStore.me {
                    Section("Compte") {
                        LabeledContent("Email", value: me.email)
                        LabeledContent("Rôle", value: me.role.rawValue)
                        LabeledContent("Premium", value: me.isPremium ? "Oui" : "Non")
                    }

                    if let teamID = me.teamId {
                        Section("Equipe liée") {
                            Text(teamID)
                        }
                    }

                    if !me.managedTeamIds.isEmpty {
                        Section("Equipes gérées") {
                            ForEach(me.managedTeamIds, id: \.self) { teamID in
                                Text(teamID)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await authStore.logout()
                        }
                    } label: {
                        Text("Se déconnecter")
                    }
                }

                Section("Outils") {
                    NavigationLink("Ouvrir un lien public plateau") {
                        PublicMatchdayView()
                    }
                }
            }
            .navigationTitle("Compte")
        }
    }
}
