import Foundation

enum DiagramPlayerColor: String, Codable, CaseIterable {
    case blue
    case red
    case yellow
    case green
    case orange

    var label: String {
        switch self {
        case .blue: return "Bleu"
        case .red: return "Rouge"
        case .yellow: return "Jaune"
        case .green: return "Vert"
        case .orange: return "Orange"
        }
    }
}

enum DiagramOrientation: String, Codable {
    case landscape
    case portrait
}

struct DiagramFieldSize: Equatable {
    let width: Double
    let height: Double
}

struct DiagramPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct DiagramPlayerNode: Codable, Equatable {
    var id: String
    var x: Double
    var y: Double
    var label: String
    var color: DiagramPlayerColor
}

struct DiagramFieldNode: Codable, Equatable {
    var id: String
    var x: Double
    var y: Double
}

struct DiagramArrowNode: Codable, Equatable {
    var id: String
    var from: DiagramPoint
    var to: DiagramPoint
}

enum DiagramItem: Codable, Identifiable, Equatable {
    case player(DiagramPlayerNode)
    case cone(DiagramFieldNode)
    case cup(DiagramFieldNode)
    case ball(DiagramFieldNode)
    case post(DiagramFieldNode)
    case arrow(DiagramArrowNode)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case x
        case y
        case label
        case color
        case from
        case to
        case side
    }

    var id: String {
        switch self {
        case let .player(node): return node.id
        case let .cone(node): return node.id
        case let .cup(node): return node.id
        case let .ball(node): return node.id
        case let .post(node): return node.id
        case let .arrow(node): return node.id
        }
    }

    var isArrow: Bool {
        if case .arrow = self { return true }
        return false
    }

    var point: DiagramPoint? {
        get {
            switch self {
            case let .player(node):
                return DiagramPoint(x: node.x, y: node.y)
            case let .cone(node):
                return DiagramPoint(x: node.x, y: node.y)
            case let .cup(node):
                return DiagramPoint(x: node.x, y: node.y)
            case let .ball(node):
                return DiagramPoint(x: node.x, y: node.y)
            case let .post(node):
                return DiagramPoint(x: node.x, y: node.y)
            case .arrow:
                return nil
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            case var .player(node):
                node.x = newValue.x
                node.y = newValue.y
                self = .player(node)
            case var .cone(node):
                node.x = newValue.x
                node.y = newValue.y
                self = .cone(node)
            case var .cup(node):
                node.x = newValue.x
                node.y = newValue.y
                self = .cup(node)
            case var .ball(node):
                node.x = newValue.x
                node.y = newValue.y
                self = .ball(node)
            case var .post(node):
                node.x = newValue.x
                node.y = newValue.y
                self = .post(node)
            case .arrow:
                break
            }
        }
    }

    var playerColor: DiagramPlayerColor? {
        get {
            guard case let .player(node) = self else { return nil }
            return node.color
        }
        set {
            guard case var .player(node) = self, let newValue else { return }
            node.color = newValue
            self = .player(node)
        }
    }

    var playerLabel: String? {
        get {
            guard case let .player(node) = self else { return nil }
            return node.label
        }
        set {
            guard case var .player(node) = self else { return }
            node.label = newValue ?? ""
            self = .player(node)
        }
    }

    var arrowNode: DiagramArrowNode? {
        guard case let .arrow(node) = self else { return nil }
        return node
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = (try? container.decode(String.self, forKey: .id)) ?? Self.makeID()

        switch type {
        case "player":
            let rawColor = (try? container.decode(String.self, forKey: .color))
                ?? ((try? container.decode(String.self, forKey: .side)) == "away" ? "red" : "blue")
            let color = DiagramPlayerColor(rawValue: rawColor) ?? .blue
            self = .player(
                DiagramPlayerNode(
                    id: id,
                    x: Self.decodeDouble(container, forKey: .x),
                    y: Self.decodeDouble(container, forKey: .y),
                    label: (try? container.decode(String.self, forKey: .label)) ?? "",
                    color: color
                )
            )
        case "cone":
            self = .cone(DiagramFieldNode(id: id, x: Self.decodeDouble(container, forKey: .x), y: Self.decodeDouble(container, forKey: .y)))
        case "cup":
            self = .cup(DiagramFieldNode(id: id, x: Self.decodeDouble(container, forKey: .x), y: Self.decodeDouble(container, forKey: .y)))
        case "ball":
            self = .ball(DiagramFieldNode(id: id, x: Self.decodeDouble(container, forKey: .x), y: Self.decodeDouble(container, forKey: .y)))
        case "post":
            self = .post(DiagramFieldNode(id: id, x: Self.decodeDouble(container, forKey: .x), y: Self.decodeDouble(container, forKey: .y)))
        case "arrow":
            self = .arrow(
                DiagramArrowNode(
                    id: id,
                    from: (try? container.decode(DiagramPoint.self, forKey: .from)) ?? DiagramPoint(x: 0, y: 0),
                    to: (try? container.decode(DiagramPoint.self, forKey: .to)) ?? DiagramPoint(x: 0, y: 0)
                )
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown diagram item type \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .player(node):
            try container.encode("player", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.x, forKey: .x)
            try container.encode(node.y, forKey: .y)
            try container.encode(node.label, forKey: .label)
            try container.encode(node.color.rawValue, forKey: .color)
        case let .cone(node):
            try container.encode("cone", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.x, forKey: .x)
            try container.encode(node.y, forKey: .y)
        case let .cup(node):
            try container.encode("cup", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.x, forKey: .x)
            try container.encode(node.y, forKey: .y)
        case let .ball(node):
            try container.encode("ball", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.x, forKey: .x)
            try container.encode(node.y, forKey: .y)
        case let .post(node):
            try container.encode("post", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.x, forKey: .x)
            try container.encode(node.y, forKey: .y)
        case let .arrow(node):
            try container.encode("arrow", forKey: .type)
            try container.encode(node.id, forKey: .id)
            try container.encode(node.from, forKey: .from)
            try container.encode(node.to, forKey: .to)
        }
    }

    func moved(to point: DiagramPoint) -> DiagramItem {
        switch self {
        case var .player(node):
            node.x = point.x
            node.y = point.y
            return .player(node)
        case var .cone(node):
            node.x = point.x
            node.y = point.y
            return .cone(node)
        case var .cup(node):
            node.x = point.x
            node.y = point.y
            return .cup(node)
        case var .ball(node):
            node.x = point.x
            node.y = point.y
            return .ball(node)
        case var .post(node):
            node.x = point.x
            node.y = point.y
            return .post(node)
        case .arrow:
            return self
        }
    }

    func updatingColor(_ color: DiagramPlayerColor) -> DiagramItem {
        guard case var .player(node) = self else { return self }
        node.color = color
        return .player(node)
    }

    func updatingLabel(_ label: String) -> DiagramItem {
        guard case var .player(node) = self else { return self }
        node.label = label
        return .player(node)
    }

    func rotatedClockwise(fromQuarterTurns: Int) -> DiagramItem {
        switch self {
        case let .arrow(node):
            return .arrow(
                DiagramArrowNode(
                    id: node.id,
                    from: DiagramData.mapPointClockwise(node.from, fromQuarterTurns: fromQuarterTurns),
                    to: DiagramData.mapPointClockwise(node.to, fromQuarterTurns: fromQuarterTurns)
                )
            )
        default:
            guard let point else { return self }
            return moved(to: DiagramData.mapPointClockwise(point, fromQuarterTurns: fromQuarterTurns))
        }
    }

    func interpolated(from fromItem: DiagramItem?, progress: Double) -> DiagramItem {
        guard let fromItem else { return self }
        switch (fromItem, self) {
        case let (.player(fromNode), .player(toNode)):
            return .player(
                DiagramPlayerNode(
                    id: toNode.id,
                    x: DiagramData.lerp(fromNode.x, toNode.x, progress),
                    y: DiagramData.lerp(fromNode.y, toNode.y, progress),
                    label: toNode.label,
                    color: toNode.color
                )
            )
        case let (.cone(fromNode), .cone(toNode)):
            return .cone(DiagramFieldNode(id: toNode.id, x: DiagramData.lerp(fromNode.x, toNode.x, progress), y: DiagramData.lerp(fromNode.y, toNode.y, progress)))
        case let (.cup(fromNode), .cup(toNode)):
            return .cup(DiagramFieldNode(id: toNode.id, x: DiagramData.lerp(fromNode.x, toNode.x, progress), y: DiagramData.lerp(fromNode.y, toNode.y, progress)))
        case let (.ball(fromNode), .ball(toNode)):
            return .ball(DiagramFieldNode(id: toNode.id, x: DiagramData.lerp(fromNode.x, toNode.x, progress), y: DiagramData.lerp(fromNode.y, toNode.y, progress)))
        case let (.post(fromNode), .post(toNode)):
            return .post(DiagramFieldNode(id: toNode.id, x: DiagramData.lerp(fromNode.x, toNode.x, progress), y: DiagramData.lerp(fromNode.y, toNode.y, progress)))
        case let (.arrow(fromNode), .arrow(toNode)):
            return .arrow(
                DiagramArrowNode(
                    id: toNode.id,
                    from: DiagramPoint(
                        x: DiagramData.lerp(fromNode.from.x, toNode.from.x, progress),
                        y: DiagramData.lerp(fromNode.from.y, toNode.from.y, progress)
                    ),
                    to: DiagramPoint(
                        x: DiagramData.lerp(fromNode.to.x, toNode.to.x, progress),
                        y: DiagramData.lerp(fromNode.to.y, toNode.to.y, progress)
                    )
                )
            )
        default:
            return self
        }
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        return 0
    }

    static func makeID() -> String {
        UUID().uuidString.lowercased()
    }
}

