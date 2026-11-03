import SwiftUI

/// The framework's commands, one tap each. A server command leads, in green.
struct ProjectCommandBar: View {
    @Bindable var model: WorkspaceModel
    @State private var showingAll = false

    var body: some View {
        let commands = model.commands
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let framework = commands.framework {
                    Text(framework.rawValue.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.6)
                        .foregroundStyle(AppTheme.mint)
                        .padding(.trailing, 2)
                }
                ForEach(commands.featured) { command in
                    Button { model.use(command) } label: {
                        HStack(spacing: 6) {
                            if command.servesSite { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)) }
                            Text(command.title)
                        }
                        .font(.system(size: 13, weight: command.servesSite ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(command.servesSite ? AppTheme.mint : AppTheme.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(command.servesSite ? AppTheme.mint.opacity(0.14) : AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(command.line)
                    .accessibilityIdentifier("command-\(command.title)")
                }
                if commands.all.count > commands.featured.count {
                    Button("All \(commands.all.count) commands") { showingAll = true }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("all-commands")
                }
                if !commands.npm.isEmpty {
                    Text("NPM")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.6)
                        .foregroundStyle(AppTheme.amber)
                        .padding(.leading, commands.featured.isEmpty ? 0 : 6)
                        .padding(.trailing, 2)
                    ForEach(commands.npm) { command in
                        Button(command.title) { model.use(command) }
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                            .buttonStyle(.plain)
                            .accessibilityLabel(command.line)
                            .accessibilityIdentifier("npm-\(command.title)")
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 52)
        .background(AppTheme.panel, ignoresSafeAreaEdges: [])
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
        .sheet(isPresented: $showingAll) { ProjectCommandsSheet(model: model) }
    }
}

/// Every command Django listed, grouped by the app it comes from.
struct ProjectCommandsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel

    var body: some View {
        let groups = Dictionary(grouping: model.commands.all, by: \.group)
        NavigationStack {
            List {
                ForEach(groups.keys.sorted(), id: \.self) { group in
                    Section(group.isEmpty ? "Commands" : group) {
                        ForEach(groups[group] ?? []) { command in
                            Button {
                                dismiss()
                                model.use(command)
                            } label: {
                                HStack {
                                    Text(command.title).font(.system(size: 15, design: .monospaced))
                                    Spacer()
                                    Text(command.needsArgument ? "Fill in" : command.servesSite ? "Start" : "Run")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(command.servesSite ? AppTheme.mint : AppTheme.selectionInk)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(model.commands.framework?.rawValue ?? "Project") commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Says the program is serving a site, with one tap to open it.
struct ServerBanner: View {
    let url: URL
    let framework: String?
    var unappliedMigrations = 0
    let onOpen: () -> Void
    var onMigrate: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            running
            if unappliedMigrations > 0 { migrations }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.panel)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill((unappliedMigrations > 0 ? AppTheme.amber : AppTheme.mint).opacity(0.12))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke((unappliedMigrations > 0 ? AppTheme.amber : AppTheme.mint).opacity(0.45), lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    /// Django starts with unapplied migrations, then fails on the first page that
    /// touches a table. Said here, where it is seen, with the fix one tap away.
    private var migrations: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.amber).accessibilityHidden(true)
            Text("\(unappliedMigrations) migration\(unappliedMigrations == 1 ? " is" : "s are") not applied. Pages that use the database will fail.")
                .font(.system(size: 13.5))
                .foregroundStyle(AppTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onMigrate) {
                Text("Migrate & restart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.onRun)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(AppTheme.run, in: Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("migrate-restart")
        }
    }

    private var running: some View {
        HStack(spacing: 10) {
            Circle().fill(AppTheme.mint).frame(width: 10, height: 10)
                .background(Circle().fill(AppTheme.mint.opacity(0.22)).frame(width: 18, height: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(framework.map { "\($0) is running" } ?? "Site is running").font(.system(size: 15, weight: .bold))
                Text(url.host().map { "\($0):\(url.port ?? 80)" } ?? url.absoluteString)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.mint)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button(action: onOpen) {
                Label("Open site", systemImage: "globe")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.onBlue)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(AppTheme.blue, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-site")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site is running at \(url.absoluteString)")
    }
}
