import Charts
import SwiftUI

// MARK: What the engine sends

struct LabPointer: Decodable, Sendable, Hashable {
    let name: String
    let index: Int?
    let node: String?
}

struct LabTreeNode: Decodable, Sendable, Hashable {
    let id: String
    let label: String
    let parent: String?
    let side: String?
    let role: String?
    let note: String?
}

struct LabChainNode: Decodable, Sendable, Hashable {
    let id: String
    let label: String
    let next: String?
    let role: String?
}

struct LabSeries: Decodable, Sendable, Hashable {
    let name: String
    let points: [[Double]]
}

struct LabPanel: Decodable, Sendable, Hashable {
    let type: String
    let title: String?
    let caption: String?
    // array, stack
    let cells: [String]?
    let roles: [String]?
    let pointers: [LabPointer]?
    let window: [Int]?
    let offset: Int?
    let horizontal: Bool?
    let ends: [String]?
    // tree, chain
    let binary: Bool?
    let nodes: [LabTreeNode]?
    let links: [LabChainNode]?
    // grid
    let grid: [[String]]?
    let gridRoles: [[String]]?
    let heat: [[Double]]?
    // scatter
    let points: [[Double]]?
    let centers: [[Double]]?
    let lines: [[Double]]?
    let trails: [[[Double]]]?
    let bounds: [Double]?
    let field: [[Double]]?
    let path: [[Double]]?
    // plot
    let series: [LabSeries]?
    // vars
    let pairs: [[String]]?
}

struct LabFrame: Decodable, Sendable {
    let note: String
    let line: Int?
    let code: String
    let panels: [LabPanel]
    let context: String
}

struct LabCheck: Decodable, Sendable, Identifiable {
    let name: String
    let ok: Bool
    let message: String
    var id: String { name }
}

struct LabFrames: Decodable, Sendable {
    let lab: String
    let variant: String
    let frames: [LabFrame]
    let checks: [LabCheck]
    let correct: Bool
    let message: String
    let truncated: Bool
}

struct LabScaleSeries: Decodable, Sendable, Identifiable {
    let name: String
    let points: [[Double]]
    let ok: Bool
    let message: String
    var id: String { name }
}

struct LabScaleResult: Decodable, Sendable {
    let lab: String
    let variant: String
    let what: String
    let x: String
    let runs: Int
    let series: [LabScaleSeries]
    let takeaway: String
    let stopped: String
    let footnote: String
}

// MARK: Colours

enum LabRole {
    static func fill(_ role: String?) -> Color {
        switch role ?? "" {
        case "now": AppTheme.run
        case "done": AppTheme.mint.opacity(0.85)
        case "seen": AppTheme.selection
        case "focus": AppTheme.violet.opacity(0.22)
        case "bad": AppTheme.coral.opacity(0.85)
        case "dim": AppTheme.raised.opacity(0.35)
        case "wall": AppTheme.secondary.opacity(0.75)
        case "land": AppTheme.amber.opacity(0.35)
        default: AppTheme.raised
        }
    }

    static func ink(_ role: String?) -> Color {
        switch role ?? "" {
        case "now": AppTheme.onRun
        case "done", "bad": AppTheme.background
        case "seen": AppTheme.selectionInk
        case "focus": AppTheme.violet
        case "dim": AppTheme.muted.opacity(0.55)
        default: AppTheme.primary
        }
    }

    static func group(_ index: Int) -> Color {
        [AppTheme.blue, AppTheme.coral, AppTheme.mint, AppTheme.violet, AppTheme.amber][abs(index) % 5]
    }
}

// MARK: Panels

