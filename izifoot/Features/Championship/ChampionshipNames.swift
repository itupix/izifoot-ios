import Foundation

/// Mirrors the server's name comparison without stripping accents.
enum ChampionshipNames {
    static func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func key(_ value: String) -> String {
        trimmed(value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "fr")))
    }
    static func error(for value: String, ownTeam: String, opponents: [String], excluding index: Int? = nil) -> String? {
        let name = trimmed(value)
        if name.isEmpty { return "Indiquez le nom de l’équipe." }
        if name.utf16.count > 120 { return "Le nom doit contenir au maximum 120 caractères." }
        let normalized = key(name)
        if normalized == key(ownTeam) { return "Votre équipe est déjà inscrite automatiquement." }
        if opponents.enumerated().contains(where: { $0.offset != index && key($0.element) == normalized }) {
            return "Cette équipe figure déjà dans la liste."
        }
        if index == nil && opponents.count >= 31 { return "Le championnat peut accueillir 32 équipes au maximum, votre équipe comprise." }
        return nil
    }
    static func championshipError(_ name: String) -> String? {
        if trimmed(name).isEmpty { return "Donnez un nom au championnat." }
        if trimmed(name).utf16.count > 200 { return "Le nom doit contenir au maximum 200 caractères." }
        return nil
    }
    static func matchCount(teams: Int, doubleRoundRobin: Bool) -> Int { teams * (teams - 1) / 2 * (doubleRoundRobin ? 2 : 1) }
}

