import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isSaving = false
    @State private var profileErrorMessage: String?

    private let api = IzifootAPI()

    var body: some View {
        NavigationStack {
            List {
                if let me = authStore.me {
                    Section("Compte") {
                        LabeledContent("Email", value: me.email)
                        LabeledContent("Rôle", value: me.role.rawValue)
                        LabeledContent("Premium", value: me.isPremium ? "Oui" : "Non")
                    }

                    Section("Modifier mon profil") {
                        TextField("Prénom", text: $firstName)
                            .textInputAutocapitalization(.words)
                        TextField("Nom", text: $lastName)
                            .textInputAutocapitalization(.words)
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        TextField("Téléphone", text: $phone)
                            .keyboardType(.phonePad)

                        Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                            Task { await saveProfile() }
                        }
                        .disabled(isSaving || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .task(id: authStore.me?.id) {
                guard let me = authStore.me else { return }
                firstName = me.firstName ?? ""
                lastName = me.lastName ?? ""
                email = me.email
                phone = me.phone ?? ""
            }
            .alert("Profil", isPresented: Binding(
                get: { profileErrorMessage != nil },
                set: { _ in profileErrorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(profileErrorMessage ?? "")
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await api.updateMeProfile(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await authStore.refreshMe()
            profileErrorMessage = "Profil mis à jour."
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }
}
