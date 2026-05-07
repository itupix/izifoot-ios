import SwiftUI

enum DiagramEditorTool: String, CaseIterable, Identifiable {
    case select
    case player
    case cone
    case cup
    case ball
    case post
    case arrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Selection"
        case .player: return "Joueur"
        case .cone: return "Cone"
        case .cup: return "Coupelle"
        case .ball: return "Ballon"
        case .post: return "Poteau"
        case .arrow: return "Fleche"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .player: return "person.crop.circle"
        case .cone: return "triangle"
        case .cup: return "circle.dotted"
        case .ball: return "soccerball"
        case .post: return "rectangle.portrait"
        case .arrow: return "arrow.up.right"
        }
    }
}

struct DiagramCanvasLayout {
    let fieldSize: DiagramFieldSize
    let containerSize: CGSize
    let canvasSize: CGSize
    let origin: CGPoint
    let scale: CGFloat

    init(fieldSize: DiagramFieldSize, in containerSize: CGSize) {
        self.fieldSize = fieldSize
        self.containerSize = containerSize

        let widthScale = containerSize.width / max(fieldSize.width, 1)
        let heightScale = containerSize.height / max(fieldSize.height, 1)
        let resolvedScale = max(0.01, min(widthScale, heightScale))
        self.scale = resolvedScale
        self.canvasSize = CGSize(
            width: fieldSize.width * resolvedScale,
            height: fieldSize.height * resolvedScale
        )
        self.origin = CGPoint(
            x: (containerSize.width - canvasSize.width) / 2,
            y: (containerSize.height - canvasSize.height) / 2
        )
    }

    func canvasPoint(from point: DiagramPoint) -> CGPoint {
        CGPoint(
            x: origin.x + point.x * scale,
            y: origin.y + point.y * scale
        )
    }

    func modelPoint(from point: CGPoint) -> DiagramPoint {
        let model = DiagramPoint(
            x: Double((point.x - origin.x) / scale),
            y: Double((point.y - origin.y) / scale)
        )
        return DiagramData.clamp(
            DiagramPoint(
                x: DiagramData.snap(model.x),
                y: DiagramData.snap(model.y)
            ),
            within: fieldSize
        )
    }

    func modelPoint(fromLocal point: CGPoint) -> DiagramPoint {
        let model = DiagramPoint(
            x: Double(point.x / scale),
            y: Double(point.y / scale)
        )
        return DiagramData.clamp(
            DiagramPoint(
                x: DiagramData.snap(model.x),
                y: DiagramData.snap(model.y)
            ),
            within: fieldSize
        )
    }

    func clampCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, point.x), origin.x + canvasSize.width),
            y: min(max(origin.y, point.y), origin.y + canvasSize.height)
        )
    }

    var fieldRect: CGRect {
        CGRect(origin: origin, size: canvasSize)
    }
}

struct DiagramFieldSurface<Overlay: View>: View {
    let quarterTurns: Int
    let minHeight: CGFloat
    let items: [DiagramItem]
    let selectedItemID: String?
    @ViewBuilder var overlay: (DiagramCanvasLayout) -> Overlay

    init(
        quarterTurns: Int,
        minHeight: CGFloat = 300,
        items: [DiagramItem],
        selectedItemID: String? = nil,
        @ViewBuilder overlay: @escaping (DiagramCanvasLayout) -> Overlay
    ) {
        self.quarterTurns = quarterTurns
        self.minHeight = minHeight
        self.items = items
        self.selectedItemID = selectedItemID
        self.overlay = overlay
    }

