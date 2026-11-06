import SQLite3
import SwiftUI

/// One value read from SQLite, kept with its storage class so NULL, numbers and
/// blobs are shown and edited for what they are.
enum SQLiteValue: Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Int)

    var display: String {
        switch self {
        case .null: return "NULL"
        case let .integer(value): return String(value)
        case let .real(value): return String(value)
        case let .text(value): return value
        case let .blob(count): return "BLOB, \(count) bytes"
        }
    }

    /// What goes in an edit field; NULL is an empty field marked as NULL.
    var editable: String {
        switch self {
        case .null, .blob: return ""
        default: return display
        }
    }

    var isNumber: Bool {
        switch self {
        case .integer, .real: return true
        default: return false
        }
    }
}

struct SQLiteResult {
    var columns: [String] = []
    var rows: [[SQLiteValue]] = []
    var changes = 0
    var isQuery: Bool { !columns.isEmpty }
}

struct SQLiteColumn: Identifiable, Hashable {
    let name: String
    let type: String
    let notNull: Bool
    let primaryKey: Bool
    var id: String { name }
}

struct SQLiteTable: Identifiable, Hashable {
    let name: String
    let kind: String
    let sql: String
    var rows: Int
    var id: String { name }
}

struct SQLiteFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A thin wrapper over the SQLite C API. The database may be open in Python
/// too, for example under a running Django server, so every call waits briefly
/// for a lock instead of failing at once.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open"
            sqlite3_close(handle)
            throw SQLiteFailure(message: message)
        }
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit { sqlite3_close(handle) }

    static func quote(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Runs every statement in `sql`; the result is that of the last one that
    /// returned rows, or the number of rows the statements changed.
    func execute(_ sql: String, bindings: [SQLiteValue?] = [], limit: Int = 1000) throws -> SQLiteResult {
        var result = SQLiteResult()
        let before = sqlite3_total_changes(handle)
        var remaining = sql
        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var statement: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            let code = remaining.withCString { pointer -> Int32 in
                let status = sqlite3_prepare_v2(handle, pointer, -1, &statement, &tail)
                if let tail { remaining = String(cString: tail) } else { remaining = "" }
                return status
            }
            guard code == SQLITE_OK else { throw failure() }
            guard let statement else { continue }
            defer { sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() where sqlite3_bind_parameter_count(statement) > index {
                bind(value, at: Int32(index + 1), in: statement)
            }
            let count = sqlite3_column_count(statement)
            var rows: [[SQLiteValue]] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw failure() }
                if rows.count < limit {
                    rows.append((0..<count).map { value(statement, $0) })
                }
            }
            if count > 0 {
                result.columns = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
                result.rows = rows
            }
        }
        result.changes = Int(sqlite3_total_changes(handle) - before)
        return result
    }

    func tables() throws -> [SQLiteTable] {
        let listed = try execute("select name, type, coalesce(sql, '') from sqlite_schema where type in ('table', 'view') and name not like 'sqlite_%' order by type, name")
        return listed.rows.map { row in
            let name = row[0].display
            let rows = (try? execute("select count(*) from \(Self.quote(name))").rows.first?.first).flatMap { value -> Int? in
                if case let .integer(count) = value { return Int(count) }
                return nil
            } ?? 0
            return SQLiteTable(name: name, kind: row[1].display, sql: row[2].display, rows: rows)
        }
    }

    func columns(of table: String) throws -> [SQLiteColumn] {
        try execute("pragma table_info(\(Self.quote(table)))").rows.map { row in
            SQLiteColumn(
                name: row[1].display,
                type: row[2].display,
                notNull: row[3] == .integer(1),
                primaryKey: row[5] != .integer(0)
            )
        }
    }

    private func failure() -> SQLiteFailure {
        SQLiteFailure(message: String(cString: sqlite3_errmsg(handle)))
    }

    private func value(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, index)))
        case SQLITE_BLOB: return .blob(Int(sqlite3_column_bytes(statement, index)))
        default: return .null
        }
    }

    private func bind(_ value: SQLiteValue?, at index: Int32, in statement: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        switch value ?? .null {
        case .null, .blob: sqlite3_bind_null(statement, index)
        case let .integer(number): sqlite3_bind_int64(statement, index, number)
        case let .real(number): sqlite3_bind_double(statement, index, number)
        case let .text(text): sqlite3_bind_text(statement, index, text, -1, transient)
        }
    }
}

/// Browses and edits a SQLite file: its tables, their rows and schema, and SQL.
struct DatabaseView: View {
    @Bindable var model: WorkspaceModel
    let path: String

    private enum Mode: String, CaseIterable { case data = "Data", schema = "Schema", sql = "SQL" }

