import PythiloGit
import SwiftUI
import UIKit

/// The nested file tree. Rows show type, Git state and indent guides.
struct FileTreeView: View {
    @Bindable var model: WorkspaceModel
    var rowHeight: CGFloat = 40
    var filter = ""
    var onOpen: () -> Void = {}
    @State private var creatingIn: NewItemTarget?
    @State private var renaming: FileNode?
    @State private var renameText = ""
    @State private var moving: FileNode?
    @State private var moveText = ""
    @State private var deleting: FileNode?
    @State private var failure: String?

    private struct Row: Identifiable {
        let node: FileNode
        let depth: Int
        var id: String { node.path }
    }

    private var rows: [Row] {
        var result: [Row] = []
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                if query.isEmpty {
                    result.append(Row(node: node, depth: depth))
                    if node.isDirectory, model.expanded.contains(node.path) {
                        walk(node.children, depth: depth + 1)
                    }
                } else {
                    if !node.isDirectory, node.path.lowercased().contains(query) {
                        result.append(Row(node: node, depth: 0))
                    }
                    walk(node.children, depth: 0)
                }
            }
        }
        walk(model.tree, depth: 0)
        return result
    }

    private var badges: [String: Character] {
        var result: [String: Character] = [:]
        for change in model.gitSnapshot?.changes ?? [] {
            let badge: Character = switch change.kind {
            case .added: "A"
            case .untracked: "?"
            case .deleted: "D"
            case .conflicted: "!"
            default: "M"
            }
            result[change.path] = badge
            var parent = change.path
            while parent.contains("/") {
                parent = (parent as NSString).deletingLastPathComponent
                if result[parent] == nil || badge == "M" { result[parent] = badge == "?" ? "?" : "M" }
            }
        }
        return result
    }

    var body: some View {
        let badges = badges
        LazyVStack(spacing: 0) {
            ForEach(rows) { row in
                rowView(row, badge: badges[row.node.path])
            }
        }
        .sheet(item: $creatingIn) { target in
            NewItemSheet(model: model, target: target)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Rename") {
                if let node = renaming { attempt { try model.rename(node.path, to: renameText) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Move to", isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })) {
            TextField("Path", text: $moveText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Move") {
                if let node = moving { attempt { try model.move(node.path, to: moveText) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the new path inside this project. Missing folders are created.")
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let node = deleting { attempt { try model.delete(node.path) } }
            }
        } message: {
            Text("This removes it from the device. Commit first if you may want it back.")
        }
        .alert("Could not do that", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }

    @ViewBuilder
    private func rowView(_ row: Row, badge: Character?) -> some View {
        let node = row.node
        let open = model.expanded.contains(node.path)
        let selected = model.selectedPath == node.path
        HStack(spacing: 0) {
            Button {
                if node.isDirectory {
                    model.toggle(folder: node.path)
                } else {
                    model.open(node.path)
                    onOpen()
                }
            } label: {
                HStack(spacing: 7) {
                    Group {
                        if node.isDirectory {
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.muted)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 12)
                    FileIconView(name: node.name, isDirectory: node.isDirectory, isOpen: open)
                    Text(node.name)
                        .font(.system(size: 13.5, weight: selected || node.isDirectory ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(badge == "M" && !selected ? AppTheme.amber : AppTheme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    if let badge {
                        Text(String(badge))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(badge == "A" ? AppTheme.mint : badge == "?" ? AppTheme.muted : badge == "D" || badge == "!" ? AppTheme.coralInk : AppTheme.amber)
                            .frame(width: 18)
                    }
                }
                .padding(.leading, 6 + CGFloat(row.depth) * 16)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if node.isDirectory {
                Button {
                    creatingIn = NewItemTarget(folder: node.path)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 36, height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New item in \(node.name)")
            }
        }
        .background {
            ZStack(alignment: .leading) {
                Color.clear
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.selection)
                }
                ForEach(0..<row.depth, id: \.self) { level in
                    Rectangle().fill(AppTheme.border).frame(width: 1).offset(x: 12 + CGFloat(level) * 16)
                }
            }
        }
        .contextMenu { menu(for: node) }
        .accessibilityIdentifier("tree-\(node.path)")
    }

    @ViewBuilder
    private func menu(for node: FileNode) -> some View {
        if node.isDirectory {
            Button("New file or folder here", systemImage: "plus") {
                creatingIn = NewItemTarget(folder: node.path)
            }
        } else {
            Button("New file beside it", systemImage: "doc.badge.plus") {
                let parent = (node.path as NSString).deletingLastPathComponent
                creatingIn = NewItemTarget(folder: parent.isEmpty ? nil : parent)
            }
        }
        Button("Rename", systemImage: "pencil") {
            renameText = node.name
            renaming = node
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            attempt { try model.duplicate(node.path) }
        }
        Button("Move to folder…", systemImage: "folder") {
            moveText = node.path
            moving = node
        }
        Button("Copy path", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = node.path
        }
        ShareLink(item: model.fileURL(node.path)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            deleting = node
        }
    }
}

struct NewItemTarget: Identifiable {
    let folder: String?
    var id: String { folder ?? "." }
}

/// New file or folder. The path can hold slashes, so one entry makes a nested
/// structure, and the preview shows which folders are about to appear.
struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel
    let target: NewItemTarget
    var startsAsFolder = false
    @State private var isFolder = false
    @State private var path = ""
    @State private var template = "Empty"
    @State private var failure: String?
    @FocusState private var focused: Bool

    private let templates: [(String, String)] = [
        ("Empty", ""),
        ("Module", "\"\"\"Describe this module.\"\"\"\n\n\ndef main():\n    pass\n"),
        ("Package", ""),
        ("Test", "def test_example():\n    assert 1 + 1 == 2\n"),
        ("Notebook", "{\n \"cells\": [],\n \"metadata\": {},\n \"nbformat\": 4,\n \"nbformat_minor\": 5\n}\n"),
    ]

    private var parts: [String] {
        path.split(separator: "/").map(String.init)
    }

    private func exists(upTo index: Int) -> Bool {
        var relative = target.folder ?? ""
        for part in parts.prefix(index + 1) {
            relative = relative.isEmpty ? part : "\(relative)/\(part)"
        }
        return FileManager.default.fileExists(atPath: model.fileURL(relative).path)
    }

    private var resolved: (path: String, contents: String, folder: Bool) {
        let contents = templates.first { $0.0 == template }?.1 ?? ""
        if isFolder { return (path, "", true) }
        switch template {
        case "Package":
            return ("\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/__init__.py", "", false)
        case "Notebook" where !path.hasSuffix(".ipynb"):
            return ("\(path).ipynb", contents, false)
        case "Module" where !path.contains("."), "Test" where !path.contains("."):
            return ("\(path).py", contents, false)
        default:
            return (path, contents, false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Kind", selection: $isFolder) {
                        Text("File").tag(false)
                        Text("Folder").tag(true)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PATH INSIDE THIS FOLDER").sectionLabel()
                        HStack(spacing: 8) {
                            FileIconView(name: parts.last ?? "x.py", isDirectory: isFolder)
                            TextField(isFolder ? "partials/cards" : "partials/cards/note.py", text: $path)
                                .font(.system(size: 15, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)
                                .accessibilityIdentifier("new-item-path")
                                .onSubmit(create)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.blue, lineWidth: 1.5) }
                    }

                    if !parts.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                FileIconView(name: "", isDirectory: true, isOpen: true)
                                Text((target.folder ?? model.project.name) + "/")
                                    .foregroundStyle(AppTheme.muted)
                            }
                            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                                let last = index == parts.count - 1
                                let folder = !last || isFolder
                                HStack(spacing: 7) {
                                    FileIconView(name: part, isDirectory: folder, isOpen: true)
                                    Text(part + (folder ? "/" : ""))
                                    Spacer()
                                    Text(exists(upTo: index) ? "exists" : folder ? "new folder" : "new file")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(exists(upTo: index) ? AppTheme.muted : AppTheme.mint)
                                }
                                .padding(.leading, CGFloat(index + 1) * 18)
                            }
                        }
                        .font(.system(size: 13, design: .monospaced))
                    }

                    if !isFolder {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("START FROM").sectionLabel()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(templates, id: \.0) { item in
                                        Button(item.0) { template = item.0 }
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(template == item.0 ? AppTheme.selectionInk : AppTheme.primary)
                                            .padding(.horizontal, 12)
                                            .frame(height: 44)
                                            .background(template == item.0 ? AppTheme.selection : AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if let failure {
                        Text(failure).font(.system(size: 14)).foregroundStyle(AppTheme.coralInk)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.panel)
            .navigationTitle("New in \(target.folder ?? model.project.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(parts.isEmpty).accessibilityIdentifier("new-item-create")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["/", ".py", "_", "-", "."], id: \.self) { symbol in
                        Button(symbol) { path += symbol }.font(.system(size: 15, design: .monospaced))
                    }
                }
            }
            .onAppear {
                isFolder = startsAsFolder
                focused = true
            }
        }
        .presentationDetents([.large])
    }

    private func create() {
        guard !parts.isEmpty else { return }
        do {
            let item = resolved
            try model.create(path: item.path, in: target.folder, isDirectory: item.folder, contents: item.contents)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