    var body: some View {
        let fieldSize = DiagramData.fieldSize(forQuarterTurns: quarterTurns)
        let aspectRatio = fieldSize.width / max(fieldSize.height, 1)

        GeometryReader { proxy in
            let layout = DiagramCanvasLayout(fieldSize: fieldSize, in: proxy.size)
            ZStack(alignment: .topLeading) {
                DiagramFieldBackground(layout: layout, quarterTurns: quarterTurns)
                DiagramArrowLayer(items: items, layout: layout, selectedItemID: selectedItemID)
                overlay(layout)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct DiagramFieldBackground: View {
    let layout: DiagramCanvasLayout
    let quarterTurns: Int

    var body: some View {
        Canvas { context, _ in
            let rect = layout.fieldRect
            let innerRect = rect.insetBy(dx: layout.scale * 5, dy: layout.scale * 5)
            let isPortrait = quarterTurns % 2 == 1

            let fieldPath = RoundedRectangle(cornerRadius: 8 * layout.scale, style: .continuous).path(in: innerRect)
            context.fill(fieldPath, with: .color(.white))
            context.stroke(fieldPath, with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), lineWidth: max(1, layout.scale))

            if !isPortrait {
                var midLine = Path()
                midLine.move(to: CGPoint(x: innerRect.midX, y: innerRect.minY))
                midLine.addLine(to: CGPoint(x: innerRect.midX, y: innerRect.maxY))
                context.stroke(midLine, with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), style: StrokeStyle(lineWidth: max(1, layout.scale), dash: [4 * layout.scale, 4 * layout.scale]))

                let penaltyY = layout.canvasPoint(from: DiagramPoint(x: 0, y: layout.fieldSize.height / 2 - 60)).y
                let leftPenalty = CGRect(
                    x: innerRect.minX,
                    y: penaltyY,
                    width: 40 * layout.scale,
                    height: 120 * layout.scale
                )
                let rightPenalty = CGRect(
                    x: innerRect.maxX - 40 * layout.scale,
                    y: penaltyY,
                    width: 40 * layout.scale,
                    height: 120 * layout.scale
                )
                context.stroke(Path(leftPenalty), with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), lineWidth: max(1, layout.scale))
                context.stroke(Path(rightPenalty), with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), lineWidth: max(1, layout.scale))
            } else {
                var midLine = Path()
                midLine.move(to: CGPoint(x: innerRect.minX, y: innerRect.midY))
                midLine.addLine(to: CGPoint(x: innerRect.maxX, y: innerRect.midY))
                context.stroke(midLine, with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), style: StrokeStyle(lineWidth: max(1, layout.scale), dash: [4 * layout.scale, 4 * layout.scale]))

                let penaltyX = layout.canvasPoint(from: DiagramPoint(x: layout.fieldSize.width / 2 - 60, y: 0)).x
                let topPenalty = CGRect(
                    x: penaltyX,
                    y: innerRect.minY,
                    width: 120 * layout.scale,
                    height: 40 * layout.scale
                )
                let bottomPenalty = CGRect(
                    x: penaltyX,
                    y: innerRect.maxY - 40 * layout.scale,
                    width: 120 * layout.scale,
                    height: 40 * layout.scale
                )
                context.stroke(Path(topPenalty), with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), lineWidth: max(1, layout.scale))
                context.stroke(Path(bottomPenalty), with: .color(Color(red: 0.78, green: 0.89, blue: 0.78)), lineWidth: max(1, layout.scale))
            }
        }
        .background(Color(red: 0.97, green: 1.0, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct DiagramArrowLayer: View {
    let items: [DiagramItem]
    let layout: DiagramCanvasLayout
    let selectedItemID: String?

    var body: some View {
        Canvas { context, _ in
            for item in items {
                guard case let .arrow(node) = item else { continue }
                let from = layout.canvasPoint(from: node.from)
                let to = layout.canvasPoint(from: node.to)
                let isSelected = node.id == selectedItemID

                if isSelected {
                    var glow = Path()
                    glow.move(to: from)
                    glow.addLine(to: to)
                    context.stroke(
                        glow,
                        with: .color(Color.cyan.opacity(0.28)),
                        style: StrokeStyle(lineWidth: max(8, layout.scale * 8), lineCap: .round)
                    )
                }

                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(
                    path,
                    with: .color(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : .black),
                    style: StrokeStyle(lineWidth: max(2, layout.scale * 2), lineCap: .round)
                )

                let angle = atan2(to.y - from.y, to.x - from.x)
                let headLength = max(8, layout.scale * 8)
                let left = CGPoint(
                    x: to.x - cos(angle - .pi / 6) * headLength,
                    y: to.y - sin(angle - .pi / 6) * headLength
                )
                let right = CGPoint(
                    x: to.x - cos(angle + .pi / 6) * headLength,
                    y: to.y - sin(angle + .pi / 6) * headLength
                )

                var head = Path()
                head.move(to: to)
                head.addLine(to: left)
                head.addLine(to: right)
                head.closeSubpath()
                context.fill(head, with: .color(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : .black))
            }
        }
        .allowsHitTesting(false)
    }
}

struct DiagramNodeView: View {
    let item: DiagramItem
    let layout: DiagramCanvasLayout
    let isSelected: Bool

    var body: some View {
        guard let point = item.point else { return AnyView(EmptyView()) }
        let canvasPoint = layout.canvasPoint(from: point)
        return AnyView(
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.cyan.opacity(0.28))
                        .frame(width: max(36, layout.scale * 36), height: max(36, layout.scale * 36))
                }
                bodyView
            }
            .position(canvasPoint)
        )
    }

    @ViewBuilder
    private var bodyView: some View {
        switch item {
        case let .player(node):
            ZStack {
                Circle()
                    .fill(diagramFillColor(node.color))
                    .frame(width: max(28, layout.scale * 28), height: max(28, layout.scale * 28))
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : .black, lineWidth: max(1.5, layout.scale * 1.8))
                    )
                Text(node.label)
                    .font(.system(size: max(9, layout.scale * 10), weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: max(22, layout.scale * 22))
            }
        case .cone:
            Triangle()
                .fill(Color.orange)
                .frame(width: max(22, layout.scale * 22), height: max(22, layout.scale * 22))
                .overlay(
                    Triangle()
                        .stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : Color(red: 0.49, green: 0.18, blue: 0.07), lineWidth: max(1.2, layout.scale * 1.5))
                )
        case .cup:
            ZStack {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: max(20, layout.scale * 20), height: max(20, layout.scale * 20))
                    .overlay(Circle().stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : Color(red: 0.63, green: 0.38, blue: 0.03), lineWidth: max(1.1, layout.scale * 1.4)))
                Circle()
                    .fill(Color(red: 1.0, green: 0.98, blue: 0.92))
                    .frame(width: max(8, layout.scale * 8), height: max(8, layout.scale * 8))
                    .overlay(Circle().stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : Color(red: 0.63, green: 0.38, blue: 0.03), lineWidth: max(0.8, layout.scale)))
            }
        case .ball:
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: max(20, layout.scale * 20), height: max(20, layout.scale * 20))
                    .overlay(Circle().stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : .black, lineWidth: max(1.1, layout.scale * 1.4)))
                CrossHair()
                    .stroke(.black, lineWidth: max(1, layout.scale * 1.2))
                    .frame(width: max(10, layout.scale * 10), height: max(10, layout.scale * 10))
            }
        case .post:
            RoundedRectangle(cornerRadius: max(2, layout.scale * 2), style: .continuous)
                .fill(Color(red: 0.58, green: 0.64, blue: 0.72))
                .frame(width: max(8, layout.scale * 8), height: max(32, layout.scale * 32))
                .overlay(
                    RoundedRectangle(cornerRadius: max(2, layout.scale * 2), style: .continuous)
                        .stroke(isSelected ? Color(red: 0.01, green: 0.52, blue: 0.78) : Color(red: 0.2, green: 0.27, blue: 0.33), lineWidth: max(1, layout.scale * 1.3))
                )
        case .arrow:
            EmptyView()
        }
    }
}