struct LabPanelView: View {
    let panel: LabPanel
    /// Arrays in one frame share a cell width so a pattern lines up under its text.
    var columns: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = panel.title, !title.isEmpty {
                Text(title.uppercased()).sectionLabel()
            }
            content
            if let caption = panel.caption, !caption.isEmpty {
                Text(caption).font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch panel.type {
        case "array": LabArrayView(panel: panel, columns: max(columns, (panel.cells?.count ?? 0) + (panel.offset ?? 0)))
        case "tree": LabTreeView(nodes: panel.nodes ?? [], binary: panel.binary ?? false)
        case "grid": LabGridView(panel: panel)
        case "stack": LabStackView(panel: panel)
        case "chain": LabChainView(nodes: panel.links ?? [], pointers: panel.pointers ?? [])
        case "scatter": LabScatterView(panel: panel)
        case "plot": LabPlotView(series: panel.series ?? [])
        case "vars": LabVarsView(pairs: panel.pairs ?? [])
        default: EmptyView()
        }
    }
}

/// Boxes in a row with pointer names underneath.
private struct LabArrayView: View {
    let panel: LabPanel
    let columns: Int

    var body: some View {
        let cells = panel.cells ?? []
        let pointers = panel.pointers ?? []
        let rows = pointers.isEmpty ? 0 : Dictionary(grouping: pointers, by: { $0.index ?? -2 }).values.map(\.count).max() ?? 0
        Canvas { context, size in
            let count = max(1, columns)
            let width = min(40, size.width / CGFloat(count))
            let left = (size.width - width * CGFloat(count)) / 2 + width * CGFloat(panel.offset ?? 0)
            let height: CGFloat = min(34, width * 1.15 + 6)
            if let window = panel.window, window.count == 2, window[0] <= window[1] {
                let rect = CGRect(x: left + width * CGFloat(window[0]) - 1.5, y: 0, width: width * CGFloat(window[1] - window[0] + 1) + 3, height: height + 3)
                context.stroke(Path(roundedRect: rect, cornerRadius: 7), with: .color(AppTheme.mint), lineWidth: 2)
            }
            for (index, value) in cells.enumerated() {
                let role = panel.roles?[safe: index] ?? ""
                let rect = CGRect(x: left + width * CGFloat(index) + 1.5, y: 1.5, width: width - 3, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(LabRole.fill(role)))
                let font = Font.system(size: value.count > 3 ? 10 : width < 24 ? 11 : 14, weight: .semibold, design: .monospaced)
                context.draw(Text(value).font(font).foregroundStyle(LabRole.ink(role)), at: CGPoint(x: rect.midX, y: rect.midY))
                if (panel.offset ?? 0) == 0, width >= 16 {
                    context.draw(Text("\(index)").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(AppTheme.muted), at: CGPoint(x: rect.midX, y: height + 9))
                }
            }
            var stacked: [Int: Int] = [:]
            for pointer in pointers {
                guard let index = pointer.index else { continue }
                let level = stacked[index, default: 0]
                stacked[index] = level + 1
                let x = left + width * (CGFloat(index) + 0.5)
                let y = height + 24 + CGFloat(level) * 13
                context.draw(Text("▲ " + pointer.name).font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundStyle(pointer.name.hasPrefix("mid") || pointer.name == "m" ? AppTheme.amber : AppTheme.blue), at: CGPoint(x: x, y: y))
            }
        }
        .frame(height: 34 + 16 + CGFloat(rows) * 13 + (rows > 0 ? 8 : 0))
        .accessibilityLabel(cells.joined(separator: ", "))
    }
}

/// A tree laid out leaf by leaf; binary trees keep left and right apart by in-order position.
private struct LabTreeView: View {
    let nodes: [LabTreeNode]
    let binary: Bool

