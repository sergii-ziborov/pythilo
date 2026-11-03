import SwiftUI
import UIKit

/// One live room: who is in it, runs waiting for this device's owner, permissions,
/// the link and the AI connection.
struct RoomView: View {
    let room: PlaygroundRoom
    var onOpen: ((Project) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmingEnd = false
    @State private var failure: String?
    @State private var connecting = false

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if room.ended || !room.session.connected {
                    Text(room.session.status).font(.system(size: 13.5)).foregroundStyle(room.ended ? AppTheme.coralInk : AppTheme.muted)
                }
                ForEach(room.host.approvals) { approval in
                    RunApprovalCard(approval: approval, device: device, onDeny: { room.host.deny(approval) }, onRun: { room.host.approve(approval) })
                }
                if let running = room.host.running { RunningCard(job: running, device: device) }
                participants
                permissions
                if let notice = grantNotice {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notice).font(.system(size: 13.5)).foregroundStyle(AppTheme.secondary)
                        Spacer(minLength: 8)
                        Button("Revoke") { room.host.revoke() }
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.coralInk)
                            .frame(minHeight: 44)
                    }
                }
                if room.isOwner, !room.leftOut.isEmpty { LeftOutList(files: room.leftOut) }
                if !room.host.history.isEmpty { history }
                if let failure = failure ?? room.failure {
                    Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                }
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = room.shareURL.absoluteString
                        copied = true
                    } label: {
                        Text(copied ? "Copied" : "Copy link").font(.system(size: 15, weight: .semibold)).playgroundButton(.secondary, height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-copy-link")
                    Button {
                        connecting = true
                    } label: {
                        Text("Connect AI").font(.system(size: 15, weight: .semibold)).playgroundButton(.secondary, height: 48)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(room.ended)
                if let onOpen, let project = room.project {
                    Button { onOpen(project) } label: {
                        Text("Open in the editor").font(.system(size: 15, weight: .semibold)).playgroundButton(.secondary, height: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(room.isOwner ? "End room" : "Leave room") { confirmingEnd = true }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.coralInk)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(AppTheme.coralFill, in: Capsule())
                    .overlay { Capsule().stroke(AppTheme.coral, lineWidth: 1) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-end")
            }
        }
        .confirmationDialog(room.isOwner ? "End this room for everyone?" : "Leave this room?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button(room.isOwner ? "End room" : "Leave room", role: .destructive, action: end)
        } message: {
            Text("Your copy of the files stays on this \(device).")
        }
        .navigationDestination(isPresented: $connecting) {
            MCPConnectionView(store: .shared, room: room)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(room.name).font(.system(size: 26, weight: .bold)).lineLimit(2)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let lead = "Room" + (room.revision.map { " · revision \($0)" } ?? "") + " · "
                let closing = room.ended ? "ended" : "closes in " + RoomTime.remaining(until: room.session.link.expiresAt, now: context.date)
                Text("\(lead)\(Text(closing).foregroundStyle(AppTheme.amber))")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var participants: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            VStack(spacing: 0) {
                Text("IN THE ROOM").sectionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                ForEach(Array(room.participants.enumerated()), id: \.element.id) { index, person in
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                    ParticipantRow(person: person, index: index)
                }
            }
            .panelCard()
        }
    }

    private var permissions: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Others run code on this \(device)").font(.system(size: 15))
                Spacer(minLength: 8)
                if room.session.link.isReadOnly {
                    Text("Needs edit access").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                } else {
                    Menu {
                        Picker("Others run code on this \(device)", selection: Binding(get: { room.host.policy }, set: { room.host.policy = $0 })) {
                            ForEach(PlaygroundRunPolicy.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Text(room.host.policy.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(room.host.policy.tint)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("room-run-policy")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            Rectangle().fill(AppTheme.border).frame(height: 1)
            HStack {
                Text("Git commit and push").font(.system(size: 15))
                Spacer(minLength: 8)
                Text("Only you").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.coralInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
        .panelCard()
    }

    private var grantNotice: String? {
        guard let grant = room.host.grant else { return nil }
        let until = Date(timeIntervalSince1970: Double(grant.expires) / 1000).formatted(date: .omitted, time: .shortened)
        let name = PlaygroundController(grant.name).name
        return room.host.policy == .ask ? "\(name) may ask to run code here until \(until)." : "\(name) may run code here until \(until)."
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("RECENT RUNS ON THIS \(device.uppercased())").sectionLabel()
            ForEach(room.host.history.prefix(6)) { record in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.started, style: .time).foregroundStyle(AppTheme.muted)
                    Text("\(Text(record.command).font(.system(size: 13, design: .monospaced))) for \(record.requester) · \(Self.outcome(record))")
                }
                .font(.system(size: 13.5))
            }
        }
    }

    private static func outcome(_ record: PlaygroundJobRecord) -> String {
        switch record.status {
        case "denied": return "denied"
        case "timeout": return "stopped at the time limit"
        case "cancelled": return "stopped"
        default:
            let seconds = String(format: "%.2f s", record.duration)
            return record.exitCode.map { "exit \($0) · \(seconds)" } ?? "\(record.status) · \(seconds)"
        }
    }

    private func end() {
        Task {
            do {
                try await PlaygroundRooms.shared.end(room)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

private struct ParticipantRow: View {
    let person: PlaygroundParticipant
    let index: Int

    private var tint: Color {
        if person.isSelf { return AppTheme.selectionInk }
        return [AppTheme.mint, AppTheme.violet, AppTheme.amber, AppTheme.blue][index % 4]
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(String((person.isSelf ? (PlaygroundRuntimeHost.ownerName ?? "Y") : person.name).prefix(1)).uppercased())
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(person.detail).font(.system(size: 12.5)).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !person.access.isEmpty {
                Text(person.access).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(person.access == "Owner" ? AppTheme.mint : AppTheme.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// "Ada wants to run code on this iPhone", with Deny and Run once.
struct RunApprovalCard: View {
    let approval: PlaygroundRunApproval
    let device: String
    let onDeny: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(approval.requester.uppercased()) WANTS TO RUN CODE ON THIS \(device.uppercased())")
                .font(.system(size: 12, weight: .bold))
                .kerning(0.7)
                .foregroundStyle(AppTheme.amber)
            Text(approval.command)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("Revision \(approval.revision.prefix(6))\(approval.origin.isEmpty ? "" : ", " + approval.origin). It can read files and the network like any code in this app. \(approval.requester) sees the output, marked as run on this \(device).")
                .font(.system(size: 13.5))
                .foregroundStyle(AppTheme.secondary)
            HStack(spacing: 8) {
                Button(action: onDeny) {
                    Text("Deny").font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("room-run-deny")
                Button(action: onRun) {
                    Text("Run once").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.onRun)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.run, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("room-run-once")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.amber.opacity(0.45), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct RunningCard: View {
    let job: PlaygroundRunApproval
    let device: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 1) {
                Text("Running for \(job.requester)").font(.system(size: 15, weight: .semibold))
                Text(job.command).font(.system(size: 13, design: .monospaced)).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 6)
            Button("Stop") { RunSession.shared.stop() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.coralInk)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .panelCard()
    }
}