struct DiagramFrame: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var items: [DiagramItem]
}

struct DiagramData: Codable, Equatable {
    static let maxSteps = 10
    static let gridSize = 20.0
    static let fieldMargin = 5.0
    static let landscapeFieldSize = DiagramFieldSize(width: 600, height: 380)
    static let portraitFieldSize = DiagramFieldSize(width: 380, height: 600)

    var frames: [DiagramFrame]
    var fps: Int
    var orientation: DiagramOrientation
    var rotationQuarterTurns: Int

    private enum CodingKeys: String, CodingKey {
        case frames
        case items
        case fps
        case orientation
        case rotationQuarterTurns
    }

    init(frames: [DiagramFrame], fps: Int = 2, orientation: DiagramOrientation = .landscape, rotationQuarterTurns: Int = 0) {
        let normalizedQuarterTurns = Self.normalizeRotationQuarterTurns(rotationQuarterTurns, fallbackOrientation: orientation)
        self.frames = Self.ensureTenFrames(frames)
        self.fps = max(1, min(8, fps))
        self.orientation = Self.orientation(forQuarterTurns: normalizedQuarterTurns)
        self.rotationQuarterTurns = normalizedQuarterTurns
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawString = try? singleValue.decode(String.self) {
            self = Self.fromJSONString(rawString)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFPS = Self.decodeFlexibleInt(container, forKey: .fps) ?? 2
        let decodedOrientation = (try? container.decode(DiagramOrientation.self, forKey: .orientation)) ?? .landscape
        let decodedQuarterTurns = Self.normalizeRotationQuarterTurns(
            Self.decodeFlexibleInt(container, forKey: .rotationQuarterTurns),
            fallbackOrientation: decodedOrientation
        )

        if let frames = try? container.decode([DiagramFrame].self, forKey: .frames), !frames.isEmpty {
            self.init(frames: frames, fps: decodedFPS, orientation: decodedOrientation, rotationQuarterTurns: decodedQuarterTurns)
            return
        }

        if let items = try? container.decode([DiagramItem].self, forKey: .items) {
            self.init(
                frames: [Self.makeFrame(name: "Etape 1", items: items)],
                fps: decodedFPS,
                orientation: decodedOrientation,
                rotationQuarterTurns: decodedQuarterTurns
            )
            return
        }

        self = Self.empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frames, forKey: .frames)
        try container.encode(fps, forKey: .fps)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(rotationQuarterTurns, forKey: .rotationQuarterTurns)
    }

