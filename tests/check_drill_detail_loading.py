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
    'func load(drillID:', 'func loadDrill(drillID:', 'func loadDiagram(drillID:', 'func saveDiagram('))
swift = r'''
import Foundation
struct Drill { let id: String }
struct Diagram { let id: String; var trainingDrillId: String? = nil }
struct DiagramData {}
struct Failure: LocalizedError { var errorDescription: String? { "Unavailable" } }
extension Error { var isCancellationError: Bool { self is CancellationError } }
@MainActor final class API {
    var failDrill = false
    var failDiagram = false
    var failTraining = false
    var trainingDiagrams: [Diagram] = []
    var catalogDiagrams: [Diagram] = [Diagram(id: "loaded")]
    var catalogRequests = 0
    var blockDiagram = false
    var continuation: CheckedContinuation<Void, Never>?
    var route = ""
    func drill(id: String) async throws -> Drill {
        if failDrill { throw Failure() }
        return Drill(id: id)
    }
    func drillDiagrams(drillID: String) async throws -> [Diagram] {
        route = "source:" + drillID
        catalogRequests += 1
        if blockDiagram { await withCheckedContinuation { continuation = $0 } }
        if failDiagram { throw Failure() }
        return catalogDiagrams
    }
    func trainingDrillDiagrams(trainingDrillID: String) async throws -> [Diagram] {
        route = "training:" + trainingDrillID
        if failTraining { throw Failure() }
        return trainingDiagrams
    }
}
extension API {
    func updateDiagram(id: String, title: String, data: DiagramData) async throws -> Diagram {
        route = "update:" + id
        return Diagram(id: id)
    }
    func createTrainingDrillDiagram(trainingDrillID: String, data: DiagramData) async throws -> Diagram {
        route = "createTraining:" + trainingDrillID
        return Diagram(id: "override", trainingDrillId: trainingDrillID)
    }
    func createDrillDiagram(drillID: String, data: DiagramData) async throws -> Diagram {
        route = "createCatalog:" + drillID
        return Diagram(id: "created")
    }
}
@MainActor final class Model {
    let api = API()
    var drill: Drill?
    var diagram: Diagram?
    var isLoading = false
    var isLoadingDiagram = false
    var isSavingDiagram = false
    var errorMessage: String?
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
        precondition(model.api.route == "source:source" && model.diagram?.id == "loaded" && model.diagramErrorMessage == nil)
        let catalogCount = model.api.catalogRequests
        model.api.trainingDiagrams = [Diagram(id: "session", trainingDrillId: "link"), Diagram(id: "older", trainingDrillId: "link")]
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        precondition(model.diagram?.id == "session" && model.api.catalogRequests == catalogCount)
        model.api.failTraining = true
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        precondition(model.diagramErrorMessage == "Unavailable" && model.api.catalogRequests == catalogCount)
        model.api.failTraining = false
        model.api.trainingDiagrams = []
        model.api.failDiagram = true
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        precondition(model.diagramErrorMessage == "Unavailable")
        model.api.failDiagram = false
        model.api.catalogDiagrams = []
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        precondition(model.diagram == nil && model.diagramErrorMessage == nil)
        model.api.catalogDiagrams = [Diagram(id: "loaded")]
        await model.loadDiagram(drillID: "source", trainingDrillID: "link")
        let savedFallback = await model.saveDiagram(DiagramData(), drillID: "source", trainingDrillID: "link")
        precondition(savedFallback && model.api.route == "createTraining:link" && model.diagram?.trainingDrillId == "link")
        let savedOverride = await model.saveDiagram(DiagramData(), drillID: "source", trainingDrillID: "link")
        precondition(savedOverride && model.api.route == "update:override")
        await model.loadDiagram(drillID: "source", trainingDrillID: nil)
        let savedCatalog = await model.saveDiagram(DiagramData(), drillID: "source", trainingDrillID: nil)
        precondition(savedCatalog && model.api.route == "update:loaded")
        let failing = Model()
        failing.api.failDrill = true
        await failing.load(drillID: "source", trainingDrillID: nil)
        precondition(failing.drill == nil && failing.loadErrorMessage == "Unavailable" && !failing.isLoading)
        precondition(failing.diagram != nil && failing.diagramErrorMessage == nil)
        failing.api.failDrill = false
        await failing.loadDrill(drillID: "source")
        precondition(failing.drill?.id == "source" && failing.loadErrorMessage == nil)
        print("PASS: exercise appears before diagram completes; independent failures/retries, session/catalog precedence, empty sources, safe session overrides and catalog edits")
    }
}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='izifoot-drill-loading-') as temp:
    path = Path(temp)
    (path / 'Checks.swift').write_text(swift)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks')], check=True)
