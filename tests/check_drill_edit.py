#!/usr/bin/env python3
"""Execute the production drill editor state against failing and suspended saves."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def block(source, signature):
    start = source.index(signature)
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

models = (ROOT / 'izifoot/Core/Models/APIModels.swift').read_text()
source = (ROOT / 'izifoot/Features/Drills/DrillDetailView.swift').read_text()
api = (ROOT / 'izifoot/Core/Networking/IzifootAPI.swift').read_text()
production = '\n'.join([
    block(models, 'enum DrillCategory:'), block(models, 'struct Drill:'),
    '@MainActor\n' + block(source, 'final class DrillEditViewModel:'),
    block(api, 'struct UpdateDrillPayload:'),
])
checks = r'''
struct Failure: LocalizedError { var errorDescription: String? { "Save failed" } }
@main struct Checks {
    @MainActor static func main() async throws {
        let original = Drill(id: "source-drill", title: "Initial", category: "autres", description: "Initial description", descriptionHtml: nil, tags: ["preserve"], teamId: "team")
        let canonical = Drill(id: original.id, title: "Canonical", category: "technique", description: "Canonical description", descriptionHtml: "<p>Canonical description</p>", tags: original.tags, teamId: original.teamId)
        var attempts = 0
        var fail = true
        var pending: CheckedContinuation<Void, Never>?
        let editor = DrillEditViewModel(drill: original) { title, description, category in
            attempts += 1
            precondition(title == "Edited" && description == "Updated description" && category == "technique")
            if fail { throw Failure() }
            await withCheckedContinuation { pending = $0 }
            return canonical
        }
        precondition(editor.title == original.title && editor.category == original.category)
        editor.title = "  "
        precondition(editor.validationError != nil)
        let invalid = await editor.save()
        precondition(invalid == nil && attempts == 0)
        editor.title = String(repeating: "a", count: 101)
        precondition(editor.validationError != nil)
        editor.title = String(repeating: "⚽️", count: 51)
        precondition(editor.validationError != nil)
        editor.title = " Edited \n"
        editor.description = String(repeating: "a", count: 2001)
        precondition(editor.validationError != nil)
        editor.description = " Updated description \n"
        editor.category = "invalid"
        precondition(editor.validationError != nil)
        editor.category = "technique"
        let failed = await editor.save()
        precondition(failed == nil && !editor.isSaving && editor.errorMessage == "Save failed")
        precondition(editor.title == " Edited \n" && editor.description == " Updated description \n")
        fail = false
        let save = Task { await editor.save() }
        while pending == nil { await Task.yield() }
        precondition(editor.isSaving)
        let duplicate = await editor.save()
        precondition(duplicate == nil && attempts == 2)
        pending?.resume()
        let result = await save.value
        precondition(result?.title == "Canonical" && result?.descriptionHtml == canonical.descriptionHtml)
        precondition(result?.tags == ["preserve"] && !editor.isSaving && editor.errorMessage == nil)
        let payload = UpdateDrillPayload(title: "Edited", description: "Updated description", category: "technique")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        precondition(Set(encoded.keys) == ["title", "description", "category"])
        print("PASS: validation, trimmed payload, draft retention after error, retry, duplicate prevention, canonical response and preserved tags")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='izifoot-drill-edit-') as temp:
    path = Path(temp)
    (path / 'Checks.swift').write_text('import Foundation\nimport Combine\n' + production + checks)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True)