func diagramFillColor(_ color: DiagramPlayerColor) -> Color {
    switch color {
    case .blue: return Color(red: 0.23, green: 0.51, blue: 0.96)
    case .red: return Color(red: 0.94, green: 0.27, blue: 0.27)
    case .yellow: return Color(red: 0.92, green: 0.70, blue: 0.03)
    case .green: return Color(red: 0.13, green: 0.77, blue: 0.37)
    case .orange: return Color(red: 0.98, green: 0.45, blue: 0.09)
    }
}

func diagramItemName(_ item: DiagramItem) -> String {
    switch item {
    case .player: return "Joueur"
    case .cone: return "Cone"
    case .cup: return "Coupelle"
    case .ball: return "Ballon"
    case .post: return "Poteau"
    case .arrow: return "Fleche"
    }
}

func diagramHitTest(items: [DiagramItem], point: DiagramPoint, tolerance: Double = 16) -> DiagramItem? {
    for item in items.reversed() {
        if let itemPoint = item.point {
            let distance = hypot(itemPoint.x - point.x, itemPoint.y - point.y)
            if distance <= tolerance {
                return item
            }
            continue
        }

        guard case let .arrow(node) = item else { continue }
        if diagramDistanceToSegment(point: point, from: node.from, to: node.to) <= tolerance {
            return item
        }
    }
    return nil
}

private func diagramDistanceToSegment(point: DiagramPoint, from: DiagramPoint, to: DiagramPoint) -> Double {
    let dx = to.x - from.x
    let dy = to.y - from.y
    guard dx != 0 || dy != 0 else {
        return hypot(point.x - from.x, point.y - from.y)
    }

    let t = max(0, min(1, ((point.x - from.x) * dx + (point.y - from.y) * dy) / (dx * dx + dy * dy)))
    let projectionX = from.x + t * dx
    let projectionY = from.y + t * dy
    return hypot(point.x - projectionX, point.y - projectionY)
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CrossHair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
