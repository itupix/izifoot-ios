import SwiftUI

struct DiagramPlayerView: View {
    let data: DiagramData
    var minHeight: CGFloat = 300

    @State private var rotationQuarterTurns: Int
    @State private var activeIndex = 0
    @State private var isPlaying = false
    @State private var transitionFromIndex: Int?
    @State private var transitionProgress = 0.0
    @State private var animationTask: Task<Void, Never>?

    init(data: DiagramData, minHeight: CGFloat = 300) {
        self.data = data
        self.minHeight = minHeight
        _rotationQuarterTurns = State(initialValue: data.rotationQuarterTurns)
    }

    private var orientedFrames: [DiagramFrame] {
        data.rotating(toQuarterTurns: rotationQuarterTurns).compressedFrames()
    }

    private var fps: Int {
        max(1, min(8, data.fps))
    }

    private var displayedItems: [DiagramItem] {
        let activeItems = orientedFrames[safe: activeIndex]?.items ?? []
        guard let transitionFromIndex, transitionFromIndex < orientedFrames.count - 1 else {
            return activeItems
        }

        let fromItems = orientedFrames[safe: transitionFromIndex]?.items ?? []
        let toItems = orientedFrames[safe: transitionFromIndex + 1]?.items ?? activeItems
        let fromByID = Dictionary(uniqueKeysWithValues: fromItems.map { ($0.id, $0) })
        let toIDs = Set(toItems.map(\.id))
        var interpolated = toItems.map { item in
            item.interpolated(from: fromByID[item.id], progress: transitionProgress)
        }

        if transitionProgress < 1 {
            for item in fromItems where !toIDs.contains(item.id) {
                interpolated.append(item)
            }
        }
        return interpolated
    }

    private var progressRatio: Double {
        guard orientedFrames.count > 1 else { return 1 }
        let baseIndex = transitionFromIndex ?? activeIndex
        let progress = transitionFromIndex == nil ? 0 : transitionProgress
        return min(1, max(0, (Double(baseIndex) + progress) / Double(orientedFrames.count - 1)))
    }

    var body: some View {
        VStack(spacing: 12) {
            DiagramFieldSurface(
                quarterTurns: rotationQuarterTurns,
                minHeight: minHeight,
                items: displayedItems
            ) { layout in
                ForEach(displayedItems.filter { !$0.isArrow }, id: \.id) { item in
                    DiagramNodeView(item: item, layout: layout, isSelected: false)
                }
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color(uiColor: .systemGray5))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.9), Color.green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * progressRatio)
                    }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                controlButton(systemImage: "backward.end.fill", action: restart, disabled: activeIndex == 0 && !isPlaying)
                controlButton(systemImage: "backward.fill", action: previousStep, disabled: activeIndex == 0)
                controlButton(systemImage: isPlaying ? "pause.fill" : "play.fill", action: togglePlayback, disabled: orientedFrames.count <= 1)
                controlButton(systemImage: "forward.fill", action: nextStep, disabled: activeIndex >= orientedFrames.count - 1)
                Spacer()
                controlButton(systemImage: "rotate.right.fill", action: rotateClockwise, disabled: false)
            }
        }
        .onChange(of: data) { _, nextValue in
            animationTask?.cancel()
            isPlaying = false
            activeIndex = 0
            transitionFromIndex = nil
            transitionProgress = 0
            rotationQuarterTurns = nextValue.rotationQuarterTurns
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(disabled)
    }

    private func restart() {
        animationTask?.cancel()
        isPlaying = false
        transitionFromIndex = nil
        transitionProgress = 0
        activeIndex = 0
    }

    private func previousStep() {
        guard activeIndex > 0 else { return }
        animationTask?.cancel()
        isPlaying = false
        transitionFromIndex = nil
        transitionProgress = 0
        activeIndex = max(0, activeIndex - 1)
    }

    private func nextStep() {
        guard !isPlaying else { return }
        animateToNext(keepPlaying: false)
    }

    private func togglePlayback() {
        guard orientedFrames.count > 1 else { return }
        if isPlaying {
            animationTask?.cancel()
            isPlaying = false
            transitionFromIndex = nil
            transitionProgress = 0
            return
        }

        if activeIndex >= orientedFrames.count - 1 {
            activeIndex = 0
        }
        isPlaying = true
        animateToNext(keepPlaying: true)
    }

    private func rotateClockwise() {
        animationTask?.cancel()
        isPlaying = false
        transitionFromIndex = nil
        transitionProgress = 0
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
    }

    private func animateToNext(keepPlaying: Bool) {
        guard activeIndex < orientedFrames.count - 1 else {
            isPlaying = false
            transitionFromIndex = nil
            transitionProgress = 0
            return
        }

        animationTask?.cancel()
        let fromIndex = activeIndex
        let duration = max(0.22, 1.0 / Double(fps))
        transitionFromIndex = fromIndex
        transitionProgress = 0

        withAnimation(.linear(duration: duration)) {
            transitionProgress = 1
        }

        animationTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let nextIndex = min(fromIndex + 1, orientedFrames.count - 1)
                transitionFromIndex = nil
                transitionProgress = 0
                activeIndex = nextIndex

                guard keepPlaying else {
                    isPlaying = false
                    return
                }

                if nextIndex >= orientedFrames.count - 1 {
                    isPlaying = false
                } else {
                    animateToNext(keepPlaying: true)
                }
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
