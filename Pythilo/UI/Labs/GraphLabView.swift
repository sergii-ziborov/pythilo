import SwiftUI

struct GraphLabNode: Decodable, Sendable {
    let id: Int
    let x: Double
    let y: Double
}

struct GraphLabStep: Decodable, Sendable {
    let node: Int
    let expanded: [Int]
    let seen: [Int]
}

struct GraphLabTrace: Decodable, Sendable {
    let algorithm: String
    let nodes: [GraphLabNode]
    let edges: [[Int]]
    let start: Int
    let steps: [GraphLabStep]
    let labels: [String: Int]
    let correct: Bool
    let message: String
    let truncated: Bool
}

struct GraphLabView: View {
    enum Algorithm: String, CaseIterable { case bfs, dfs, dijkstra }

    @AppStorage("pythilo.lab.graph.algorithm") private var algorithm = Algorithm.bfs
    @AppStorage("pythilo.lab.graph.topology") private var topology = "grid"
    @AppStorage("pythilo.lab.graph.bfs") private var bfsSource = Self.templates[.bfs]!
    @AppStorage("pythilo.lab.graph.dfs") private var dfsSource = Self.templates[.dfs]!
    @AppStorage("pythilo.lab.graph.dijkstra") private var dijkstraSource = Self.templates[.dijkstra]!
    @State private var trace: GraphLabTrace?
    @State private var step = 0.0
    @State private var measure: LabScaleResult?
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabChoice(options: [(.bfs, "BFS"), (.dfs, "DFS"), (.dijkstra, "Dijkstra")], selection: $algorithm)
                LabCodeBox(source: source, filePath: "\(algorithm.rawValue).py", height: 190, bridge: bridge)
                ScrollView(.horizontal, showsIndicators: false) {
                    LabChips(options: [("grid", "Grid"), ("tree", "Tree"), ("sparse", "Sparse"), ("dense", "Dense")], selection: $topology)
                }
                HStack(spacing: 8) {
                    LabActionButton(title: "Trace", primary: true, action: runTrace).accessibilityIdentifier("graph-trace")
                    LabScaleButton(action: runMeasure)
                    if session.isBusy { LabActionButton(title: "Stop", action: session.stop) }
                }
                if let trace, trace.algorithm == algorithm.rawValue { traceView(trace) }
                if let measure, measure.variant == algorithm.rawValue { LabScaleCard(result: measure) }
                Text("The search reads the graph only through graph.neighbors(node), and each call is one step here. In Dijkstra it gives (node, weight) pairs.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondary)
                LabErrors()
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("Graph Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: algorithm) { trace = nil; measure = nil }
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_graph_trace", let value = try? JSONDecoder().decode(GraphLabTrace.self, from: data) {
                    trace = value
                    step = 0
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    measure = value
                }
            }
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                if UserDefaults.standard.bool(forKey: "labScale") { runMeasure() } else { runTrace() }
            }
        }
        #endif
    }

    private var source: Binding<String> {
        switch algorithm {
        case .bfs: $bfsSource
        case .dfs: $dfsSource
        case .dijkstra: $dijkstraSource
        }
    }

    private func runTrace() {
        bridge.dismissKeyboard()
        session.clearOutput()
        let size = topology == "dense" ? 10 : 16
        session.submit(["kind": "lab_graph_trace", "algorithm": algorithm.rawValue, "source": source.wrappedValue, "topology": topology, "size": size], label: "trace")
    }

    private func runMeasure() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_graph_measure", "algorithm": algorithm.rawValue, "source": source.wrappedValue, "topology": topology], label: "scale")
    }

    private func traceView(_ trace: GraphLabTrace) -> some View {
        let index = min(Int(step), max(0, trace.steps.count - 1))
        let current = trace.steps.isEmpty ? nil : trace.steps[index]
        let atEnd = index == trace.steps.count - 1
        return VStack(alignment: .leading, spacing: 8) {
            GraphLabCanvas(trace: trace, step: current, showsLabels: atEnd && trace.correct)
                .frame(height: 260)
                .accessibilityLabel(current.map { "Step \(index + 1): expanding node \($0.node), \($0.expanded.count) expanded so far" } ?? "No steps")
            if trace.steps.count > 1 {
                Slider(value: $step, in: 0...Double(trace.steps.count - 1), step: 1).tint(AppTheme.run)
            }
            HStack {
                Text("Step \(index + 1) of \(trace.steps.count)")
                Spacer()
                if let current { Text("neighbors(\(current.node))") }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(AppTheme.secondary)
            HStack(spacing: 12) {
                legend(fill: AppTheme.blue, ring: false, "expanded")
                legend(fill: AppTheme.blue, ring: true, "seen")
                legend(fill: AppTheme.run, ring: false, "now")
            }
            LabVerdict(correct: trace.correct, success: trace.algorithm == "dfs" ? "A valid depth-first order" : trace.algorithm == "bfs" ? "Every hop count matches" : "Every distance matches", message: trace.message)
        }
        .padding(12)
        .panelCard()
    }

    private func legend(fill: Color, ring: Bool, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ring ? .clear : fill).overlay { if ring { Circle().stroke(fill, lineWidth: 2) } }.frame(width: 10, height: 10)
            Text(title)
        }
        .font(.system(size: 12))
        .foregroundStyle(AppTheme.muted)
    }

    static let templates: [Algorithm: String] = [
        .bfs: """
        from collections import deque


        def bfs(graph, start):
            hops = {start: 0}
            queue = deque([start])
            while queue:
                node = queue.popleft()
                for nxt in graph.neighbors(node):
                    if nxt not in hops:
                        hops[nxt] = hops[node] + 1
                        queue.append(nxt)
            return hops

        """,
        .dfs: """
        def dfs(graph, start):
            order, seen = [], set()

            def visit(node):
                seen.add(node)
                order.append(node)
                for nxt in graph.neighbors(node):
                    if nxt not in seen:
                        visit(nxt)

            visit(start)
            return order

        """,
        .dijkstra: """
        import heapq


        def dijkstra(graph, start):
            distance = {start: 0}
            queue = [(0, start)]
            while queue:
                cost, node = heapq.heappop(queue)
                if cost > distance[node]:
                    continue
                for nxt, weight in graph.neighbors(node):
                    if cost + weight < distance.get(nxt, float("inf")):
                        distance[nxt] = cost + weight
                        heapq.heappush(queue, (cost + weight, nxt))
            return distance

        """,
    ]
}