    static var empty: DiagramData {
        DiagramData(frames: [makeFrame(name: "Etape 1", items: [])], fps: 2, orientation: .landscape, rotationQuarterTurns: 0)
    }

    static func fromJSONString(_ rawValue: String) -> DiagramData {
        guard let data = rawValue.data(using: .utf8) else { return .empty }
        return (try? JSONDecoder().decode(DiagramData.self, from: data)) ?? .empty
    }

    static func makeFrame(name: String, items: [DiagramItem] = []) -> DiagramFrame {
        DiagramFrame(id: DiagramItem.makeID(), name: name, items: items)
    }

    var hasContent: Bool {
        frames.contains { !$0.items.isEmpty }
    }

    var fieldSize: DiagramFieldSize {
        Self.fieldSize(forQuarterTurns: rotationQuarterTurns)
    }

    func compressedFrames() -> [DiagramFrame] {
        let filtered = frames.enumerated().compactMap { index, frame in
            guard index > 0 else { return frame }
            return frame.items == frames[index - 1].items ? nil : frame
        }
        return filtered.isEmpty ? [frames.first ?? Self.makeFrame(name: "Etape 1")] : filtered
    }

    func rotatingClockwise() -> DiagramData {
        let currentTurns = Self.normalizeRotationQuarterTurns(rotationQuarterTurns, fallbackOrientation: orientation)
        let nextTurns = Self.normalizeRotationQuarterTurns(currentTurns + 1, fallbackOrientation: orientation)
        return DiagramData(
            frames: frames.map { frame in
                DiagramFrame(
                    id: frame.id,
                    name: frame.name,
                    items: frame.items.map { $0.rotatedClockwise(fromQuarterTurns: currentTurns) }
                )
            },
            fps: fps,
            orientation: Self.orientation(forQuarterTurns: nextTurns),
            rotationQuarterTurns: nextTurns
        )
    }

