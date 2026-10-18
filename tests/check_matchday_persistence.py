#!/usr/bin/env python3
"""Run production persistence methods against a failing API, without an iOS simulator.

Uses the actual Swift method bodies and payload declarations; stubs only model/UI
storage and API transport. Run from any directory with Python 3 and Swift installed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'izifoot/Features/Planning/MatchdayDetailView.swift').read_text()
MODELS = (ROOT / 'izifoot/Core/Models/APIModels.swift').read_text()


def block(text, signature):
    start = text.index(signature)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


payloads = '\n'.join(block(MODELS, 'struct ' + name + ':') for name in (
    'MatchPayload', 'MatchSidesPayload', 'MatchSidePlayersPayload',
    'MatchScorePayload', 'MatchScorerPayload', 'MatchTacticPayload',
    'MatchTacticPointPayload'))
sheet_source = SOURCE[SOURCE.index('private final class MatchdayMatchesSheetViewModel:'):]
detail_source = SOURCE[SOURCE.index('private final class MatchdayMatchDetailViewModel:'):]
pager_source = SOURCE[SOURCE.index('private struct MatchdayMatchesPagerSheet:'):]
methods = {
    'detail_save': block(detail_source, 'func persistPendingChanges()'),
    'detail_discard': block(detail_source, 'func discardDeletedMatch()'),
    'all_save': block(sheet_source, 'func persistAllChanges()'),
    'all_discard': block(sheet_source, 'func discardDeletedMatch(id:'),
    'load_all': block(sheet_source, 'func loadAll(matches:') if 'func loadAll(matches:' in sheet_source else block(sheet_source, 'func loadAll(matches currentMatches:'),
    'delete': block(SOURCE, 'private func deleteMatchRecord(id:'),
    'pager_delete': block(pager_source, 'private func deleteMatch(id:'),
}
# UI integration guarantees that the executable method checks below depend on.
assert '.interactiveDismissDisabled()' in pager_source
assert '.onDisappear' not in pager_source[:pager_source.index('private struct MatchdayMatchDetailView:')]
assert 'if await sheetViewModel.persistAllChanges() {\n                                dismiss()' in pager_source
assert '.sheet(item: $selectedMatchDestination, onDismiss: {\n            Task { await viewModel.load() }' in SOURCE
assert '}().filter { !deletedMatchIDs.contains($0.id) }' in block(SOURCE, 'func load()')
assert block(SOURCE, 'private func reloadMatchesState()').count('filter { !deletedMatchIDs.contains($0.id) }') == 2

swift = r'''
import Foundation
PAYLOADS
struct MatchLite { let id: String; var matchdayId: String? = "plateau" }
struct MatchdaySummary {}
struct AttendanceRow {}
struct MatchTacticPoint { let x: Double; let y: Double }
struct Team { let side: String; let score: Int }
struct Player { let playerId: String }
struct Scorer { let playerId: String; let side: String; let assistId: String? }
struct MatchDetail {
    let id: String
    var matchdayId: String? = "plateau"
    let type = "PLATEAU"
    var teams = [Team(side: "home", score: 3), Team(side: "away", score: 1)]
    let awayStarters: [Player] = []
    let awaySubs: [Player] = []
    let scorers: [Scorer] = []
    let opponentName: String? = "Adversaire"
    let played: Bool? = true
    let rotationGameKey: String? = nil
}
struct Failure: Error {}
extension Error { var isCancellationError: Bool { false } }
final class API {
    var failing: Set<String> = []
    var updated: [(String, MatchPayload)] = []
    var deleted: [String] = []
    var blockedLoadID: String?
    var blockedLoad: CheckedContinuation<Void, Never>?
    func matchdaySummary(id: String, includeAllPlayers: Bool) async throws -> MatchdaySummary { MatchdaySummary() }
    func allAttendanceBySession(type: String, sessionID: String) async throws -> [AttendanceRow] { [] }
    func updateMatch(id: String, payload: MatchPayload) async throws -> Int {
        if failing.contains(id) { throw Failure() }
        updated.append((id, payload)); return 1
    }
    func deleteMatch(id: String) async throws {
        if failing.contains(id) { throw Failure() }
        deleted.append(id)
    }
}
final class Detail {
    let api: API
    var matchDetail: MatchDetail?
    var hasPendingChanges = true
    var isSaving = false
    var errorMessage: String?
    var tokens = ["one", "two"]
    var slotAssignments = ["one": "player-1", "two": "player-2"]
    var benchPlayerIDs = ["player-3"]
    var playersOnField = 2
    var selectedPreset = "balanced"
    var tacticPoints: [String: MatchTacticPoint] = [:]
    var selectedComposition: String?
    var loadCount = 0
    let matchID: String
    func load(sharedPlayers: [Player], summary: MatchdaySummary?, attendance: [AttendanceRow]?) async {
        loadCount += 1
        if api.blockedLoadID == matchID {
            await withCheckedContinuation { api.blockedLoad = $0 }
        }
        matchDetail = MatchDetail(id: matchID)
        hasPendingChanges = false
    }
    init(_ id: String, _ api: API) { self.api = api; self.matchID = id; self.matchDetail = MatchDetail(id: id) }
    DETAIL_SAVE
    DETAIL_DISCARD
}
final class Sheet {
    var isPersisting = false
    var matches: [MatchLite]
    var viewModelsByID: [String: Detail]
    var loadingTasksByID: [String: Task<Void, Never>] = [:]
    let sharedPlayers: [Player] = []
    let api: API
    func viewModel(for id: String) -> Detail {
        if let existing = viewModelsByID[id] { return existing }
        let detail = Detail(id, api); detail.matchDetail = nil; detail.hasPendingChanges = false
        viewModelsByID[id] = detail
        return detail
    }
    init(_ models: [String: Detail]) {
        viewModelsByID = models; matches = models.keys.sorted().map { MatchLite(id: $0) }
        api = models.values.first?.api ?? API()
    }
    LOAD_ALL
    ALL_SAVE
    ALL_DISCARD
}
final class Parent {
    let api: API
    var matches = [MatchLite(id: "deleted"), MatchLite(id: "survivor")]
    var deletedMatchIDs: Set<String> = []
    init(_ api: API) { self.api = api }
    DELETE
    func remove(_ id: String) async throws { try await deleteMatchRecord(id: id) }
}
final class Pager {
    let sheetViewModel: Sheet
    let onDeleteManualMatch: (String) async -> Bool
    var matches: [MatchLite]
    var selectedMatchID = "deleted"
    var isDeletingMatch = false
    var saveFailed = false
    var dismissCount = 0
    init(_ sheet: Sheet, _ deletion: @escaping (String) async -> Bool) {
        sheetViewModel = sheet; matches = sheet.matches; onDeleteManualMatch = deletion
    }
    func dismiss() { dismissCount += 1 }
    PAGER_DELETE
    func remove(_ id: String) async -> Bool { await deleteMatch(id: id) }
}
@main struct Checks {
    static func main() async throws {
        let api = API()
        let failed = Detail("failed", api), survivor = Detail("survivor", api)
        let sheet = Sheet(["failed": failed, "survivor": survivor])
        api.failing = ["failed"]
        let first = await sheet.persistAllChanges()
        precondition(!first && failed.hasPendingChanges && !survivor.hasPendingChanges)
        precondition(!sheet.isPersisting && !failed.isSaving && failed.errorMessage != nil)
        precondition(api.updated.map(\.0) == ["survivor"])
        api.failing = []
        let retry = await sheet.persistAllChanges()
        precondition(retry && !failed.hasPendingChanges && failed.errorMessage == nil)
        precondition(api.updated.map(\.0) == ["survivor", "failed"])
        let payload = api.updated.last!.1
        precondition(payload.score.home == 3 && payload.score.away == 1)
        precondition(payload.sides.home.starters == ["player-1", "player-2"])
        precondition(payload.sides.home.subs == ["player-3"])
        let missing = Detail("missing", api); missing.matchDetail = nil
        let missingSave = await missing.persistPendingChanges()
        precondition(!missingSave && missing.hasPendingChanges)

        let parent = Parent(api)
        try await parent.remove("deleted")
        precondition(parent.matches.map(\.id) == ["survivor"])
        precondition(parent.deletedMatchIDs == ["deleted"])
        api.failing = ["survivor"]
        do { try await parent.remove("survivor"); preconditionFailure("Delete should fail") } catch {}
        precondition(parent.matches.map(\.id) == ["survivor"])

        let deleted = Detail("deleted", api), sibling = Detail("survivor", api)
        let deletionSheet = Sheet(["deleted": deleted, "survivor": sibling])
        let pager = Pager(deletionSheet) { _ in true }
        let deletedOK = await pager.remove("deleted")
        precondition(deletedOK && pager.dismissCount == 0 && pager.saveFailed)
        precondition(!deleted.hasPendingChanges && sibling.hasPendingChanges)
        precondition(deletionSheet.viewModelsByID["deleted"] == nil)
        precondition(pager.selectedMatchID == "survivor" && !pager.isDeletingMatch)
        precondition(!api.updated.contains { $0.0 == "deleted" })
        api.failing = []
        let siblingRetry = await deletionSheet.persistAllChanges()
        precondition(siblingRetry && !sibling.hasPendingChanges)
        let cleanPager = Pager(Sheet(["deleted": Detail("deleted", api)])) { _ in true }
        let cleanDelete = await cleanPager.remove("deleted")
        precondition(cleanDelete && cleanPager.dismissCount == 1)
        cleanPager.isDeletingMatch = true
        let duplicate = await cleanPager.remove("deleted")
        precondition(!duplicate)
        // Reproduce three manual pages, interruption while later pages load,
        // deletion of the first page, then reopening the surviving pages.
        let lifecycleAPI = API()
        let one = Detail("one", lifecycleAPI), two = Detail("two", lifecycleAPI), three = Detail("three", lifecycleAPI)
        for detail in [one, two, three] { detail.matchDetail = nil; detail.hasPendingChanges = false }
        let lifecycle = Sheet(["one": one, "two": two, "three": three])
        lifecycleAPI.blockedLoadID = "two"
        let firstLoad = Task { await lifecycle.loadAll(matches: ["one", "two", "three"].map { MatchLite(id: $0) }) }
        while lifecycleAPI.blockedLoad == nil { await Task.yield() }
        firstLoad.cancel()
        lifecycle.discardDeletedMatch(id: "one")
        lifecycleAPI.blockedLoad?.resume(); lifecycleAPI.blockedLoad = nil
        await firstLoad.value
        precondition(one.matchDetail == nil && three.matchDetail == nil)
        // Existing loaded drafts must not be reset while missing pages retry.
        two.hasPendingChanges = true
        await lifecycle.loadAll(matches: ["two", "three"].map { MatchLite(id: $0) })
        precondition(two.loadCount == 1 && two.hasPendingChanges)
        precondition(three.loadCount == 1 && three.matchDetail != nil)
        three.hasPendingChanges = true
        let afterDeletionSave = await lifecycle.persistAllChanges()
        precondition(afterDeletionSave)
        precondition(Set(lifecycleAPI.updated.map(\.0)) == ["two", "three"])
        precondition(!lifecycleAPI.updated.contains { $0.0 == "one" })
        // A retained sheet must also load and save a newly displayed ID.
        await lifecycle.loadAll(matches: [MatchLite(id: "three"), MatchLite(id: "four")])
        let four = lifecycle.viewModel(for: "four")
        precondition(four.matchDetail != nil && lifecycle.viewModelsByID["two"] == nil)
        four.hasPendingChanges = true
        let newPageSave = await lifecycle.persistAllChanges()
        precondition(newPageSave && lifecycleAPI.updated.last!.0 == "four")
        print("PASS: three-match interrupted load/delete/reopen, active-ID synchronization, draft preservation")
        print("PASS: failed-save retention, retry score/lineup payloads, sibling save, deleted-ID exclusion, deletion failure, protected close, and refresh integration")
    }
}
'''
swift = swift.replace('PAYLOADS', payloads)
for name, method in sorted(methods.items(), key=lambda item: len(item[0]), reverse=True):
    swift = swift.replace(name.upper(), method)
with tempfile.TemporaryDirectory(prefix='izifoot-persistence-') as temp:
    path = Path(temp)
    (path / 'Checks.swift').write_text(swift)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True)
