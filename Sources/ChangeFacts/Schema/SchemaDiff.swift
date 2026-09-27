//
//  SchemaDiff.swift
//  ChangeFacts
//
//  What changed between two schemas, as facts a reviewer can hold against a migration.
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What changed between two schemas, as facts a reviewer can hold against a migration: tables
/// and columns added or removed (a removal is where data goes), types and nullability changed
/// (a caution — data may or may not survive), keys and indexes added or removed. Matched by
/// name; a rename reads as a removal and an addition, which is what the database does too.
public enum SchemaDiff {
    /// How much a fact can cost: data lost, data possibly lost, or nothing lost.
    public enum Severity: Sendable, Equatable { case destructive, caution, info }
    /// What changed, one case per kind of fact.
    public enum Kind: Sendable, Equatable {
        case tableRemoved, tableAdded
        case columnRemoved, columnAdded, typeChanged, nullabilityChanged, keyChanged
        case foreignKeyRemoved, foreignKeyAdded
        case indexRemoved, indexAdded
    }
    /// One change between the schemas.
    public struct Fact: Equatable, Sendable {
        /// What changed.
        public let kind: Kind
        /// How much it can cost.
        public let severity: Severity
        /// The fact as a phrase, e.g. "column users.bio removed".
        public let summary: String

        /// Creates a fact.
        public init(kind: Kind, severity: Severity, summary: String) {
            self.kind = kind
            self.severity = severity
            self.summary = summary
        }
    }

    /// Every fact between two models, tables matched by case-insensitive name.
    public static func compare(old: SchemaModel, new: SchemaModel) -> [Fact] {
        var facts: [Fact] = []
        let oldTables = Dictionary(uniqueKeysWithValues: old.tables.map { ($0.name.lowercased(), $0) })
        let newTables = Dictionary(uniqueKeysWithValues: new.tables.map { ($0.name.lowercased(), $0) })
        for t in old.tables where newTables[t.name.lowercased()] == nil { facts.append(Fact(kind: .tableRemoved, severity: .destructive, summary: String(localized: "table \(t.name) removed (\(t.columns.count) columns)", bundle: .module, comment: "Schema change: a table name, then how many columns it had"))) }
        for t in new.tables where oldTables[t.name.lowercased()] == nil { facts.append(Fact(kind: .tableAdded, severity: .info, summary: String(localized: "table \(t.name) added (\(t.columns.count) columns)", bundle: .module, comment: "Schema change: a table name, then how many columns it has"))) }
        for t in new.tables {
            guard let o = oldTables[t.name.lowercased()] else { continue }
            let oldCols = Dictionary(uniqueKeysWithValues: o.columns.map { ($0.name.lowercased(), $0) })
            let newCols = Dictionary(uniqueKeysWithValues: t.columns.map { ($0.name.lowercased(), $0) })
            for c in o.columns where newCols[c.name.lowercased()] == nil { facts.append(Fact(kind: .columnRemoved, severity: .destructive, summary: String(localized: "column \(t.name).\(c.name) removed", bundle: .module, comment: "Schema change: table.column"))) }
            for c in t.columns where oldCols[c.name.lowercased()] == nil {
                let type = typeName(c.type)
                let summary = c.notNull
                    ? String(localized: "column \(t.name).\(c.name) added (\(type), NOT NULL)", bundle: .module, comment: "Schema change: table.column, then its SQL type; NOT NULL is SQL and stays as is")
                    : String(localized: "column \(t.name).\(c.name) added (\(type))", bundle: .module, comment: "Schema change: table.column, then its SQL type")
                facts.append(Fact(kind: .columnAdded, severity: .info, summary: summary))
            }
            for c in t.columns {
                guard let oc = oldCols[c.name.lowercased()] else { continue }
                if oc.type.lowercased() != c.type.lowercased() { facts.append(Fact(kind: .typeChanged, severity: .caution, summary: String(localized: "column \(t.name).\(c.name) type \(typeName(oc.type)) → \(typeName(c.type))", bundle: .module, comment: "Schema change: table.column, then its old SQL type → new SQL type"))) }
                if oc.notNull != c.notNull { facts.append(Fact(kind: .nullabilityChanged, severity: c.notNull ? .caution : .info, summary: c.notNull
                    ? String(localized: "column \(t.name).\(c.name) now NOT NULL", bundle: .module, comment: "Schema change: table.column now rejects empty values; NOT NULL is SQL and stays as is")
                    : String(localized: "column \(t.name).\(c.name) now nullable", bundle: .module, comment: "Schema change: table.column now accepts empty (NULL) values"))) }
                if oc.pk != c.pk { facts.append(Fact(kind: .keyChanged, severity: .caution, summary: c.pk
                    ? String(localized: "column \(t.name).\(c.name) is now the primary key", bundle: .module, comment: "Schema change: table.column")
                    : String(localized: "column \(t.name).\(c.name) no longer the primary key", bundle: .module, comment: "Schema change: table.column"))) }
            }
            for fk in o.foreignKeys where !t.foreignKeys.contains(fk) { facts.append(Fact(kind: .foreignKeyRemoved, severity: .caution, summary: String(localized: "foreign key \(t.name).\(fk.column) → \(fk.toTable).\(fk.toColumn) removed", bundle: .module, comment: "Schema change: table.column → referenced table.column"))) }
            for fk in t.foreignKeys where !o.foreignKeys.contains(fk) { facts.append(Fact(kind: .foreignKeyAdded, severity: .info, summary: String(localized: "foreign key \(t.name).\(fk.column) → \(fk.toTable).\(fk.toColumn) added", bundle: .module, comment: "Schema change: table.column → referenced table.column"))) }
            let oldIdx = Set(o.indexes.map { "\($0.unique)|\($0.columns.joined(separator: ","))" })
            let newIdx = Set(t.indexes.map { "\($0.unique)|\($0.columns.joined(separator: ","))" })
            for i in o.indexes where !newIdx.contains("\(i.unique)|\(i.columns.joined(separator: ","))") {
                let cols = i.columns.joined(separator: ", ")
                facts.append(Fact(kind: .indexRemoved, severity: .info, summary: i.unique
                    ? String(localized: "unique index on \(t.name)(\(cols)) removed", bundle: .module, comment: "Schema change: table(columns)")
                    : String(localized: "index on \(t.name)(\(cols)) removed", bundle: .module, comment: "Schema change: table(columns)")))
            }
            for i in t.indexes where !oldIdx.contains("\(i.unique)|\(i.columns.joined(separator: ","))") {
                let cols = i.columns.joined(separator: ", ")
                facts.append(Fact(kind: .indexAdded, severity: .info, summary: i.unique
                    ? String(localized: "unique index on \(t.name)(\(cols)) added", bundle: .module, comment: "Schema change: table(columns)")
                    : String(localized: "index on \(t.name)(\(cols)) added", bundle: .module, comment: "Schema change: table(columns)")))
            }
        }
        return facts
    }