    var body: some View {
        let layout = Self.layout(nodes, binary: binary)
        let longest = nodes.map(\.label.count).max() ?? 1
        let leafWidth = max(binary ? 30 : 26, CGFloat(longest) * 6.4 + 14)
        let depth = (layout.values.map(\.y).max() ?? 0) + 1
        let notes = nodes.contains { $0.note != nil }
        let rowHeight: CGFloat = notes ? 54 : 44
        GeometryReader { proxy in
            let columns = max(1, (layout.values.map(\.x).max() ?? 0) + 1)
            let width = max(proxy.size.width, columns * leafWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { context, size in
                    let step = size.width / columns
                    func point(_ id: String) -> CGPoint? {
                        guard let spot = layout[id] else { return nil }
                        return CGPoint(x: (spot.x + 0.5) * step, y: 18 + spot.y * rowHeight)
                    }
                    for node in nodes {
                        guard let parent = node.parent, let from = point(parent), let to = point(node.id) else { continue }
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)
                        context.stroke(path, with: .color(AppTheme.border), lineWidth: 1.5)
                    }
                    for node in nodes {
                        guard let center = point(node.id) else { continue }
                        let text = context.resolve(Text(node.label).font(.system(size: 11.5, weight: .bold, design: .monospaced)).foregroundStyle(LabRole.ink(node.role)))
                        let measured = text.measure(in: CGSize(width: 300, height: 40))
                        let box = CGSize(width: max(26, measured.width + 12), height: 24)
                        let rect = CGRect(x: center.x - box.width / 2, y: center.y - box.height / 2, width: box.width, height: box.height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(LabRole.fill(node.role)))
                        if (node.role ?? "").isEmpty {
                            context.stroke(Path(roundedRect: rect, cornerRadius: 12), with: .color(AppTheme.border), lineWidth: 1)
                        }
                        context.draw(text, at: center)
                        if let note = node.note {
                            context.draw(Text(note).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(AppTheme.mint), at: CGPoint(x: center.x, y: center.y + 20))
                        }
                    }
                }
                .frame(width: width, height: depth * rowHeight + 6)
            }
        }
        .frame(height: depth * rowHeight + 6)
        .accessibilityLabel("A tree of \(nodes.count) nodes")
    }

    struct Spot { var x: CGFloat; var y: CGFloat }

    static func layout(_ nodes: [LabTreeNode], binary: Bool) -> [String: Spot] {
        var children: [String: [LabTreeNode]] = [:]
        let ids = Set(nodes.map(\.id))
        var roots: [LabTreeNode] = []
        for node in nodes {
            if let parent = node.parent, ids.contains(parent) {
                children[parent, default: []].append(node)
            } else {
                roots.append(node)
            }
        }
        var spots: [String: Spot] = [:]
        var next: CGFloat = 0
        var visiting = Set<String>()
        if binary {
            func walk(_ node: LabTreeNode, _ depth: CGFloat) {
                guard visiting.insert(node.id).inserted else { return }
                let kids = children[node.id] ?? []
                if let left = kids.first(where: { $0.side == "L" }) { walk(left, depth + 1) }
                spots[node.id] = Spot(x: next, y: depth)
                next += 1
                if let right = kids.first(where: { $0.side == "R" }) { walk(right, depth + 1) }
            }
            roots.forEach { walk($0, 0) }
        } else {
            func walk(_ node: LabTreeNode, _ depth: CGFloat) -> CGFloat {
                guard visiting.insert(node.id).inserted else { return next }
                let kids = children[node.id] ?? []
                if kids.isEmpty {
                    spots[node.id] = Spot(x: next, y: depth)
                    next += 1
                } else {
                    let xs = kids.map { walk($0, depth + 1) }
                    spots[node.id] = Spot(x: ((xs.first ?? 0) + (xs.last ?? 0)) / 2, y: depth)
                }
                return spots[node.id]?.x ?? 0
            }
            roots.forEach { _ = walk($0, 0) }
        }
        return spots
    }
}

private struct LabGridView: View {
    let panel: LabPanel