    func rotating(toQuarterTurns targetQuarterTurns: Int) -> DiagramData {
        let normalizedTarget = Self.normalizeRotationQuarterTurns(targetQuarterTurns, fallbackOrientation: orientation)
        let currentTurns = Self.normalizeRotationQuarterTurns(rotationQuarterTurns, fallbackOrientation: orientation)
        var next = DiagramData(frames: frames, fps: fps, orientation: orientation, rotationQuarterTurns: currentTurns)
        let steps = (normalizedTarget - currentTurns + 4) % 4
        for _ in 0 ..< steps {
            next = next.rotatingClockwise()
        }
        return next
    }

    func materialSummary() -> [String] {
        var maxCone = 0
        var maxCup = 0
        var maxBall = 0
        var maxPost = 0
        var maxPlayers = 0
        var colors = Set<DiagramPlayerColor>()

        for frame in frames {
            var cone = 0
            var cup = 0
            var ball = 0
            var post = 0
            var players = 0

            for item in frame.items {
                switch item {
                case let .player(node):
                    players += 1
                    colors.insert(node.color)
                case .cone:
                    cone += 1
                case .cup:
                    cup += 1
                case .ball:
                    ball += 1
                case .post:
                    post += 1
                case .arrow:
                    break
                }
            }

            maxCone = max(maxCone, cone)
            maxCup = max(maxCup, cup)
            maxBall = max(maxBall, ball)
            maxPost = max(maxPost, post)
            maxPlayers = max(maxPlayers, players)
        }

        var lines: [String] = []
        if maxCup > 0 { lines.append("\(maxCup) coupelle\(maxCup > 1 ? "s" : "")") }
        if maxCone > 0 { lines.append("\(maxCone) cone\(maxCone > 1 ? "s" : "")") }
        if maxBall > 0 { lines.append("\(maxBall) ballon\(maxBall > 1 ? "s" : "")") }
        if maxPost > 0 { lines.append("\(maxPost) poteau\(maxPost > 1 ? "x" : "")") }
        if colors.count >= 2 && maxPlayers > 0 { lines.append("chasubles") }
        return lines
    }

    static func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }

    static func orientation(forQuarterTurns quarterTurns: Int) -> DiagramOrientation {
        normalizeRotationQuarterTurns(quarterTurns, fallbackOrientation: .landscape) % 2 == 1 ? .portrait : .landscape
    }

    static func fieldSize(forQuarterTurns quarterTurns: Int) -> DiagramFieldSize {
        orientation(forQuarterTurns: quarterTurns) == .portrait ? portraitFieldSize : landscapeFieldSize
    }

    static func normalizeRotationQuarterTurns(_ input: Int?, fallbackOrientation: DiagramOrientation) -> Int {
        guard let input else {
            return fallbackOrientation == .portrait ? 1 : 0
        }
        return ((input % 4) + 4) % 4
    }

    static func snap(_ value: Double) -> Double {
        (value / gridSize).rounded() * gridSize
    }

    static func clamp(_ point: DiagramPoint, within size: DiagramFieldSize) -> DiagramPoint {
        DiagramPoint(
            x: min(max(fieldMargin, point.x), size.width - fieldMargin),
            y: min(max(fieldMargin, point.y), size.height - fieldMargin)
        )
    }

    static func mapPointClockwise(_ point: DiagramPoint, fromQuarterTurns: Int) -> DiagramPoint {
        let fromSize = fieldSize(forQuarterTurns: fromQuarterTurns)
        let toSize = fieldSize(forQuarterTurns: fromQuarterTurns + 1)
        let fromInnerWidth = fromSize.width - fieldMargin * 2
        let fromInnerHeight = fromSize.height - fieldMargin * 2
        let toInnerWidth = toSize.width - fieldMargin * 2
        let toInnerHeight = toSize.height - fieldMargin * 2

        let normalizedX = min(1, max(0, (point.x - fieldMargin) / fromInnerWidth))
        let normalizedY = min(1, max(0, (point.y - fieldMargin) / fromInnerHeight))
        return DiagramPoint(
            x: fieldMargin + normalizedY * toInnerWidth,
            y: fieldMargin + (1 - normalizedX) * toInnerHeight
        )
    }

    private static func ensureTenFrames(_ frames: [DiagramFrame]) -> [DiagramFrame] {
        var normalized = Array(frames.prefix(maxSteps)).enumerated().map { index, frame in
            DiagramFrame(
                id: frame.id,
                name: "Etape \(index + 1)",
                items: frame.items
            )
        }

        while normalized.count < maxSteps {
            normalized.append(makeFrame(name: "Etape \(normalized.count + 1)"))
        }
        return normalized
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value.rounded()) }
        return nil
    }
}

struct Diagram: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let data: DiagramData
    let drillId: String?
    let trainingDrillId: String?
    let createdAt: String?
    let updatedAt: String?
}