private struct GraphLabCanvas: View {
    let trace: GraphLabTrace
    let step: GraphLabStep?
    let showsLabels: Bool

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            func point(_ id: Int) -> CGPoint {
                guard let node = trace.nodes.first(where: { $0.id == id }) else { return .zero }
                return CGPoint(x: inset + node.x * (size.width - 2 * inset), y: inset + node.y * (size.height - 2 * inset))
            }
            let expanded = Set(step?.expanded ?? [])
            let seen = Set(step?.seen ?? [])
            let radius: CGFloat = trace.nodes.count > 12 ? 12 : 15
            for edge in trace.edges where edge.count >= 2 {
                var path = Path()
                path.move(to: point(edge[0]))
                path.addLine(to: point(edge[1]))
                let lit = expanded.contains(edge[0]) && seen.contains(edge[1]) || expanded.contains(edge[1]) && seen.contains(edge[0])
                context.stroke(path, with: .color(lit ? AppTheme.blue.opacity(0.85) : AppTheme.border), lineWidth: lit ? 2.5 : 1.5)
                if trace.algorithm == "dijkstra", edge.count == 3 {
                    let a = point(edge[0]), b = point(edge[1])
                    context.draw(Text("\(edge[2])").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(AppTheme.muted), at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 7))
                }
            }
            for node in trace.nodes {
                let center = point(node.id)
                let isCurrent = step?.node == node.id
                let size = isCurrent ? radius + 2 : radius
                let rect = CGRect(x: center.x - size, y: center.y - size, width: 2 * size, height: 2 * size)
                let circle = Path(ellipseIn: rect)
                let ink: Color
                if isCurrent {
                    context.fill(circle, with: .color(AppTheme.run))
                    ink = AppTheme.onRun
                } else if expanded.contains(node.id) {
                    context.fill(circle, with: .color(AppTheme.blue))
                    ink = AppTheme.background
                } else if seen.contains(node.id) {
                    context.fill(circle, with: .color(AppTheme.panel))
                    context.stroke(circle, with: .color(AppTheme.blue), lineWidth: 2.5)
                    ink = AppTheme.selectionInk
                } else {
                    context.fill(circle, with: .color(AppTheme.raised))
                    ink = AppTheme.muted
                }
                context.draw(Text("\(node.id)").font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundStyle(ink), at: center)
                if showsLabels, let label = trace.labels["\(node.id)"] {
                    context.draw(Text("\(label)").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.mint), at: CGPoint(x: center.x + radius, y: center.y - radius))
                }
            }
        }
    }
}
