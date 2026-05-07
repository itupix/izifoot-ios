import SwiftUI

struct DiagramEditorView: View {
    @Binding var data: DiagramData

    @State private var tool: DiagramEditorTool = .select
    @State private var selectedItemID: String?
    @State private var activeFrameIndex = 0
    @State private var pendingArrowID: String?
    @State private var dragStartByItemID: [String: DiagramPoint] = [:]

    private var frames: [DiagramFrame] {
        data.frames.isEmpty ? DiagramData.empty.frames : data.frames
    }

    private var activeFrame: DiagramFrame {
        frames[min(activeFrameIndex, frames.count - 1)]
    }

    private var selectedItem: DiagramItem? {
        activeFrame.items.first { $0.id == selectedItemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DiagramEditorTool.allCases) { item in
                        Button {
                            tool = item
                            if item != .select {
                                selectedItemID = nil
                            }
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(tool == item ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
                                .foregroundStyle(tool == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selectedItemID == nil)

                Button(role: .destructive) {
                    resetDiagram()
                } label: {
                    Label("Reinitialiser", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!data.hasContent)

                Spacer()

                Button {
                    previousFrame()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(activeFrameIndex == 0)

                Button {
                    nextFrame()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(activeFrameIndex >= frames.count - 1)

                Button {
                    rotateClockwise()
                } label: {
                    Image(systemName: "rotate.right.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            DiagramFieldSurface(
                quarterTurns: data.rotationQuarterTurns,
                minHeight: 340,
                items: activeFrame.items,
                selectedItemID: selectedItemID
            ) { layout in
                fieldInteractionLayer(layout: layout)

                ForEach(activeFrame.items.filter { !$0.isArrow }, id: \.id) { item in
                    DiagramNodeView(item: item, layout: layout, isSelected: item.id == selectedItemID)
                        .allowsHitTesting(tool == .select)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                guard tool == .select else { return }
                                selectedItemID = item.id
                            }
                        )
                        .gesture(itemDragGesture(item: item, layout: layout))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0 ..< DiagramData.maxSteps, id: \.self) { index in
                        Button {
                            activeFrameIndex = index
                            selectedItemID = nil
                        } label: {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(index == activeFrameIndex ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Circle())
                                .foregroundStyle(index == activeFrameIndex ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selectedItem {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Element selectionne : \(diagramItemName(selectedItem))")
                        .font(.subheadline.weight(.medium))

                    if case let .player(player) = selectedItem {
                        Picker("Couleur", selection: Binding(
                            get: { player.color },
                            set: { updateSelectedPlayerColor($0) }
                        )) {
                            ForEach(DiagramPlayerColor.allCases, id: \.self) { color in
                                Text(color.label).tag(color)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField(
                            "Label",
                            text: Binding(
                                get: { player.label },
                                set: { updateSelectedPlayerLabel($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text("Les joueurs et ballons se propagent a partir de l'etape courante. Le materiel reste synchronise sur toutes les etapes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: data.rotationQuarterTurns) { _, _ in
            dragStartByItemID.removeAll()
            pendingArrowID = nil
        }
    }

    @ViewBuilder
    private func fieldInteractionLayer(layout: DiagramCanvasLayout) -> some View {
        Color.clear
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
            .contentShape(Rectangle())
            .position(x: layout.fieldRect.midX, y: layout.fieldRect.midY)
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let point = layout.modelPoint(fromLocal: value.location)
                        handleTap(at: point)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard tool == .arrow else { return }
                        updatePendingArrow(
                            from: layout.modelPoint(fromLocal: value.startLocation),
                            to: layout.modelPoint(fromLocal: value.location)
                        )
                    }
                    .onEnded { value in
                        guard tool == .arrow else { return }
                        finishPendingArrow(
                            from: layout.modelPoint(fromLocal: value.startLocation),
                            to: layout.modelPoint(fromLocal: value.location)
                        )
                    }
            )
    }

    private func itemDragGesture(item: DiagramItem, layout: DiagramCanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard tool == .select, let startPoint = item.point else { return }
                if dragStartByItemID[item.id] == nil {
                    dragStartByItemID[item.id] = startPoint
                    selectedItemID = item.id
                }

                guard let basePoint = dragStartByItemID[item.id] else { return }
                let translatedPoint = DiagramPoint(
                    x: basePoint.x + Double(value.translation.width / layout.scale),
                    y: basePoint.y + Double(value.translation.height / layout.scale)
                )
                let nextPoint = DiagramData.clamp(
                    DiagramPoint(
                        x: DiagramData.snap(translatedPoint.x),
                        y: DiagramData.snap(translatedPoint.y)
                    ),
                    within: data.fieldSize
                )
                moveItem(item, to: nextPoint)
            }
            .onEnded { _ in
                dragStartByItemID[item.id] = nil
            }
    }

    private func handleTap(at point: DiagramPoint) {
        pendingArrowID = nil

        switch tool {
        case .select:
            selectedItemID = diagramHitTest(items: activeFrame.items, point: point)?.id
        case .player:
            addPersistentItem(.player(DiagramPlayerNode(id: DiagramItem.makeID(), x: point.x, y: point.y, label: "", color: .blue)))
        case .cone:
            addPersistentItem(.cone(DiagramFieldNode(id: DiagramItem.makeID(), x: point.x, y: point.y)))
        case .cup:
            addPersistentItem(.cup(DiagramFieldNode(id: DiagramItem.makeID(), x: point.x, y: point.y)))
        case .ball:
            addPersistentItem(.ball(DiagramFieldNode(id: DiagramItem.makeID(), x: point.x, y: point.y)))
        case .post:
            addPersistentItem(.post(DiagramFieldNode(id: DiagramItem.makeID(), x: point.x, y: point.y)))
        case .arrow:
            break
        }
    }

    private func updatePendingArrow(from: DiagramPoint, to: DiagramPoint) {
        if pendingArrowID == nil {
            let id = DiagramItem.makeID()
            pendingArrowID = id
            selectedItemID = id
            updateCurrentFrameItems { items in
                items + [.arrow(DiagramArrowNode(id: id, from: from, to: to))]
            }
            return
        }

        guard let pendingArrowID else { return }
        updateCurrentFrameItems { items in
            items.map { item in
                guard case let .arrow(node) = item, node.id == pendingArrowID else { return item }
                return .arrow(DiagramArrowNode(id: node.id, from: from, to: to))
            }
        }
    }

    private func finishPendingArrow(from: DiagramPoint, to: DiagramPoint) {
        defer { pendingArrowID = nil }
        guard let pendingArrowID else { return }

        if from == to {
            updateCurrentFrameItems { items in
                items.filter { $0.id != pendingArrowID }
            }
            if selectedItemID == pendingArrowID {
                selectedItemID = nil
            }
        } else {
            updatePendingArrow(from: from, to: to)
        }
    }

    private func previousFrame() {
        activeFrameIndex = max(0, activeFrameIndex - 1)
        selectedItemID = nil
    }

    private func nextFrame() {
        activeFrameIndex = min(frames.count - 1, activeFrameIndex + 1)
        selectedItemID = nil
    }

    private func rotateClockwise() {
        data = data.rotatingClockwise()
        selectedItemID = nil
    }

    private func deleteSelected() {
        guard let selectedItemID else { return }
        removeItemEverywhere(id: selectedItemID)
        self.selectedItemID = nil
    }

    private func resetDiagram() {
        data = .empty
        activeFrameIndex = 0
        selectedItemID = nil
        dragStartByItemID.removeAll()
        pendingArrowID = nil
    }

    private func addPersistentItem(_ item: DiagramItem) {
        updateFrames { frames in
            for index in frames.indices {
                frames[index].items.append(item)
            }
        }
        selectedItemID = item.id
        tool = .select
    }

    private func removeItemEverywhere(id: String) {
        updateFrames { frames in
            for index in frames.indices {
                frames[index].items.removeAll { $0.id == id }
            }
        }
    }

    private func updateCurrentFrameItems(_ transform: ([DiagramItem]) -> [DiagramItem]) {
        updateFrames { frames in
            frames[activeFrameIndex].items = transform(frames[activeFrameIndex].items)
        }
    }

    private func updateItemEverywhere(id: String, transform: (DiagramItem) -> DiagramItem) {
        updateFrames { frames in
            for frameIndex in frames.indices {
                frames[frameIndex].items = frames[frameIndex].items.map { item in
                    item.id == id ? transform(item) : item
                }
            }
        }
    }

    private func updateItemFromCurrentForward(id: String, transform: (DiagramItem) -> DiagramItem) {
        updateFrames { frames in
            for frameIndex in frames.indices where frameIndex >= activeFrameIndex {
                frames[frameIndex].items = frames[frameIndex].items.map { item in
                    item.id == id ? transform(item) : item
                }
            }
        }
    }

    private func moveItem(_ item: DiagramItem, to point: DiagramPoint) {
        switch item {
        case .cone, .cup, .post:
            updateItemEverywhere(id: item.id) { $0.moved(to: point) }
        case .player, .ball:
            updateItemFromCurrentForward(id: item.id) { $0.moved(to: point) }
        case .arrow:
            break
        }
    }

    private func updateSelectedPlayerColor(_ color: DiagramPlayerColor) {
        guard let selectedItemID else { return }
        updateItemEverywhere(id: selectedItemID) { $0.updatingColor(color) }
    }

    private func updateSelectedPlayerLabel(_ label: String) {
        guard let selectedItemID else { return }
        updateCurrentFrameItems { items in
            items.map { item in
                item.id == selectedItemID ? item.updatingLabel(label) : item
            }
        }
    }

    private func updateFrames(_ mutate: (inout [DiagramFrame]) -> Void) {
        var nextFrames = frames
        mutate(&nextFrames)
        data = DiagramData(
            frames: nextFrames,
            fps: data.fps,
            orientation: data.orientation,
            rotationQuarterTurns: data.rotationQuarterTurns
        )
    }
}
