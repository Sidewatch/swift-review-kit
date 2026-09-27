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
    public enum Severity: Sendable, Equatable { case destructive, caution, info }
    public enum Kind: Sendable, Equatable { case tableRemoved, tableAdded, columnRemoved, columnAdded, typeChanged, nullabilityChanged, keyChanged, foreignKeyRemoved, foreignKeyAdded, indexRemoved, indexAdded }
    public struct Fact: Equatable, Sendable {
        public let kind: Kind
        public let severity: Severity
        public let summary: String
       ; public init(kind: Kind, severity: Severity, summary: String) { self.kind = kind; self.severity = severity; self.summary = summary }
    }

    public static func compare(old: SchemaModel, new: SchemaModel) -> [Fact] {
        var facts: [Fact] = []
        let oldTables = Dictionary(uniqueKeysWithValues: old.tables.map { ($0.name.lowercased(), $0) })
        let newTables = Dictionary(uniqueKeysWithValues: new.tables.map { ($0.name.lowercased(), $0) })
        for t in old.tables where newTables[t.name.lowercased()] == nil { facts.append(Fact(kind: .tableRemoved, severity: .destructive, summary: "table \(t.name) removed (\(t.columns.count) columns)")) }
        for t in new.tables where oldTables[t.name.lowercased()] == nil { facts.append(Fact(kind: .tableAdded, severity: .info, summary: "table \(t.name) added (\(t.columns.count) columns)")) }
        for t in new.tables {
            guard let o = oldTables[t.name.lowercased()] else { continue }
            let oldCols = Dictionary(uniqueKeysWithValues: o.columns.map { ($0.name.lowercased(), $0) })
            let newCols = Dictionary(uniqueKeysWithValues: t.columns.map { ($0.name.lowercased(), $0) })
            for c in o.columns where newCols[c.name.lowercased()] == nil { facts.append(Fact(kind: .columnRemoved, severity: .destructive, summary: "column \(t.name).\(c.name) removed")) }
            for c in t.columns where oldCols[c.name.lowercased()] == nil { facts.append(Fact(kind: .columnAdded, severity: .info, summary: "column \(t.name).\(c.name) added (\(c.type.isEmpty ? "untyped" : c.type)\(c.notNull ? ", NOT NULL" : ""))")) }
            for c in t.columns {
                guard let oc = oldCols[c.name.lowercased()] else { continue }
                if oc.type.lowercased() != c.type.lowercased() { facts.append(Fact(kind: .typeChanged, severity: .caution, summary: "column \(t.name).\(c.name) type \(oc.type.isEmpty ? "untyped" : oc.type) → \(c.type.isEmpty ? "untyped" : c.type)")) }
                if oc.notNull != c.notNull { facts.append(Fact(kind: .nullabilityChanged, severity: c.notNull ? .caution : .info, summary: "column \(t.name).\(c.name) \(c.notNull ? "now NOT NULL" : "now nullable")")) }
                if oc.pk != c.pk { facts.append(Fact(kind: .keyChanged, severity: .caution, summary: "column \(t.name).\(c.name) \(c.pk ? "is now the primary key" : "no longer the primary key")")) }
            }
            for fk in o.foreignKeys where !t.foreignKeys.contains(fk) { facts.append(Fact(kind: .foreignKeyRemoved, severity: .caution, summary: "foreign key \(t.name).\(fk.column) → \(fk.toTable).\(fk.toColumn) removed")) }
            for fk in t.foreignKeys where !o.foreignKeys.contains(fk) { facts.append(Fact(kind: .foreignKeyAdded, severity: .info, summary: "foreign key \(t.name).\(fk.column) → \(fk.toTable).\(fk.toColumn) added")) }
            let oldIdx = Set(o.indexes.map { "\($0.unique)|\($0.columns.joined(separator: ","))" })
            let newIdx = Set(t.indexes.map { "\($0.unique)|\($0.columns.joined(separator: ","))" })
            for i in o.indexes where !newIdx.contains("\(i.unique)|\(i.columns.joined(separator: ","))") { facts.append(Fact(kind: .indexRemoved, severity: .info, summary: "\(i.unique ? "unique index" : "index") on \(t.name)(\(i.columns.joined(separator: ", "))) removed")) }
            for i in t.indexes where !oldIdx.contains("\(i.unique)|\(i.columns.joined(separator: ","))") { facts.append(Fact(kind: .indexAdded, severity: .info, summary: "\(i.unique ? "unique index" : "index") on \(t.name)(\(i.columns.joined(separator: ", "))) added")) }
        }
        return facts
    }

    /// "Schema: 1 table removed, 2 columns removed, 1 type change, 1 index added".
    public static func headline(_ facts: [Fact]) -> String? {
        guard !facts.isEmpty else { return nil }
        var parts: [String] = []
        func count(_ kinds: [Kind], _ one: String, _ many: String) {
            let n = facts.filter { kinds.contains($0.kind) }.count
            if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") }
        }
        count([.tableRemoved], "table removed", "tables removed")
        count([.tableAdded], "table added", "tables added")
        count([.columnRemoved], "column removed", "columns removed")
        count([.columnAdded], "column added", "columns added")
        count([.typeChanged], "type change", "type changes")
        count([.nullabilityChanged], "nullability change", "nullability changes")
        count([.keyChanged], "key change", "key changes")
        count([.foreignKeyRemoved, .foreignKeyAdded], "foreign key change", "foreign key changes")
        count([.indexRemoved, .indexAdded], "index change", "index changes")
        return "Schema: " + parts.joined(separator: ", ")
    }

    /// The badge's tool tip: the headline, then every fact.
    public static func tooltip(_ facts: [Fact]) -> String? {
        guard let head = headline(facts) else { return nil }
        return head + " — " + facts.prefix(12).map(\.summary).joined(separator: "; ") + (facts.count > 12 ? "; and \(facts.count - 12) more" : "")
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
