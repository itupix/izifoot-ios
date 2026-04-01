import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isSaving = false
    @State private var profileErrorMessage: String?
    @State private var linkedChild: LinkedChildProfile?
    @State private var teamNameByID: [String: String] = [:]
    @State private var isEditSheetPresented = false

    private let api = IzifootAPI()

    var body: some View {
        NavigationStack {
            List {
                if let me = authStore.me {
                    Section("Moi") {
                        HStack {
                            Spacer()
                            Button("Modifier") {
                                isEditSheetPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        LabeledContent("Prénom", value: displayValue(me.firstName))
                        LabeledContent("Nom", value: displayValue(me.lastName))
                        LabeledContent("Email", value: me.email)
                        LabeledContent("Téléphone", value: displayValue(me.phone))
                        if me.role != .parent {
                            LabeledContent("Équipe", value: teamDisplayName(for: me.teamId))
                        }
                    }

                    if me.role == .parent {
                        Section("Mon enfant") {
                            if let child = linkedChild {
                                LabeledContent("Prénom", value: displayValue(child.firstName))
                                LabeledContent("Nom", value: displayValue(child.lastName ?? child.name))
                                LabeledContent("Licence", value: displayValue(child.licence))
                                LabeledContent("Équipe", value: child.teamName ?? teamDisplayName(for: child.teamId))
                            } else {
                                Text("Aucun enfant lié")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !me.managedTeamIds.isEmpty {
                        Section("Équipes gérées") {
                            ForEach(me.managedTeamIds, id: \.self) { teamID in
                                Text(teamDisplayName(for: teamID))
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
            }
            .navigationTitle("Mon compte")
            .task(id: authStore.me?.id) {
                guard let me = authStore.me else { return }
                firstName = me.firstName ?? ""
                lastName = me.lastName ?? ""
                email = me.email
                phone = me.phone ?? ""
                await loadTeamsAndChild(for: me)
            }
            .refreshable {
                await authStore.refreshMe()
                guard let me = authStore.me else { return }
                firstName = me.firstName ?? ""
                lastName = me.lastName ?? ""
                email = me.email
                phone = me.phone ?? ""
                await loadTeamsAndChild(for: me)
            }
            .sheet(isPresented: $isEditSheetPresented) {
                NavigationStack {
                    Form {
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
                        }
                    }
                    .navigationTitle("Modifier")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fermer") {
                                isEditSheetPresented = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                                Task {
                                    if await saveProfile() {
                                        isEditSheetPresented = false
                                    }
                                }
                            }
                            .disabled(
                                isSaving
                                || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || (email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            )
                        }
                    }
                }
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

    private func loadTeamsAndChild(for me: Me) async {
        do {
            let teams = try await api.teams()
            var map: [String: String] = [:]
            for team in teams {
                map[team.id] = team.name
            }
            teamNameByID = map
        } catch {
            teamNameByID = [:]
        }

        if me.role == .parent {
            do {
                linkedChild = try await api.meLinkedChild()
            } catch {
                linkedChild = nil
            }
        } else {
            linkedChild = nil
        }
    }

    private func teamDisplayName(for teamID: String?) -> String {
        guard let teamID, !teamID.isEmpty else { return "—" }
        return teamNameByID[teamID] ?? teamID
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    @discardableResult
    private func saveProfile() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        let normalizedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFirstName.isEmpty, !normalizedLastName.isEmpty, !(normalizedEmail.isEmpty && normalizedPhone.isEmpty) else {
            profileErrorMessage = "Merci de renseigner prénom, nom et au moins un contact (e-mail ou téléphone)."
            return false
        }

        do {
            _ = try await api.updateMeProfile(
                firstName: normalizedFirstName,
                lastName: normalizedLastName,
                email: normalizedEmail.isEmpty ? nil : normalizedEmail,
                phone: normalizedPhone.isEmpty ? nil : normalizedPhone
            )
            await authStore.refreshMe()
            profileErrorMessage = "Profil mis à jour."
            return true
        } catch {
            profileErrorMessage = error.localizedDescription
            return false
        }
    }
}
