//
//  SchemaModel.swift
//  ChangeFacts
//
//  A schema as structure — tables, columns, keys, indexes — and the diff of two of them as facts.
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import SQLiteReader

/// A schema as STRUCTURE, built by running its DDL (SQL as written, or what `SchemaDDL` makes
/// of a Prisma / Rails / Django file) into an in-memory SQLite one statement at a time — a
/// statement SQLite cannot take (`CREATE EXTENSION`, an `ALTER … ADD CONSTRAINT`) is skipped,
/// not fatal, so a Postgres schema still yields its tables. Types are the declared strings.
public struct SchemaModel: Equatable, Sendable {
    /// A column: its declared type string, NOT NULL, and whether it is in the primary key.
    public struct Column: Equatable, Sendable { public let name: String; public let type: String; public let notNull: Bool; public let pk: Bool; public init(name: String, type: String, notNull: Bool, pk: Bool) { self.name = name; self.type = type; self.notNull = notNull; self.pk = pk } }
    /// A foreign key from one column of this table to a column of `toTable`.
    public struct ForeignKey: Equatable, Sendable { public let column: String; public let toTable: String; public let toColumn: String; public init(column: String, toTable: String, toColumn: String) { self.column = column; self.toTable = toTable; self.toColumn = toColumn } }
    /// A `CREATE INDEX` or `UNIQUE` constraint; a constraint is named `unique(col, …)`.
    public struct Index: Equatable, Sendable { public let name: String; public let columns: [String]; public let unique: Bool; public init(name: String, columns: [String], unique: Bool) { self.name = name; self.columns = columns; self.unique = unique } }
    /// One table with its columns in declaration order, foreign keys, and indexes sorted by name.
    public struct Table: Equatable, Sendable {
        /// The table's name as declared.
        public let name: String
        /// The columns in declaration order.
        public let columns: [Column]
        /// The foreign keys SQLite reports for the table.
        public let foreignKeys: [ForeignKey]
        /// Indexes on plain columns (not expressions), sorted by name.
        public let indexes: [Index]
       ; public init(name: String, columns: [Column], foreignKeys: [ForeignKey], indexes: [Index]) { self.name = name; self.columns = columns; self.foreignKeys = foreignKeys; self.indexes = indexes }
    }
    /// Every table the DDL defined.
    public let tables: [Table]

    /// Creates a model from already-built tables.
    public init(tables: [Table]) { self.tables = tables }

    /// Files this reads: SQL, and what `SchemaDDL` reads.
    public static func isSchemaPath(_ path: String) -> Bool {
        SchemaDDL.isSchemaFile(path) || ["sql", "ddl", "psql", "pgsql", "mysql"].contains((path as NSString).pathExtension.lowercased())
    }

    /// The model of `text` read as `path`; nil when it is not a schema file or defines no table.
    public static func load(text: String, path: String) -> SchemaModel? {
        let ddl: String
        if let made = SchemaDDL.ddl(for: text, path: path) { ddl = made }
        else if isSchemaPath(path) { ddl = text }
        else { return nil }
        let model = load(ddl: ddl)
        return model.tables.isEmpty ? nil : model
    }

    /// The model the DDL builds, statement by statement.
    public static func load(ddl: String) -> SchemaModel {
        guard let db = SQLiteDB(sql: ddl) else { return SchemaModel(tables: []) }   // one statement at a time, failures skipped
        var tables: [Table] = []
        for name in db.tables() {
            let columns = db.schema(name).map { Column(name: $0.name, type: $0.type, notNull: $0.notNull, pk: $0.pk) }
            let fks = db.foreignKeys(name).map { ForeignKey(column: $0.from, toTable: $0.toTable, toColumn: $0.toColumn) }
            var indexes: [Index] = []
            for row in db.run("PRAGMA index_list(\(SQLiteDB.quoteIdentifier(name)))").rows where row.count >= 4 {
                // seq, name, unique, origin (c = CREATE INDEX, u = UNIQUE constraint, pk)
                guard row[3] == "c" || row[3] == "u" else { continue }
                let cols = db.run("PRAGMA index_info(\(SQLiteDB.quoteIdentifier(row[1])))").rows.compactMap { $0.count >= 3 ? $0[2] : nil }
                guard !cols.isEmpty, !cols.contains("NULL"), !cols.contains("") else { continue }   // an index on an expression, not a column
                let indexName = row[3] == "u" ? "unique(\(cols.joined(separator: ", ")))" : row[1]
                indexes.append(Index(name: indexName, columns: cols, unique: row[2] == "1"))
            }
            tables.append(Table(name: name, columns: columns, foreignKeys: fks, indexes: indexes.sorted { $0.name < $1.name }))
        }
        return SchemaModel(tables: tables)
    }

    /// The script's statements, as the reader splits them (quotes, comments, trigger bodies).
    public static func statements(in ddl: String) -> [String] { SQLiteDB.statements(in: ddl) }
}