    var body: some View {
        let rows = panel.grid ?? []
        let columns = rows.map(\.count).max() ?? 0
        Canvas { context, size in
            let side = min(size.width / CGFloat(max(1, columns)), 34)
            let left = (size.width - side * CGFloat(columns)) / 2
            for (r, row) in rows.enumerated() {
                for (c, value) in row.enumerated() {
                    let role = panel.gridRoles?[safe: r]?[safe: c] ?? ""
                    let rect = CGRect(x: left + CGFloat(c) * side + 1, y: CGFloat(r) * side + 1, width: side - 2, height: side - 2)
                    let shape = Path(roundedRect: rect, cornerRadius: min(6, side / 5))
                    if role == "focus" {
                        context.fill(shape, with: .color(heatColor(r, c)))
                        context.stroke(shape, with: .color(AppTheme.violet), lineWidth: 2)
                    } else if role.isEmpty {
                        context.fill(shape, with: .color(heatColor(r, c)))
                    } else {
                        context.fill(shape, with: .color(LabRole.fill(role)))
                    }
                    if !value.isEmpty {
                        let ink = role.isEmpty || role == "focus" ? AppTheme.primary : LabRole.ink(role)
                        context.draw(Text(value).font(.system(size: side * 0.5, weight: .bold)).foregroundStyle(ink), at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
            }
        }
        .aspectRatio(CGFloat(max(1, columns)) / CGFloat(max(1, rows.count)), contentMode: .fit)
        .frame(maxHeight: CGFloat(rows.count) * 34)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("A grid of \(rows.count) rows")
    }

    private func heatColor(_ r: Int, _ c: Int) -> Color {
        if let value = panel.heat?[safe: r]?[safe: c] {
            return AppTheme.blue.opacity(0.08 + 0.5 * value)
        }
        return AppTheme.raised
    }
}

private struct LabStackView: View {
    let panel: LabPanel

    var body: some View {
        let cells = panel.cells ?? []
        let ends = panel.ends ?? []
        if panel.horizontal ?? false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if let first = ends.first { endLabel(first) }
                    if cells.isEmpty { Text("empty").font(.system(size: 13)).foregroundStyle(AppTheme.muted).frame(minHeight: 34) }
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, value in
                        chip(value, role: panel.roles?[safe: index])
                    }
                    if ends.count > 1 { endLabel(ends[1]) }
                }
            }
        } else {
            VStack(spacing: 4) {
                if ends.count > 1 { endLabel(ends[1]) }
                if cells.isEmpty { Text("empty").font(.system(size: 13)).foregroundStyle(AppTheme.muted).frame(minHeight: 30) }
                ForEach(Array(cells.enumerated().reversed()), id: \.offset) { index, value in
                    chip(value, role: panel.roles?[safe: index]).frame(minWidth: 120)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func chip(_ value: String, role: String?) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(LabRole.ink(role))
            .padding(.horizontal, 10)
            .frame(minWidth: 34, minHeight: 32)
            .background(LabRole.fill(role), in: RoundedRectangle(cornerRadius: 8))
    }

    private func endLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.muted)
    }
}

/// Linked nodes in the order they were made, with each next arrow drawn where it points now.
private struct LabChainView: View {
    let nodes: [LabChainNode]
    let pointers: [LabPointer]

