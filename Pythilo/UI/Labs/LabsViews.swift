import SwiftUI

struct LabStep: Decodable, Sendable {
    let kind: String
    let i: [Int]
    let values: [Int]
}

struct LabTrace: Decodable, Sendable {
    let id: String
    let steps: [LabStep]
    let correct: Bool
    let truncated: Bool
}

struct LabsView: View {
    let onOpenProject: (Project) -> Void
    @State private var path = NavigationPath()
    @State private var selected: LabInfo.Section?
    @State private var query = ""
    @State private var expandedTopics: Set<String> = []
    @State private var collapsedSearchTopics: Set<String> = []
    @State private var store = ContentStore.shared
    @State private var hidden = HiddenContent.shared
    @State private var showHidden = false
    @State private var removing: RemovalTarget?
    @State private var guideLab: LabInfo?

    private static let order: [LabInfo.Section] = [.learning, .intelligence, .basics, .structures, .algorithms]

    private var sections: [LabInfo.Section] {
        selected.map { [$0] } ?? Self.order
    }

    private func matching(_ section: LabInfo.Section) -> [LabInfo] {
        LabCatalog.all.filter {
            $0.section == section && (query.isEmpty || "\($0.title) \($0.summary) \(LabCatalog.topic(for: $0)?.title ?? "")".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if query.isEmpty { hero }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filter("All · \(LabCatalog.all.count)", systemImage: "square.grid.2x2", section: nil)
                            ForEach(Self.order, id: \.self) { section in
                                let count = LabCatalog.all.filter { $0.section == section }.count
                                filter("\(section.shortTitle) · \(count)", systemImage: section.systemImage, section: section)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                    if sections.allSatisfy({ matching($0).isEmpty }) {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(sections, id: \.self) { section in
                        let labs = matching(section)
                        if !labs.isEmpty {
                            sectionHeader(section, count: labs.count)
                            ForEach(LabCatalog.topics.filter { $0.section == section && (showHidden || !hidden.labTopics.contains($0.id)) }) { topic in
                                let matches = labs.filter { LabCatalog.topic(for: $0)?.id == topic.id }
                                if !matches.isEmpty {
                                    topicGroup(topic, labs: matches)
                                }
                            }
                        }
                    }
                    let hiddenTopics = LabCatalog.topics.filter { hidden.labTopics.contains($0.id) }.count
                    HiddenFooter(count: hiddenTopics, noun: hiddenTopics == 1 ? "topic" : "topics", showing: $showHidden,
                                 identifier: "labs-show-hidden")
                    Text("Touch and hold a topic to download, remove or hide it.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                    Text("Timings come from this device. They suggest a growth rate; they do not prove Big O.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    Text("Version \(AppInfo.version)")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Labs")
            .removalConfirmation($removing)
            .toolbar { DownloadsLink() }
            .searchable(text: $query, prompt: "Search all labs")
            .onChange(of: query) { collapsedSearchTopics = [] }
            .navigationDestination(for: String.self) { id in
                LabDestination(id: id)
            }
            .sheet(item: $guideLab) { LabGuideSheet(lab: $0) }
            .navigationDestination(for: LessonRoute.self) { route in
                LessonView(course: route.course, lesson: route.lesson, onOpenProject: onOpenProject)
            }
            #if DEBUG
            // For screenshots: -openLab <id> [-labVariant <id>] [-labRun YES] [-labAnswer YES] [-labStep 0.6] [-labScale YES].
            .onAppear {
                if path.isEmpty, let lab = UserDefaults.standard.string(forKey: "openLab") { path.append(lab) }
            }
            #endif
        }
    }

    /// What Labs are, in one look: the count, one sentence and three facts.
    private var hero: some View {
        let topics = LabCatalog.topics
        let offline = topics.filter { store.ready("labs-\($0.id)") }.count
        let linked = LabCatalog.all.filter { !($0.lessons ?? []).isEmpty }.count
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(LabCatalog.all.count) interactive labs")
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityIdentifier("labs-total")
                Text("Write the code yourself, trace every step and check the edge cases. Everything runs on this device.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                heroFact("\(topics.count)", "topics", systemImage: "square.stack.3d.up", tint: AppTheme.violet)
                heroFact("\(linked)", "with lessons", systemImage: "book", tint: AppTheme.blue)
                heroFact("\(offline)/\(topics.count)", "offline", systemImage: "arrow.down.circle", tint: AppTheme.mint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.violet.opacity(0.14), AppTheme.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.violet.opacity(0.18), lineWidth: 1) }
        .padding(.top, 4)
    }

    private func heroFact(_ value: String, _ label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text(label).font(.system(size: 12)).foregroundStyle(AppTheme.muted).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ section: LabInfo.Section, count: Int) -> some View {
        let download = CompactSelectionControl(
            packIDs: LabCatalog.topics.filter { $0.section == section && !hidden.labTopics.contains($0.id) }.map { "labs-\($0.id)" },
            title: "Download all",
            downloadID: "download-category-\(section.rawValue)",
            readyText: "Every topic in \(section.rawValue) is on this device.")
        let title = HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(section.tint)
                .frame(width: 24, height: 24)
                .background(section.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text("\(section.rawValue.uppercased()) · \(count)")
                .sectionLabel()
                .accessibilityAddTraits(.isHeader)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                title
                Spacer(minLength: 8)
                download
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                download
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 2)
    }

    private func topicGroup(_ topic: LabTopic, labs: [LabInfo]) -> some View {
        let expanded = query.isEmpty ? expandedTopics.contains(topic.id) : !collapsedSearchTopics.contains(topic.id)
        let tint = topic.section.tint
        let ready = store.ready("labs-\(topic.id)")
        let isHidden = hidden.labTopics.contains(topic.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if !query.isEmpty {
                        if collapsedSearchTopics.contains(topic.id) { collapsedSearchTopics.remove(topic.id) }
                        else { collapsedSearchTopics.insert(topic.id) }
                    } else if expandedTopics.contains(topic.id) { expandedTopics.remove(topic.id) }
                    else { expandedTopics.insert(topic.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: topic.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if ready {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.mint)
                                    .background(Circle().fill(AppTheme.panel).padding(1))
                                    .offset(x: 4, y: 4)
                                    .accessibilityLabel("Offline")
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(topic.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(AppTheme.primary)
                                .multilineTextAlignment(.leading)
                            if isHidden { HiddenTag() }
                        }
                        Text(preview(of: labs))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("\(labs.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(AppTheme.secondary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 28, minHeight: 24)
                        .background(AppTheme.raised, in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.app)
            .accessibilityIdentifier("labs-topic-\(topic.id)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .contentActions(packID: "labs-\(topic.id)", title: topic.title, noun: "topic", isReady: ready, isHidden: isHidden, remove: $removing) {
                withAnimation(.snappy(duration: 0.2)) { hidden.toggleTopic(topic.id) }
            }
            if expanded {
                Divider().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 10) {
                    if !ready {
                        // Stacked, so the button and its progress never sit on top of the text.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save this topic, its packages and data to use it offline.")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            CompactSelectionControl(packIDs: ["labs-\(topic.id)"], title: "Download", downloadID: "download-pack-labs-\(topic.id)")
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                        ForEach(labs) { lab($0) }
                    }
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .panelCard(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isHidden ? 0.6 : 1)
    }

    /// A taste of what is inside a collapsed topic.
    private func preview(of labs: [LabInfo]) -> String {
        let names = labs.prefix(3).map(\.title).joined(separator: " · ")
        return labs.count > 3 ? "\(names) +\(labs.count - 3)" : names
    }

    private func filter(_ title: String, systemImage: String, section: LabInfo.Section?) -> some View {
        let active = selected == section
        let tint = section?.tint ?? AppTheme.blue
        return Button { withAnimation(.snappy(duration: 0.2)) { selected = section } } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11.5, weight: .bold))
                Text(title).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(active ? AppTheme.onBlue : AppTheme.secondary)
            .background(active ? tint : AppTheme.panel, in: Capsule())
            .overlay { if !active { Capsule().stroke(AppTheme.border, lineWidth: 1) } }
        }
        .buttonStyle(.app)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func lab(_ info: LabInfo) -> some View {
        HStack(alignment: .top, spacing: 0) {
        NavigationLink(value: info.id) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: info.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(info.color)
                    .frame(width: 40, height: 40)
                    .background(info.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(AppTheme.primary)
                        .multilineTextAlignment(.leading)
                    Text(info.summary).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    let tags = tags(for: info)
                    if !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Label(tag.title, systemImage: tag.image)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AppTheme.secondary)
                                    .labelStyle(.titleAndIcon)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.raised, in: Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
                    .padding(.top, 12)
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, hasGuide(info) ? 4 : 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.app)
        .accessibilityIdentifier("lab-\(info.id)")
        if hasGuide(info) {
            // Beside the row, not inside it: the guide opens without the Lab's download.
            Button { guideLab = info } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.app)
            .padding(.top, 10)
            .padding(.trailing, 4)
            .accessibilityLabel("About \(info.title)")
            .accessibilityIdentifier("lab-about-\(info.id)")
        }
        }
        .background(AppTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border.opacity(0.7), lineWidth: 1) }
    }

    private func hasGuide(_ info: LabInfo) -> Bool { LabGuides.guide(for: info.id) != nil }

    private func tags(for info: LabInfo) -> [Tag] {
        var result: [Tag] = []
        if info.variants.count > 1 { result.append(Tag("\(info.variants.count) problems", "list.number")) }
        if let lessons = info.lessons, !lessons.isEmpty { result.append(Tag(lessons.count == 1 ? "Lesson" : "\(lessons.count) lessons", "book")) }
        return result
    }

    private struct Tag: Hashable {
        let title: String
        let image: String
        init(_ title: String, _ image: String) { self.title = title; self.image = image }
    }
}

extension LabInfo.Section {
    var shortTitle: String {
        switch self {
        case .learning: "ML"
        case .intelligence: "AI"
        default: rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "magnifyingglass"
        case .structures: "square.stack.3d.up"
        case .algorithms: "point.3.connected.trianglepath.dotted"
        case .learning: "brain"
        case .intelligence: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .basics: AppTheme.mint
        case .structures: AppTheme.amber
        case .algorithms: AppTheme.coral
        case .learning: AppTheme.violet
        case .intelligence: AppTheme.blue
        }
    }
}

extension LabTopic {
    var systemImage: String {
        switch id {
        case "ml-foundations": "function"
        case "ml-evaluation": "chart.xyaxis.line"
        case "ml-operations": "waveform.path.ecg"
        case "ml-projects": "shippingbox"
        case "pytorch-training": "flame"
        case "transformer-internals": "square.stack.3d.down.right"
        case "generation": "text.bubble"
        case "retrieval-rag": "doc.text.magnifyingglass"
        case "tools-evaluation": "wrench.and.screwdriver"
        case "transformer-projects": "cpu"
        case "basics": "magnifyingglass"
        case "structures": "square.grid.3x3.topleft.filled"
        case "algorithms": "point.3.filled.connected.trianglepath.dotted"
        case "finetuning-training": "speedometer"
        case "finetuning-adapters": "slider.horizontal.3"
        case "robust-training": "shield.lefthalf.filled"
        case "robustness-projects": "checkmark.shield"
        case "alignment-mechanisms": "scope"
        case "alignment-projects": "arrow.triangle.branch"
        default: section.systemImage
        }
    }
}

struct LabDestination: View {
    let id: String
    var body: some View {
        if let lab = LabCatalog.lab(id), let topic = LabCatalog.topic(for: lab) {
            DownloadGate(packID: "labs-\(topic.id)") {
                switch id {
                case "graph": GraphLabView()
                case "hash": HashLabView()
                case "dp": DPLabView()
                case "sorting": SortingBenchView()
                default: TraceLabView(lab: lab)
                }
            }
            .navigationTitle(lab.title)
            .labGuide(lab)
        }
    }
}

struct SortingBenchView: View {
    @AppStorage("pythilo.lab.sort") private var source = """
    def my_sort(items):
        for i in range(1, len(items)):
            key = items[i]
            j = i - 1
            while j >= 0 and items[j] > key:
                items[j + 1] = items[j]
                j -= 1
            items[j + 1] = key

    """
    @State private var cursor = 0
    @State private var trace: LabTrace?
    @State private var step = 0.0
    @State private var scale: LabScaleResult?
    @State private var traceIsStale = false
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your own code, traced while it runs. Define my_sort(items), which sorts the list in place.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                SyntaxCodeEditor(
                    text: $source,
                    cursorOffset: $cursor,
                    filePath: "sort.py",
                    isEditable: !session.isBusy,
                    tracksTyping: false,
                    navigationTarget: nil,
                    keyboardBridge: bridge,
                    onRequestCompletion: {}
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }

                HStack(spacing: 8) {
                    labButton("Trace", primary: true, action: runTrace).accessibilityIdentifier("lab-trace")
                    LabScaleButton(action: runMeasure)
                    if session.isBusy {
                        labButton("Stop", action: session.stop)
                    }
                }

                if let trace { traceView(trace) }
                if let scale { LabScaleCard(result: scale) }

                Text("Trace records every read and write your sort makes to the list. How it scales times it on longer and longer lists.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondary)

                ForEach(session.output.filter { $0.kind == .stderr }) { chunk in
                    Text(chunk.text).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(AppTheme.coralInk)
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                if UserDefaults.standard.bool(forKey: "labScale") { runMeasure() } else { runTrace() }
            }
        }
        #endif
        .navigationTitle("Sorting Bench")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: source) { traceIsStale = trace != nil }
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_trace", let value = try? JSONDecoder().decode(LabTrace.self, from: data) {
                    trace = value
                    step = 0
                    traceIsStale = false
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    scale = value
                }
            }
        }
    }

    private func labButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        LabActionButton(title: title, primary: primary, action: action)
    }

    private func runTrace() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_trace", "source": source], label: "trace")
    }

    private func runMeasure() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_measure", "source": source], label: "scale")
    }

    private func traceView(_ trace: LabTrace) -> some View {
        let index = min(Int(step), trace.steps.count - 1)
        let current = trace.steps[index]
        let top = max(1, current.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(current.values.enumerated()), id: \.offset) { position, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(current.i.contains(position) ? (current.kind == "write" ? AppTheme.coral : AppTheme.run) : AppTheme.blue.opacity(0.7))
                        .frame(height: 120 * CGFloat(value) / CGFloat(top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 124)
            .accessibilityLabel("Bars at step \(index + 1)")
            Slider(value: $step, in: 0...Double(max(1, trace.steps.count - 1)), step: 1)
                .tint(AppTheme.run)
                .accessibilityIdentifier("lab-step")
            HStack {
                Text("Step \(index + 1) of \(trace.steps.count)")
                Spacer()
                Text(current.kind == "write" ? "write [\(current.i.first ?? 0)]" : current.kind == "read" ? "read [\(current.i.first ?? 0)]" : "start")
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(AppTheme.secondary)
            if traceIsStale {
                Text("You changed the code. This trace is from the earlier version. Trace again.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.amber)
            } else if !trace.correct {
                Text("The list did not end up sorted.").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.coralInk)
            }
            if trace.truncated {
                Text("Stopped recording at \(trace.steps.count) steps.").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .panelCard()
    }
}
