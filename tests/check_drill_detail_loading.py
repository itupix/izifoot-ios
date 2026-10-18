#!/usr/bin/env python3
"""Execute production exercise loading methods with independent API failures."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'izifoot/Features/Drills/DrillDetailView.swift').read_text()

def block(signature):
    start = source.index(signature)
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

methods = '\n'.join(block(signature) for signature in (
    'func load(drillID:', 'func loadDrill(drillID:', 'func loadDiagram(drillID:'))
swift = r'''
import Foundation
struct Drill { let id: String }
struct Diagram { let id: String }
struct Failure: LocalizedError { var errorDescription: String? { "Unavailable" } }
extension Error { var isCancellationError: Bool { self is CancellationError } }
@MainActor final class API {
    var failDrill = false
    var failDiagram = false
    var blockDiagram = false
    var continuation: CheckedContinuation<Void, Never>?
    var route = ""
    func drill(id: String) async throws -> Drill {
        if failDrill { throw Failure() }
        return Drill(id: id)
    }
    func drillDiagrams(drillID: String) async throws -> [Diagram] {
        route = "source:" + drillID
        if blockDiagram { await withCheckedContinuation { continuation = $0 } }
        if failDiagram { throw Failure() }
        return [Diagram(id: "loaded")]
    }
    func trainingDrillDiagrams(trainingDrillID: String) async throws -> [Diagram] {
        route = "training:" + trainingDrillID
        if failDiagram { throw Failure() }
        return []
    }
}
@MainActor final class Model {
    let api = API()
    var drill: Drill?
    var diagram: Diagram?
    var isLoading = false
    var isLoadingDiagram = false
    var loadErrorMessage: String?
    var diagramErrorMessage: String?
    METHODS
}
@main struct Checks {
    @MainActor static func main() async {
        let model = Model()
        model.api.failDiagram = true
        model.api.blockDiagram = true
        let load = Task { await model.load(drillID: "source", trainingDrillID: nil) }
        while model.api.continuation == nil || model.drill == nil { await Task.yield() }
        precondition(model.drill?.id == "source" && !model.isLoading && model.isLoadingDiagram)
        model.api.continuation?.resume()
        await load.value
        precondition(model.drill != nil && model.loadErrorMessage == nil)
        precondition(model.diagram == nil && model.diagramErrorMessage == "Unavailable" && !model.isLoadingDiagram)
        model.api.failDiagram = false
        model.api.blockDiagram = false
        await model.loadDiagram(drillID: "source", trainingDrillID: nil)
        precondition(model.diagram?.id == "loaded" && model.diagramErrorMessage == nil)
        precondition(model.api.route == "source:source")
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        precondition(model.api.route == "training:link" && model.diagram == nil && model.diagramErrorMessage == nil)
        let failing = Model()
        failing.api.failDrill = true
        await failing.load(drillID: "source", trainingDrillID: nil)
        precondition(failing.drill == nil && failing.loadErrorMessage == "Unavailable" && !failing.isLoading)
        precondition(failing.diagram != nil && failing.diagramErrorMessage == nil)
        failing.api.failDrill = false
        await failing.loadDrill(drillID: "source")
        precondition(failing.drill?.id == "source" && failing.loadErrorMessage == nil)
        print("PASS: exercise appears before diagram completes; independent failures, retries and source/training diagram routes")
    }
}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='izifoot-drill-loading-') as temp:
    path = Path(temp)
    (path / 'Checks.swift').write_text(swift)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True)
