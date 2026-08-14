import CoreGraphics
import Foundation
import SwiftUI

struct TacticalGridPoint: Identifiable, Hashable {
    let id: String
    let x: CGFloat
    let y: CGFloat

    var normalizedX: CGFloat { x / 100 }
    var normalizedY: CGFloat { y / 100 }
}

enum TacticalFieldLayout {
    static let pitchAspectRatio: CGFloat = 68.0 / 105.0

    // Uniform 5 x 9 grid across the playable pitch surface, with fixed edge margins.
    private static let gridXs: [CGFloat] = [12, 31, 50, 69, 88]
    private static let gridRows: [CGFloat] = [10, 19, 28, 37, 46, 55, 64, 73, 82]

    private static let canonicalXsByCount: [Int: [CGFloat]] = [
        1: [50],
        2: [31, 69],
        3: [12, 50, 88],
        4: [12, 31, 69, 88],
        5: [12, 31, 50, 69, 88]
    ]

    static let goalkeeper = TacticalGridPoint(id: "gk", x: 50, y: 88)

    static let snapPoints: [TacticalGridPoint] = {
        var points = [goalkeeper]
        for y in gridRows {
            for x in gridXs {
                points.append(TacticalGridPoint(id: pointID(x: x, y: y), x: x, y: y))
            }
        }
        return points
    }()

    private static let legacyPointsByID: [String: TacticalGridPoint] = {
        let legacyPoints: [TacticalGridPoint] = [
            .init(id: "p1", x: 50, y: 90),
            .init(id: "p2", x: 20, y: 82),
            .init(id: "p3", x: 35, y: 82),
            .init(id: "p4", x: 50, y: 82),
            .init(id: "p5", x: 65, y: 82),
            .init(id: "p6", x: 80, y: 82),
            .init(id: "p7", x: 14, y: 72),
            .init(id: "p8", x: 26, y: 72),
            .init(id: "p9", x: 38, y: 72),
            .init(id: "p10", x: 50, y: 72),
            .init(id: "p11", x: 62, y: 72),
            .init(id: "p12", x: 74, y: 72),
            .init(id: "p13", x: 86, y: 72),
            .init(id: "p14", x: 10, y: 60),
            .init(id: "p15", x: 20, y: 60),
            .init(id: "p16", x: 30, y: 60),
            .init(id: "p17", x: 40, y: 60),
            .init(id: "p18", x: 50, y: 60),
            .init(id: "p19", x: 60, y: 60),
            .init(id: "p20", x: 70, y: 60),
            .init(id: "p21", x: 80, y: 60),
            .init(id: "p22", x: 90, y: 60),
            .init(id: "p23", x: 10, y: 48),
            .init(id: "p24", x: 20, y: 48),
            .init(id: "p25", x: 30, y: 48),
            .init(id: "p26", x: 40, y: 48),
            .init(id: "p27", x: 50, y: 48),
            .init(id: "p28", x: 60, y: 48),
            .init(id: "p29", x: 70, y: 48),
            .init(id: "p30", x: 80, y: 48),
            .init(id: "p31", x: 90, y: 48),
            .init(id: "p32", x: 14, y: 36),
            .init(id: "p33", x: 26, y: 36),
            .init(id: "p34", x: 38, y: 36),
            .init(id: "p35", x: 50, y: 36),
            .init(id: "p36", x: 62, y: 36),
            .init(id: "p37", x: 74, y: 36),
            .init(id: "p38", x: 86, y: 36),
            .init(id: "p39", x: 20, y: 24),
            .init(id: "p40", x: 35, y: 24),
            .init(id: "p41", x: 50, y: 24),
            .init(id: "p42", x: 65, y: 24),
            .init(id: "p43", x: 80, y: 24),
            .init(id: "p44", x: 30, y: 14),
            .init(id: "p45", x: 50, y: 14),
            .init(id: "p46", x: 70, y: 14)
        ]
        return Dictionary(uniqueKeysWithValues: legacyPoints.map { ($0.id, $0) })
    }()

    private static let snapPointsByID = Dictionary(uniqueKeysWithValues: snapPoints.map { ($0.id, $0) })

    static func point(by pointID: String) -> TacticalGridPoint? {
        if let point = snapPointsByID[pointID] {
            return point
        }
        let sourcePoint = parsedStoredPoint(pointID) ?? legacyPointsByID[pointID]
        guard let sourcePoint else {
            return nil
        }
        return nearestPoint(to: sourcePoint, candidates: snapPoints)
    }

    static func migratePointIDs(_ pointIDs: [String]) -> [String] {
        guard !pointIDs.isEmpty else { return [] }
        var available = snapPoints

        return pointIDs.map { pointID in
            let source = snapPointsByID[pointID] ?? parsedStoredPoint(pointID) ?? legacyPointsByID[pointID] ?? goalkeeper
            let resolved = nearestPoint(to: source, candidates: available) ?? goalkeeper
            available.removeAll { $0.id == resolved.id }
            return resolved.id
        }
    }

