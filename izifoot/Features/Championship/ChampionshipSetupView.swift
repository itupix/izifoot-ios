import SwiftUI

struct ChampionshipSetupView: View {
    let ownTeamName: String
    let isBusy: Bool
    var errorMessage: String? = nil
    var showTeamPicker = false
    let onGenerate: (String, [String], Bool) -> Void
    @State private var step = 0
    @State private var name = ""
    @State private var roundTrip = true
    @State private var opponents: [String] = []
    @State private var teamInput = ""
    @State private var teamError: String?
    @State private var attemptedName = false
    @State private var renamingIndex: Int?
    @State private var renameInput = ""
    @State private var renameError: String?
    @FocusState private var inputFocused: Bool
    private let steps = ["Championnat", "Équipes", "Vérifier"]

    var body: some View {
        List {
        if showTeamPicker { Section { TeamScopePicker() } }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Créer votre championnat").font(.title2.bold())
                Text("Étape \(step + 1) sur 3 · \(steps[step])").font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(step + 1), total: 3).accessibilityLabel("Étape \(step + 1) sur 3")
            }.padding(.vertical, 8)
        }
        if step == 0 { championshipStep }
        else if step == 1 { teamsStep }
        else { reviewStep }
        if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button { inputFocused = false; step -= 1 } label: { Label("Retour", systemImage: "chevron.left").frame(minHeight: 44) }.buttonStyle(.bordered)
                }
                Button(action: advance) {
                    HStack { Spacer(minLength: 0); Text(step == 2 ? "Générer le calendrier" : "Continuer").bold(); if step < 2 { Image(systemName: "chevron.right") }; Spacer(minLength: 0) }.frame(minHeight: 44)
                }.buttonStyle(.borderedProminent)
            }.disabled(isBusy).padding().background(.bar)
        }
        .sheet(isPresented: Binding(get: { renamingIndex != nil }, set: { if !$0 { renamingIndex = nil } })) {
            NavigationStack {
                Form {
                    Section("Nom de l’équipe") {
                        TextField("Nom", text: $renameInput).textInputAutocapitalization(.words)
                            .onChange(of: renameInput) { _ in
                                renameError = ChampionshipNames.error(for: renameInput, ownTeam: ownTeamName, opponents: opponents, excluding: renamingIndex)
                            }
                        if let renameError { Text(renameError).font(.footnote).foregroundStyle(.red) }
                    }
                }
                .navigationTitle("Renommer l’équipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { renamingIndex = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { rename() }.disabled(ChampionshipNames.error(for: renameInput, ownTeam: ownTeamName, opponents: opponents, excluding: renamingIndex) != nil) }
                }
            }.presentationDetents([.medium, .large])
        }
    }
    private var championshipStep: some View {
        Section {
            TextField("Nom du championnat", text: $name).textInputAutocapitalization(.sentences).submitLabel(.next).onSubmit(advance)
            if attemptedName, let error = ChampionshipNames.championshipError(name) { Text(error).font(.footnote).foregroundStyle(.red) }
            Toggle("Matchs aller-retour", isOn: $roundTrip)
                .frame(minHeight: 44)
            Text(roundTrip ? "Chaque équipe rencontre ses adversaires à domicile et à l’extérieur." : "Chaque équipe rencontre ses adversaires une fois.").font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Les bases") } footer: { Text("Vous choisirez les dates et les horaires après la génération du calendrier.") }
    }
    private var teamsStep: some View {
        Group {
            Section("Votre équipe") {
                Label { VStack(alignment: .leading, spacing: 4) { Text(ownTeamName).bold(); Text("Déjà inscrite · non modifiable ici").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "lock.fill").foregroundStyle(.secondary) }.padding(.vertical, 4)
            }
            Section {
                HStack {
                    TextField("Nom d’une équipe adverse", text: $teamInput)
                        .focused($inputFocused).textInputAutocapitalization(.words).submitLabel(.done)
                        .onSubmit { _ = addTeam(); inputFocused = true }
                        .onChange(of: teamInput) { _ in
                            teamError = teamInput.isEmpty ? nil : ChampionshipNames.error(for: teamInput, ownTeam: ownTeamName, opponents: opponents)
                        }
                    Button { _ = addTeam(); inputFocused = true } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Ajouter cette équipe")
                }
                if let teamError { Text(teamError).font(.footnote).foregroundStyle(.red) }
                if opponents.isEmpty { Text("Ajoutez au moins un adversaire pour créer les rencontres.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(opponents.enumerated()), id: \.offset) { index, opponent in
                    HStack {
                        Button { renameInput = opponent; renameError = nil; renamingIndex = index } label: {
                            HStack { Text(opponent).foregroundStyle(.primary); Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary) }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Renommer \(opponent)")
                        Button(role: .destructive) { opponents.remove(at: index); teamError = nil } label: { Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44) }.buttonStyle(.borderless).accessibilityLabel("Retirer \(opponent)")
                    }
                }
            } header: {
                HStack { Text("Adversaires"); Spacer(); Text("\(opponents.count + 1) / 32 équipes") }
            } footer: { Text("Ajoutez une équipe à la fois. Touchez son nom pour le modifier.") }
        }
    }
    private var reviewStep: some View {
        Group {
            Section("Votre championnat") {
                Text(ChampionshipNames.trimmed(name)).font(.headline)
                Label(roundTrip ? "Aller-retour" : "Rencontres simples", systemImage: "arrow.left.arrow.right")
                Label("\(opponents.count + 1) équipes · \(ChampionshipNames.matchCount(teams: opponents.count + 1, doubleRoundRobin: roundTrip)) rencontres", systemImage: "soccerball")
            }
            Section("Équipes inscrites") {
                Label("\(ownTeamName) · Votre équipe", systemImage: "person.fill.checkmark")
                ForEach(opponents, id: \.self) { Text($0) }
            }
            Section {
                Label("Les équipes et le format seront figés dès la génération.", systemImage: "lock.fill").font(.subheadline)
                Text("Vérifiez la liste avant de continuer. Vous pourrez ensuite organiser les rencontres et ajouter leurs dates et horaires.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    @discardableResult private func addTeam() -> Bool {
        if let error = ChampionshipNames.error(for: teamInput, ownTeam: ownTeamName, opponents: opponents) { teamError = error; return false }
        opponents.append(ChampionshipNames.trimmed(teamInput)); teamInput = ""; teamError = nil; return true
    }
    private func advance() {
        inputFocused = false
        if step == 0 {
            attemptedName = true
            guard ChampionshipNames.championshipError(name) == nil else { return }
            step = 1
        } else if step == 1 {
            // Keep an entered opponent when the user continues without tapping Add.
            if !ChampionshipNames.trimmed(teamInput).isEmpty && !addTeam() { inputFocused = true; return }
            guard !opponents.isEmpty else { teamError = "Ajoutez au moins une équipe adverse."; inputFocused = true; return }
            step = 2
        } else { onGenerate(ChampionshipNames.trimmed(name), opponents, roundTrip) }
    }
    private func rename() {
        guard let index = renamingIndex, opponents.indices.contains(index) else { return }
        if let error = ChampionshipNames.error(for: renameInput, ownTeam: ownTeamName, opponents: opponents, excluding: index) {
            renameError = error; return
        }
        opponents[index] = ChampionshipNames.trimmed(renameInput); renamingIndex = nil; renameError = nil
    }
}