    /// A column's declared type, or "untyped" when it declares none.
    private static func typeName(_ type: String) -> String {
        type.isEmpty ? String(localized: "untyped", bundle: .module, comment: "Schema change: stands in for a column's SQL type when it declares none") : type
    }

    /// "Schema: 1 table removed, 2 columns removed, 1 type change, 1 index added".
    public static func headline(_ facts: [Fact]) -> String? {
        guard !facts.isEmpty else { return nil }
        var parts: [String] = []
        func count(_ kinds: [Kind], _ phrase: (Int) -> String) {
            let n = facts.filter { kinds.contains($0.kind) }.count
            if n > 0 { parts.append(phrase(n)) }
        }
        count([.tableRemoved]) { String(localized: "\($0) tables removed", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.tableAdded]) { String(localized: "\($0) tables added", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.columnRemoved]) { String(localized: "\($0) columns removed", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.columnAdded]) { String(localized: "\($0) columns added", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.typeChanged]) { String(localized: "\($0) type changes", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.nullabilityChanged]) { String(localized: "\($0) nullability changes", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.keyChanged]) { String(localized: "\($0) key changes", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.foreignKeyRemoved, .foreignKeyAdded]) { String(localized: "\($0) foreign key changes", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        count([.indexRemoved, .indexAdded]) { String(localized: "\($0) index changes", bundle: .module, comment: "Schema summary clause on a changed schema file; the argument is a count") }
        let clauses = parts.joined(separator: ", ")
        return String(localized: "Schema: \(clauses)", bundle: .module,
                      comment: "Headline on a changed schema file; the argument is a comma-separated list of counted changes")
    }

    /// The badge's tool tip: the headline, then every fact.
    public static func tooltip(_ facts: [Fact]) -> String? {
        guard let head = headline(facts) else { return nil }
        var list = facts.prefix(12).map(\.summary).joined(separator: "; ")
        if facts.count > 12 {
            list = String(localized: "\(list); and \(facts.count - 12) more", bundle: .module,
                          comment: "A shortened list: the first argument is a semicolon-separated list of changes, the second how many more were left out")
        }
        return head + " — " + list
    }

    /// The facts between two texts of the same schema file; empty when either is not a schema
    /// (a file that stopped defining tables is a removal of all of them, which is reported).
    public static func facts(oldText: String?, newText: String, path: String) -> [Fact] {
        guard SchemaModel.isSchemaPath(path) else { return [] }
        let new = SchemaModel.load(text: newText, path: path)
        let old = (oldText?.isEmpty ?? true) ? nil : SchemaModel.load(text: oldText!, path: path)
        guard old != nil || new != nil else { return [] }
        return compare(old: old ?? SchemaModel(tables: []), new: new ?? SchemaModel(tables: []))
    }

}
