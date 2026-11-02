import SwiftUI
import UIKit

struct PlaygroundView: View {
    let store: ProjectStore
    let onOpen: (Project) -> Void
    @State private var host = MCPHost.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Work on one project with an AI client on your computer. It reaches this device over your local network, with no account or cloud service. Editing and running code are separate permissions.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                    if host.isRunning {
                        MCPActiveCard(host: host)
                    } else {
                        Text("SHARE A PROJECT").sectionLabel()
                        if store.projects.isEmpty {
                            Text("Create a project first.").font(.system(size: 15)).foregroundStyle(AppTheme.muted)
                        }
                        VStack(spacing: 8) {
                            ForEach(store.projects) { project in
                                Button {
                                    host.start(project: project)
                                } label: {
                                    HStack(spacing: 12) {
                                        FileIconView(name: "", isDirectory: true, isOpen: true)
                                        Text(project.name).font(.system(size: 15.5, weight: .semibold))
                                        Spacer()
                                        Text("Connect").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.blue)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 52)
                                    .panelCard()
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("mcp-share-\(project.name)")
                            }
                        }
                    }
                    if let failure = host.failure {
                        Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                    }
                    Text("Shared rooms with other people need a hosted relay, which is not set up yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Playground")
            .onAppear(perform: store.refresh)
        }
    }
}

/// Connection details, permissions, approvals and what the client did.
struct MCPActiveCard: View {
    @Bindable var host: MCPHost
    @State private var client = "claude"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(host.clientName == nil ? AppTheme.amber : AppTheme.mint).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.clientName ?? "Waiting for a client").font(.system(size: 20, weight: .bold))
                    Text("Sharing \(host.project?.name ?? "") · keep Pythilo open").font(.system(size: 13.5)).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button("Stop sharing") { host.stop() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.coralInk)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppTheme.coralFill, in: Capsule())
                    .overlay { Capsule().stroke(AppTheme.coral, lineWidth: 1) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mcp-stop")
            }

            ForEach(host.pending) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text("WANTS TO: \(request.permission.title.uppercased())").font(.system(size: 12, weight: .bold)).foregroundStyle(AppTheme.amber)
                    Text(request.summary).font(.system(size: 15, weight: .semibold))
                    if !request.detail.isEmpty {
                        Text(request.detail)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if request.permission == .run || request.permission == .packages {
                        Text("Code here can read files and the network like any code in this app.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Deny") { host.answer(request, allow: false) }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mcp-deny")
                        Button("Allow once") { host.answer(request, allow: true) }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.onRun)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(AppTheme.run, in: RoundedRectangle(cornerRadius: 11))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mcp-allow")
                    }
                }
                .padding(12)
                .background(AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if host.clientName == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Client", selection: $client) {
                        Text("Claude Code").tag("claude")
                        Text("Codex").tag("codex")
                    }
                    .pickerStyle(.segmented)
                    Text("ON YOUR COMPUTER, ON THE SAME NETWORK").sectionLabel()
                    Text(host.command(for: client))
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityIdentifier("mcp-command")
                    if client == "codex" {
                        Text("Set PYTHILO_TOKEN to \(host.token)")
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button(copied ? "Copied" : "Copy command") {
                        UIPasteboard.general.string = host.command(for: client)
                        copied = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
                    Text("Any other MCP client: Streamable HTTP at \(host.address ?? ""), with the same bearer token. The token ends when you stop sharing.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .panelCard()
            }

            VStack(spacing: 0) {
                Text("WHAT IT MAY DO").sectionLabel().frame(maxWidth: .infinity, alignment: .leading).padding(12)
                ForEach(MCPPermission.allCases) { permission in
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                    HStack {
                        Text(permission.title).font(.system(size: 15))
                        Spacer()
                        Picker(permission.title, selection: Binding(
                            get: { host.grants[permission] ?? .deny },
                            set: { host.grants[permission] = $0 }
                        )) {
                            ForEach(MCPGrant.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
            }
            .panelCard()

            if !host.activity.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT").sectionLabel()
                    ForEach(host.activity.prefix(8)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.date, style: .time).foregroundStyle(AppTheme.muted)
                            Text(item.text)
                        }
                        .font(.system(size: 13.5))
                    }
                }
            }
        }
    }
}

/// The same controls from inside a project.
struct RoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel
    @State private var host = MCPHost.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if host.isRunning, host.project?.id == model.project.id {
                        MCPActiveCard(host: host)
                    } else {
                        Text("Let an AI client on your computer work on \(model.project.name), over your local network.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.secondary)
                        Button("Connect an AI client") {
                            host.start(project: model.project)
                            host.workspace = model
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.onBlue)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 14))
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if host.project?.id == model.project.id { host.workspace = model } }
        }
    }
}