    var body: some View {
        let empty = pointers.filter { $0.node == nil }.map(\.name)
        let named = Dictionary(grouping: pointers.filter { $0.node != nil }, by: { $0.node! })
        let rows = named.values.map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let count = max(1, nodes.count)
                let slot = min(70, size.width / CGFloat(count))
                let box = CGSize(width: min(40, slot * 0.6), height: 30)
                let left = (size.width - slot * CGFloat(count)) / 2
                let top: CGFloat = 26
                var centers: [String: CGPoint] = [:]
                for (index, node) in nodes.enumerated() {
                    centers[node.id] = CGPoint(x: left + slot * (CGFloat(index) + 0.5), y: top + box.height / 2)
                }
                for (index, node) in nodes.enumerated() {
                    guard let from = centers[node.id] else { continue }
                    if let next = node.next, let to = centers[next] {
                        let ahead = nodes.firstIndex(where: { $0.id == next }).map { $0 - index } ?? 0
                        var path = Path()
                        let tip: CGPoint
                        let angle: CGFloat
                        if ahead == 1 {
                            path.move(to: CGPoint(x: from.x + box.width / 2, y: from.y))
                            tip = CGPoint(x: to.x - box.width / 2 - 1, y: to.y)
                            path.addLine(to: tip)
                            angle = 0
                        } else {
                            let below = ahead < 0
                            let start = CGPoint(x: from.x, y: from.y + (below ? box.height / 2 : -box.height / 2))
                            tip = CGPoint(x: to.x, y: to.y + (below ? box.height / 2 + 1 : -box.height / 2 - 1))
                            let lift = min(24, 10 + CGFloat(abs(ahead)) * 5)
                            path.move(to: start)
                            path.addCurve(to: tip, control1: CGPoint(x: start.x, y: start.y + (below ? lift : -lift)), control2: CGPoint(x: tip.x, y: tip.y + (below ? lift : -lift)))
                            angle = below ? -.pi / 2 : .pi / 2
                        }
                        context.stroke(path, with: .color(AppTheme.blue), lineWidth: 2)
                        var head = Path()
                        head.move(to: tip)
                        head.addLine(to: CGPoint(x: tip.x - 7 * cos(angle) + 4 * sin(angle), y: tip.y - 7 * sin(angle) - 4 * cos(angle)))
                        head.addLine(to: CGPoint(x: tip.x - 7 * cos(angle) - 4 * sin(angle), y: tip.y - 7 * sin(angle) + 4 * cos(angle)))
                        head.closeSubpath()
                        context.fill(head, with: .color(AppTheme.blue))
                    } else {
                        context.draw(Text("∅").font(.system(size: 11, weight: .bold)).foregroundStyle(AppTheme.muted), at: CGPoint(x: from.x + box.width / 2 + 7, y: from.y))
                    }
                    let rect = CGRect(x: from.x - box.width / 2, y: from.y - box.height / 2, width: box.width, height: box.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(LabRole.fill(node.role)))
                    context.draw(Text(node.label).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(LabRole.ink(node.role)), at: from)
                    for (level, pointer) in (named[node.id] ?? []).enumerated() {
                        context.draw(Text("▲ " + pointer.name).font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundStyle(pointer.name == "returned" ? AppTheme.mint : AppTheme.amber),
                                     at: CGPoint(x: from.x, y: top + box.height + 34 + CGFloat(level) * 13))
                    }
                }
            }
            .frame(height: 26 + 30 + 34 + CGFloat(max(rows, 1)) * 13)
            if !empty.isEmpty {
                Text(empty.map { "\($0) → None" }.joined(separator: "   "))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .accessibilityLabel(nodes.map(\.label).joined(separator: " then "))
    }
}

/// Points, lines and paths over an optional heat map, in data coordinates.
private struct LabScatterView: View {
    let panel: LabPanel

