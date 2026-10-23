#!/usr/bin/env python3
"""Execute production materials loading against failures and overlapping refreshes."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'izifoot/Features/Planning/TrainingDetailView.swift').read_text()
start = source.index('    func loadMaterials() async {')
end = source.index('\n    func load() async', start)
method = source[start:end]
models = (root / 'izifoot/Core/Models/APIModels.swift').read_text().split('struct TrainingMaterialsResponse: Decodable {')[1]
models = 'struct TrainingMaterialsResponse: Decodable {' + models
harness = r'''
import Foundation
struct Failure: Error {}
extension Error { var isCancellationError: Bool { self is CancellationError } }
@MainActor final class API {
    var fail = false
    var block = false
    var continuation: CheckedContinuation<TrainingMaterialsResponse, Never>?
    func trainingMaterials(trainingID: String) async throws -> TrainingMaterialsResponse {
        precondition(trainingID == "training-1")
        if fail { throw Failure() }
        if block { return await withCheckedContinuation { continuation = $0 } }
        return TrainingMaterialsResponse(items: [], drillCount: 0, missingDiagramCount: 0)
    }
}
@MainActor final class Model {
    let api = API()
    let training = (id: "training-1", unused: 0)
    var materials: TrainingMaterialsResponse?
    var isLoadingMaterials = false
    var materialsError: String?
    var materialsRequestID = UUID()
METHOD
}
@main struct Checks {
    @MainActor static func main() async throws {
        let response = try JSONDecoder().decode(TrainingMaterialsResponse.self, from: Data(#"{"items":[{"type":"cone","label":"Cônes","quantity":3},{"type":"bib","label":"Chasubles","quantity":null}],"drillCount":2,"missingDiagramCount":1}"#.utf8))
        precondition(response.items[0].quantity == 3 && response.items[1].quantity == nil)
        precondition(response.missingDiagramCount == 1 && response.drillCount == 2)
        let model = Model()
        await model.loadMaterials()
        precondition(model.materials?.drillCount == 0 && !model.isLoadingMaterials)
        model.api.fail = true
        await model.loadMaterials()
        precondition(model.materials == nil && model.materialsError != nil && !model.isLoadingMaterials)
        model.api.fail = false
        model.api.block = true
        let old = Task { await model.loadMaterials() }
        while model.api.continuation == nil { await Task.yield() }
        model.api.block = false
        await model.loadMaterials()
        model.api.continuation?.resume(returning: response)
        await old.value
        precondition(model.materials?.drillCount == 0, "Old response must not overwrite current selection")
        precondition(model.materialsError == nil && !model.isLoadingMaterials)
        print("Training materials decoding, failure, retry and concurrent refresh checks passed")
    }
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'Checks.swift'
    path.write_text(harness.replace('METHOD', method) + '\n' + models)
    binary = Path(directory) / 'checks'
    subprocess.run(['swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