    @State private var database: SQLiteDatabase?
    @State private var tables: [SQLiteTable] = []
    @State private var selected: String?
    @State private var mode = Mode.data
    @State private var result = SQLiteResult()
    @State private var rowIDs: [Int64?] = []
    @State private var columns: [SQLiteColumn] = []
    @State private var filter = ""
    @State private var pageSize = 100
    @State private var failure: String?
    @State private var query = ""
    @State private var queryResult: SQLiteResult?
    @State private var queryMessage: String?
    @State private var editing: RowEdit?

    struct RowEdit: Identifiable {
        let id = UUID()
        let rowID: Int64?
        var fields: [String: String]
        var nulls: Set<String>
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(AppTheme.border).frame(height: 1)
            if let failure, database == nil {
                ContentUnavailableView("Cannot open this database", systemImage: "cylinder.split.1x2", description: Text(failure))
            } else if tables.isEmpty && mode != .sql {
                ContentUnavailableView {
                    Label("No tables yet", systemImage: "tablecells")
                } description: {
                    Text("Create one in the SQL tab, or run python manage.py migrate in a Django project.")
                } actions: {
                    Button("Write SQL") { mode = .sql }
                }
            } else {
                switch mode {
                case .data: dataPane
                case .schema: schemaPane
                case .sql: sqlPane
                }
            }
        }
        .background(AppTheme.editor)
        .task(id: path) { open() }
        .sheet(item: $editing) { edit in
            RowEditor(edit: edit, columns: columns, table: selected ?? "", onSave: save, onDelete: delete)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(tables) { table in
                        Button {
                            select(table.name)
                        } label: {
                            Label("\(table.name)  (\(table.rows))", systemImage: table.kind == "view" ? "eye" : selected == table.name ? "checkmark" : "tablecells")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tablecells").foregroundStyle(AppTheme.blue)
                        Text(selected ?? "No tables")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let table = tables.first(where: { $0.name == selected }) {
                            Text("\(table.rows) row\(table.rows == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.muted)
                                .fixedSize()
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border) }
                }
                .disabled(tables.isEmpty)
                .accessibilityLabel("Table: \(selected ?? "none")")
                .accessibilityIdentifier("database-table-picker")
                Spacer(minLength: 4)
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload")
                Menu {
                    Button("Open in the terminal", systemImage: "terminal") {
                        model.panel = .terminal
                        model.runTerminal("sqlite3 \(shellQuoted(path))")
                    }
                    ShareLink(item: model.fileURL(path)) { Label("Share file", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Database actions")
            }
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("database-mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.rail)
    }

    // MARK: Data

    private var editableTable: Bool {
        tables.first { $0.name == selected }?.kind == "table"
    }

    private var dataPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                TextField("Filter rows", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { loadRows() }
                if !filter.isEmpty {
                    Button { filter = ""; loadRows() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(AppTheme.muted)
                        .accessibilityLabel("Clear filter")
                }
                if editableTable {
                    Button {
                        editing = RowEdit(rowID: nil, fields: [:], nulls: Set(columns.filter { $0.primaryKey }.map(\.name)))
                    } label: { Label("Add row", systemImage: "plus") }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("database-add-row")
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(AppTheme.border).frame(height: 1)
            if let failure {
                Text(failure).font(.system(size: 13, design: .monospaced)).foregroundStyle(AppTheme.coralInk).padding(12)
            }
            ResultGrid(result: result, onTap: editableTable ? { index in startEditing(index) } : nil)
            let total = tables.first { $0.name == selected }?.rows ?? 0
            if filter.isEmpty, result.rows.count < total, result.rows.count == pageSize {
                Button("Show \(min(pageSize, total - result.rows.count)) more of \(total)") {
                    pageSize += 100
                    loadRows()
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(10)
            }
        }
    }

    // MARK: Schema

    private var schemaPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let table = tables.first(where: { $0.name == selected }) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(columns) { column in
                            HStack(spacing: 8) {
                                Image(systemName: column.primaryKey ? "key.fill" : "circle.fill")
                                    .font(.system(size: column.primaryKey ? 11 : 5))
                                    .foregroundStyle(column.primaryKey ? AppTheme.amber : AppTheme.muted)
                                    .frame(width: 14)
                                Text(column.name).font(.system(size: 14, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text(column.type.isEmpty ? "any" : column.type)
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(AppTheme.violet)
                                if column.notNull {
                                    Text("NOT NULL").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.muted)
                                }
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            Rectangle().fill(AppTheme.border).frame(height: 1)
                        }
                    }
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border) }
                    Text("CREATE statement").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
                    Text(table.sql)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
        }
    }

    // MARK: SQL

    private var sqlPane: some View {
        VStack(spacing: 0) {
            TextEditor(text: $query)
                .font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 160)
                .padding(8)
                .background(AppTheme.panel)
                .overlay(alignment: .topLeading) {
                    if query.isEmpty {
                        Text("select * from \(selected ?? "table") limit 20;")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("database-sql")
            HStack {
                if let queryMessage {
                    Text(queryMessage)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(queryResult == nil ? AppTheme.coralInk : AppTheme.muted)
                        .lineLimit(3)
                }
                Spacer()
                Button {
                    runQuery()
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.onRun)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(AppTheme.run, in: Capsule())
                }
                .buttonStyle(.app)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("database-run")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Rectangle().fill(AppTheme.border).frame(height: 1)
            if let queryResult, queryResult.isQuery {
                ResultGrid(result: queryResult, onTap: nil)
            } else {
                Spacer()
            }
        }
    }

    // MARK: Actions

    private func open() {
        do {
            database = try SQLiteDatabase(url: model.fileURL(path))
            failure = nil
            reload()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func reload() {
        guard let database else { return }
        do {
            tables = try database.tables()
            if selected == nil || !tables.contains(where: { $0.name == selected }) {
                selected = tables.first(where: { !$0.name.hasPrefix("django_") && !$0.name.hasPrefix("auth_") })?.name ?? tables.first?.name
            }
            failure = nil
            loadRows()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func select(_ name: String) {
        selected = name
        filter = ""
        pageSize = 100
        loadRows()
    }

    private func loadRows() {
        guard let database, let table = selected else { return }
        do {
            columns = try database.columns(of: table)
            let quoted = SQLiteDatabase.quote(table)
            let isTable = tables.first { $0.name == table }?.kind == "table"
            let selectList = isTable ? "rowid as \"__rowid\", *" : "*"
            var sql = "select \(selectList) from \(quoted)"
            var bindings: [SQLiteValue?] = []
            if !filter.isEmpty, !columns.isEmpty {
                sql += " where " + columns.map { "cast(\(SQLiteDatabase.quote($0.name)) as text) like ?" }.joined(separator: " or ")
                bindings = Array(repeating: .text("%\(filter)%"), count: columns.count)
            }
            sql += " limit \(pageSize)"
            var loaded = try database.execute(sql, bindings: bindings)
            if isTable, loaded.columns.first == "__rowid" {
                rowIDs = loaded.rows.map { if case let .integer(id) = $0.first { return id } else { return nil } }
                loaded.columns.removeFirst()
                loaded.rows = loaded.rows.map { Array($0.dropFirst()) }
            } else {
                rowIDs = []
            }
            result = loaded
            failure = nil
        } catch {
            // A table WITHOUT ROWID has no rowid to select; show it read-only.
            if let plain = try? database.execute("select * from \(SQLiteDatabase.quote(table)) limit \(pageSize)") {
                result = plain
                rowIDs = []
                failure = nil
            } else {
                failure = error.localizedDescription
            }
        }
    }

    private func runQuery() {
        guard let database else { return }
        do {
            let ran = try database.execute(query)
            queryResult = ran
            queryMessage = ran.isQuery ? "\(ran.rows.count) row\(ran.rows.count == 1 ? "" : "s")\(ran.rows.count == 1000 ? " (first 1000)" : "")" : "Done. \(ran.changes) row\(ran.changes == 1 ? "" : "s") changed."
            tables = (try? database.tables()) ?? tables
            loadRows()
            model.reloadTree()
        } catch {
            queryResult = nil
            queryMessage = error.localizedDescription
        }
    }

    private func startEditing(_ index: Int) {
        guard index < result.rows.count else { return }
        let row = result.rows[index]
        var fields: [String: String] = [:]
        var nulls = Set<String>()
        for (column, value) in zip(result.columns, row) {
            // A blob cannot be typed in; leaving it out keeps it as it is.
            if case .blob = value { continue }
            fields[column] = value.editable
            if value == .null { nulls.insert(column) }
        }
        editing = RowEdit(rowID: index < rowIDs.count ? rowIDs[index] : nil, fields: fields, nulls: nulls)
    }

    private func typed(_ text: String, for column: SQLiteColumn) -> SQLiteValue {
        let type = column.type.uppercased()
        if type.contains("INT"), let number = Int64(text) { return .integer(number) }
        if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") || type.contains("NUM") || type.contains("DEC"),
           let number = Double(text) { return .real(number) }
        if type.contains("BOOL"), let number = Int64(text) { return .integer(number) }
        return .text(text)
    }

    private func save(_ edit: RowEdit) -> String? {
        guard let database, let table = selected else { return "No table" }
        let quoted = SQLiteDatabase.quote(table)
        let used = columns.filter { edit.fields[$0.name] != nil || edit.nulls.contains($0.name) }
        let values: [SQLiteValue?] = used.map { column in
            edit.nulls.contains(column.name) ? .null : typed(edit.fields[column.name] ?? "", for: column)
        }
        do {
            if let rowID = edit.rowID {
                let assignments = used.map { "\(SQLiteDatabase.quote($0.name)) = ?" }.joined(separator: ", ")
                _ = try database.execute("update \(quoted) set \(assignments) where rowid = ?", bindings: values + [.integer(rowID)])
            } else {
                let names = used.map { SQLiteDatabase.quote($0.name) }.joined(separator: ", ")
                let marks = Array(repeating: "?", count: used.count).joined(separator: ", ")
                _ = try database.execute(used.isEmpty ? "insert into \(quoted) default values" : "insert into \(quoted) (\(names)) values (\(marks))", bindings: values)
            }
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func delete(_ edit: RowEdit) -> String? {
        guard let database, let table = selected, let rowID = edit.rowID else { return "This row cannot be deleted here" }
        do {
            _ = try database.execute("delete from \(SQLiteDatabase.quote(table)) where rowid = ?", bindings: [.integer(rowID)])
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func shellQuoted(_ text: String) -> String {
        text.contains(where: { " '\"$\\".contains($0) }) ? "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" : text
    }
}

/// Rows and columns, scrolled both ways, with numbers to the right and NULL
/// told apart from an empty string.
private struct ResultGrid: View {
    let result: SQLiteResult
    let onTap: ((Int) -> Void)?

    private var widths: [CGFloat] {
        result.columns.indices.map { index in
            let longest = max(result.columns[index].count, result.rows.prefix(200).map { min($0[index].display.count, 40) }.max() ?? 0)
            return min(max(CGFloat(longest) * 8.4 + 20, 56), 360)
        }
    }

    var body: some View {
        if result.columns.isEmpty {
            Spacer()
        } else if result.rows.isEmpty {
            VStack { headerRow; Text("No rows").foregroundStyle(AppTheme.muted).padding(20); Spacer() }
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: headerRow) {
                        ForEach(result.rows.indices, id: \.self) { index in
                            row(index)
                        }
                    }
                }
            }
            .defaultScrollAnchor(.topLeading)
            .accessibilityIdentifier("database-grid")
        }
    }

    private func numeric(_ column: Int) -> Bool {
        let values = result.rows.prefix(200).map { $0[column] }.filter { $0 != .null }
        return !values.isEmpty && values.allSatisfy(\.isNumber)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(result.columns.indices, id: \.self) { index in
                Text(result.columns[index])
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .frame(width: widths[index], alignment: numeric(index) ? .trailing : .leading)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: 34)
        .background(AppTheme.rail)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    private func row(_ index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(result.columns.indices, id: \.self) { column in
                let value = result.rows[index][column]
                Text(value.display.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13, design: .monospaced))
                    .italic(value == .null)
                    .foregroundStyle(value == .null ? AppTheme.muted : value.isNumber ? AppTheme.blue : AppTheme.primary)
                    .lineLimit(1)
                    .frame(width: widths[column], alignment: value.isNumber ? .trailing : .leading)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: 34)
        .background(index.isMultiple(of: 2) ? AppTheme.editor : AppTheme.panel)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(index) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }
}

/// Edits one row; a NULL switch per column keeps NULL apart from empty text.
private struct RowEditor: View {
    @State var edit: DatabaseView.RowEdit
    let columns: [SQLiteColumn]
    let table: String
    let onSave: (DatabaseView.RowEdit) -> String?
    let onDelete: (DatabaseView.RowEdit) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Text(failure).foregroundStyle(AppTheme.coralInk).font(.system(size: 13, design: .monospaced))
                }
                ForEach(columns) { column in
                    Section {
                        HStack {
                            TextField(edit.nulls.contains(column.name) ? "NULL" : column.type, text: Binding(
                                get: { edit.fields[column.name] ?? "" },
                                set: { edit.fields[column.name] = $0; edit.nulls.remove(column.name) }
                            ), axis: .vertical)
                            .font(.system(size: 15, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(column.type.uppercased().contains("INT") ? .numbersAndPunctuation : .default)
                            Toggle("NULL", isOn: Binding(
                                get: { edit.nulls.contains(column.name) },
                                set: { if $0 { edit.nulls.insert(column.name); edit.fields[column.name] = "" } else { edit.nulls.remove(column.name) } }
                            ))
                            .toggleStyle(.button)
                            .font(.system(size: 12, weight: .semibold))
                        }
                    } header: {
                        Text(column.name + (column.primaryKey ? "  ·  primary key" : "") + (column.type.isEmpty ? "" : "  ·  \(column.type)"))
                    }
                }
                if edit.rowID != nil {
                    Section {
                        Button("Delete row", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(edit.rowID == nil ? "New row in \(table)" : "Edit row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let message = onSave(edit) { failure = message } else { dismiss() }
                    }
                    .accessibilityIdentifier("database-save-row")
                }
            }
            .confirmationDialog("Delete this row?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let message = onDelete(edit) { failure = message } else { dismiss() }
                }
            }
        }
    }
}