    static func formationPoints(playersOnField: Int, lines: [Int]) -> [TacticalGridPoint] {
        let totalPlayers = max(1, playersOnField)
        guard totalPlayers > 1 else { return [goalkeeper] }

        let outfieldPlayers = max(0, totalPlayers - 1)
        let normalized = normalize(lines: lines, outfieldPlayers: outfieldPlayers)
        let activeLines = normalized.filter { $0 > 0 }
        let resolvedLines = activeLines.isEmpty ? [outfieldPlayers] : activeLines
        let rowYs = lineYs(for: resolvedLines.count)

        var points = [goalkeeper]
        for (lineCount, y) in zip(resolvedLines, rowYs) {
            for x in xPositions(for: lineCount) {
                points.append(TacticalGridPoint(id: pointID(x: x, y: y), x: x, y: y))
            }
        }

        return Array(points.prefix(totalPlayers))
    }

    private static func normalize(lines: [Int], outfieldPlayers: Int) -> [Int] {
        guard outfieldPlayers > 0 else { return [] }
        let sanitized = lines.map { max(0, $0) }
        let total = sanitized.reduce(0, +)

        guard total > 0 else {
            return [outfieldPlayers]
        }

        if total == outfieldPlayers {
            return sanitized
        }

        let scaled = sanitized.map { Double($0) / Double(total) * Double(outfieldPlayers) }
        var next = scaled.map { Int(floor($0)) }
        let center = Double(max(0, sanitized.count - 1)) / 2
        let distributionOrder = sanitized.indices.sorted { lhs, rhs in
            let leftDistance = abs(Double(lhs) - center)
            let rightDistance = abs(Double(rhs) - center)
            if leftDistance == rightDistance {
                return lhs < rhs
            }
            return leftDistance < rightDistance
        }

        var missing = outfieldPlayers - next.reduce(0, +)
        var index = 0
        while missing > 0 && !distributionOrder.isEmpty {
            next[distributionOrder[index % distributionOrder.count]] += 1
            index += 1
            missing -= 1
        }

        return next
    }

    private static func lineYs(for lineCount: Int) -> [CGFloat] {
        switch lineCount {
        case ...0:
            return []
        case 1:
            return [46]
        case 2:
            return [64, 28]
        default:
            return [73, 46, 19]
        }
    }

    private static func xPositions(for count: Int) -> [CGFloat] {
        guard let positions = canonicalXsByCount[max(1, min(count, 5))] else {
            return [50]
        }
        return positions
    }

    private static func pointID(x: CGFloat, y: CGFloat) -> String {
        "r\(Int(y))-x\(Int(x))"
    }

    private static func parsedStoredPoint(_ pointID: String) -> TacticalGridPoint? {
        guard pointID.hasPrefix("r"), pointID.contains("-x") else {
            return nil
        }
        let parts = pointID.split(separator: "-")
        guard parts.count == 2 else { return nil }
        let rawY = parts[0].dropFirst()
        let rawX = parts[1].dropFirst()
        guard let y = Double(rawY), let x = Double(rawX) else { return nil }
        return TacticalGridPoint(id: pointID, x: CGFloat(x), y: CGFloat(y))
    }

    private static func nearestPoint(to target: TacticalGridPoint, candidates: [TacticalGridPoint]) -> TacticalGridPoint? {
        candidates.min { lhs, rhs in
            let leftDistance = hypot(lhs.x - target.x, lhs.y - target.y)
            let rightDistance = hypot(rhs.x - target.x, rhs.y - target.y)
            return leftDistance < rightDistance
        }
    }
}

struct TacticalPitchView<Content: View>: View {
    let cornerRadius: CGFloat
    let maxWidth: CGFloat
    let centerCircleScale: CGFloat
    let content: (CGSize) -> Content

    init(
        cornerRadius: CGFloat = 24,
        maxWidth: CGFloat = 560,
        centerCircleScale: CGFloat = 0.22,
        @ViewBuilder content: @escaping (CGSize) -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.maxWidth = maxWidth
        self.centerCircleScale = centerCircleScale
        self.content = content
    }

    var body: some View {
        Color.clear
            .aspectRatio(TacticalFieldLayout.pitchAspectRatio, contentMode: .fit)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.29, green: 0.58, blue: 0.31), Color(red: 0.36, green: 0.65, blue: 0.39)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        Rectangle()
                            .fill(.white.opacity(0.42))
                            .frame(height: 2)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                        Circle()
                            .stroke(.white.opacity(0.34), lineWidth: 2)
                            .frame(width: min(proxy.size.width, proxy.size.height) * centerCircleScale)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                        content(proxy.size)
                    }
                }
            }
    }
}