    var body: some View {
        Canvas { context, size in
            let all = (panel.points ?? []) + (panel.centers ?? []) + (panel.path ?? [])
            let bounds = panel.bounds ?? [
                all.map { $0[0] }.min() ?? 0, all.map { $0[0] }.max() ?? 1,
                all.map { $0[1] }.min() ?? 0, all.map { $0[1] }.max() ?? 1,
            ]
            let inset: CGFloat = 8
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: inset + (x - bounds[0]) / max(1e-9, bounds[1] - bounds[0]) * (size.width - 2 * inset),
                        y: inset + (bounds[3] - y) / max(1e-9, bounds[3] - bounds[2]) * (size.height - 2 * inset))
            }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(AppTheme.raised.opacity(0.45)))
            if let field = panel.field, let first = field.first, !first.isEmpty {
                let cellWidth = size.width / CGFloat(first.count)
                let cellHeight = size.height / CGFloat(field.count)
                for (r, row) in field.enumerated() {
                    for (c, value) in row.enumerated() {
                        context.fill(Path(CGRect(x: CGFloat(c) * cellWidth, y: CGFloat(r) * cellHeight, width: cellWidth + 0.5, height: cellHeight + 0.5)),
                                     with: .color(AppTheme.blue.opacity(0.04 + 0.42 * value)))
                    }
                }
            }
            for trail in panel.trails ?? [] where trail.count > 1 {
                var path = Path()
                path.move(to: point(trail[0][0], trail[0][1]))
                trail.dropFirst().forEach { path.addLine(to: point($0[0], $0[1])) }
                context.stroke(path, with: .color(AppTheme.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let line = panel.path, line.count > 1 {
                var path = Path()
                path.move(to: point(line[0][0], line[0][1]))
                line.dropFirst().forEach { path.addLine(to: point($0[0], $0[1])) }
                context.stroke(path, with: .color(AppTheme.coral), lineWidth: 2)
                for spot in line {
                    let at = point(spot[0], spot[1])
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 2.5, y: at.y - 2.5, width: 5, height: 5)), with: .color(AppTheme.coral))
                }
            }
            for line in panel.lines ?? [] where line.count == 4 {
                var path = Path()
                path.move(to: point(line[0], line[1]))
                path.addLine(to: point(line[2], line[3]))
                context.stroke(path, with: .color(AppTheme.primary), lineWidth: 2.5)
            }
            for spot in panel.points ?? [] where spot.count >= 2 {
                let at = point(spot[0], spot[1])
                let group = spot.count > 2 ? Int(spot[2]) : 0
                if group == 9 {
                    context.draw(Text("✕").font(.system(size: 15, weight: .heavy)).foregroundStyle(AppTheme.primary), at: at)
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 4.5, y: at.y - 4.5, width: 9, height: 9)), with: .color(LabRole.group(group)))
                    context.stroke(Path(ellipseIn: CGRect(x: at.x - 4.5, y: at.y - 4.5, width: 9, height: 9)), with: .color(AppTheme.panel), lineWidth: 1)
                }
            }
            for spot in panel.centers ?? [] where spot.count >= 2 {
                let at = point(spot[0], spot[1])
                let group = spot.count > 2 ? Int(spot[2]) : 0
                let rect = CGRect(x: at.x - 9, y: at.y - 9, width: 18, height: 18)
                context.fill(Path(ellipseIn: rect), with: .color(AppTheme.run))
                context.stroke(Path(ellipseIn: rect), with: .color(LabRole.group(group)), lineWidth: 3.5)
            }
        }
        .aspectRatio(CGFloat(((panel.bounds?[safe: 1] ?? 1) - (panel.bounds?[safe: 0] ?? 0)) / max(0.1, (panel.bounds?[safe: 3] ?? 1) - (panel.bounds?[safe: 2] ?? 0))), contentMode: .fit)
        .frame(maxHeight: 300)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("A plot of \(panel.points?.count ?? 0) points")
    }
}

private struct LabPlotView: View {
    let series: [LabSeries]

    var body: some View {
        Chart {
            ForEach(series, id: \.name) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, point in
                    if point.count == 2 {
                        LineMark(x: .value("step", point[0]), y: .value("value", point[1]))
                            .foregroundStyle(by: .value("series", line.name))
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartForegroundStyleScale(range: [AppTheme.coral, AppTheme.blue, AppTheme.mint])
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .frame(height: 120)
    }
}

private struct LabVarsView: View {
    let pairs: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    Text(pair.first ?? "").foregroundStyle(AppTheme.muted)
                    Text(pair.count > 1 ? pair[1] : "").foregroundStyle(AppTheme.primary).lineLimit(2)
                }
                .font(.system(size: 12.5, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
