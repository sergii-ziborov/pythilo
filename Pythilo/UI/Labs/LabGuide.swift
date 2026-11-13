import SwiftUI
import UIKit

/// What a Lab's algorithm is, how it works, what it costs and where it is used.
/// One entry per Lab in Resources/LabGuides/lab-guides.json. It is part of the app,
/// so it can be read before the Lab's topic is downloaded.
struct LabGuide: Decodable, Sendable {
    struct Cost: Decodable, Hashable, Sendable {
        let label: String
        let value: String
    }

    let idea: String
    let steps: [String]
    let cost: [Cost]
    let costNote: String
    let uses: [String]
    let pitfalls: [String]
    let watch: String
}

enum LabGuides {
    private static let folder = Bundle.main.bundleURL.appending(path: "LabGuides")

    private static let all: [String: LabGuide] = {
        guard let data = try? Data(contentsOf: folder.appending(path: "lab-guides.json")) else { return [:] }
        return (try? JSONDecoder().decode([String: LabGuide].self, from: data)) ?? [:]
    }()

    static func guide(for lab: String) -> LabGuide? { all[lab] }

    /// The Lab's own illustration, or its topic's when the Lab has none.
    static func image(for lab: LabInfo) -> UIImage? {
        let names = ["labs/\(lab.id)", LabCatalog.topic(for: lab).map { "topics/\($0.id)" }].compactMap { $0 }
        for name in names {
            for kind in ["heic", "jpg"] {
                if let image = UIImage(contentsOfFile: folder.appending(path: "\(name).\(kind)").path) { return image }
            }
        }
        return nil
    }
}

/// Opens a Lab's guide from its navigation bar.
struct LabGuideButton: ViewModifier {
    let lab: LabInfo
    @State private var showing = false

    func body(content: Content) -> some View {
        if LabGuides.guide(for: lab.id) == nil { content } else {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showing = true } label: {
                            Label("About", systemImage: "info.circle")
                        }
                        .accessibilityLabel("About this algorithm")
                        .accessibilityIdentifier("lab-about")
                    }
                }
                .sheet(isPresented: $showing) { LabGuideSheet(lab: lab) }
        }
    }
}

struct LabGuideSheet: View {
    let lab: LabInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let guide = LabGuides.guide(for: lab.id) {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        section("The idea", systemImage: "lightbulb") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(guide.idea.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                    prose(paragraph)
                                }
                            }
                        }
                        section("How it works", systemImage: "list.number") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                                            .foregroundStyle(lab.color)
                                            .frame(width: 26, height: 26)
                                            .background(lab.color.opacity(0.15), in: Circle())
                                            .accessibilityHidden(true)
                                        prose(step)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Step \(index + 1). \(plain(step))")
                                }
                            }
                        }
                        section("What it costs", systemImage: "gauge.with.dots.needle.33percent") {
                            VStack(alignment: .leading, spacing: 12) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) { costs(guide) }
                                    VStack(alignment: .leading, spacing: 8) { costs(guide) }
                                }
                                prose(guide.costNote)
                            }
                        }
                        section("Where it is used", systemImage: "map") {
                            bullets(guide.uses, systemImage: "arrow.right.circle.fill", tint: AppTheme.blue)
                        }
                        section("Watch out for", systemImage: "exclamationmark.triangle") {
                            bullets(guide.pitfalls, systemImage: "exclamationmark.circle.fill", tint: AppTheme.amber)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "eye")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(lab.color)
                                .frame(width: 34, height: 34)
                                .background(lab.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("In this Lab").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.primary)
                                prose(guide.watch)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
                        .accessibilityElement(children: .combine)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("lab-about-done")
                }
            }
        }
        // A page-sized sheet on iPad, where the default form sheet is narrow for reading.
        .presentationSizing(.page)
        .accessibilityIdentifier("lab-about-sheet")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = LabGuides.image(for: lab) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border.opacity(0.8), lineWidth: 1) }
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: lab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(lab.color)
                    .frame(width: 46, height: 46)
                    .background(lab.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let topic = LabCatalog.topic(for: lab) {
                        Text(topic.title.uppercased())
                            .font(.system(size: 11.5, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(lab.color)
                    }
                    Text(lab.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("lab-about-title")
                    Text(lab.summary)
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func costs(_ guide: LabGuide) -> some View {
        ForEach(guide.cost, id: \.self) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.uppercased())
                    .font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(AppTheme.muted)
                Text(item.value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.primary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func bullets(_ items: [String], systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    prose(item)
                }
            }
        }
    }

    /// Body text with `code` spans in the guide's own Markdown.
    private func prose(_ text: String) -> some View {
        Text(Self.inline(text))
            .font(.system(size: 16))
            .lineSpacing(3)
            .foregroundStyle(AppTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plain(_ text: String) -> String { String(Self.inline(text).characters) }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

extension View {
    /// Adds About to a Lab's navigation bar when the Lab has a guide.
    func labGuide(_ lab: LabInfo) -> some View { modifier(LabGuideButton(lab: lab)) }
}
