//
//  SchemaTests.swift
//  ChangeFactsTests
//
//  The same data model read three ways (Prisma, Rails schema.rb, Django models.py) into one
//  structure, the tolerant DDL build, and the diff's facts, severities and headline.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ChangeFacts

final class SchemaTests: XCTestCase {
    private func read(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/schemas/" + name, withExtension: nil), "fixture \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func table(_ m: SchemaModel?, _ name: String) -> SchemaModel.Table? { m?.tables.first { $0.name.lowercased() == name.lowercased() } }
    private func col(_ t: SchemaModel.Table?, _ name: String) -> SchemaModel.Column? { t?.columns.first { $0.name.lowercased() == name.lowercased() } }

    func testPrisma() throws {
        let prisma = SchemaModel.load(text: try read("schema.prisma"), path: "prisma/schema.prisma")
        let users = table(prisma, "users"), profiles = table(prisma, "profiles"), posts = table(prisma, "posts"), tag = table(prisma, "Tag")
        XCTAssertEqual(prisma?.tables.count, 4, "four models become tables under their @@map names, Tag under its own")
        XCTAssertEqual(col(users, "id")?.pk, true); XCTAssertEqual(col(users, "id")?.type, "TEXT")
        XCTAssertEqual(col(users, "email")?.type, "VARCHAR(120)"); XCTAssertEqual(col(users, "email")?.notNull, true)
        XCTAssertEqual(col(users, "name")?.notNull, false); XCTAssertEqual(col(users, "role")?.type, "TEXT")
        XCTAssertEqual(col(users, "legacy_id")?.type, "INTEGER"); XCTAssertEqual(col(users, "legacy_id")?.notNull, false)
        XCTAssertEqual(col(users, "created_at")?.type, "DATETIME"); XCTAssertNil(col(users, "posts")); XCTAssertNil(col(users, "profile"))
        XCTAssertEqual(profiles?.foreignKeys, [SchemaModel.ForeignKey(column: "user_id", toTable: "users", toColumn: "id")])
        XCTAssertEqual(posts?.foreignKeys, [SchemaModel.ForeignKey(column: "author_id", toTable: "users", toColumn: "id")])
        XCTAssertTrue(users?.indexes.contains { $0.columns == ["created_at"] && !$0.unique } == true)
        XCTAssertTrue(posts?.indexes.contains { $0.columns == ["author_id", "title"] && $0.unique } == true)
        XCTAssertTrue(tag?.indexes.contains { $0.columns == ["label"] && $0.unique } == true)
    }

    func testRails() throws {
        let rails = SchemaModel.load(text: try read("schema.rb"), path: "db/schema.rb")
        let users = table(rails, "users"), profiles = table(rails, "profiles"), posts = table(rails, "posts")
        XCTAssertEqual(rails?.tables.count, 3, "the commented-out table is absent")
        XCTAssertEqual(col(users, "id")?.pk, true); XCTAssertEqual(col(users, "id")?.type, "BIGINT")
        XCTAssertEqual(col(users, "email")?.type, "VARCHAR(120)"); XCTAssertEqual(col(users, "email")?.notNull, true)
        XCTAssertEqual(col(users, "admin")?.type, "BOOLEAN"); XCTAssertEqual(col(users, "admin")?.notNull, true)
        XCTAssertEqual(col(users, "created_at")?.type, "DATETIME"); XCTAssertNotNil(col(profiles, "updated_at"))
        XCTAssertEqual(col(posts, "price")?.type, "DECIMAL(10,2)"); XCTAssertEqual(col(posts, "price")?.notNull, false)
        XCTAssertEqual(profiles?.foreignKeys, [SchemaModel.ForeignKey(column: "user_id", toTable: "users", toColumn: "id")])
        XCTAssertEqual(posts?.foreignKeys, [SchemaModel.ForeignKey(column: "author_id", toTable: "users", toColumn: "id")])
        XCTAssertTrue(users?.indexes.contains { $0.columns == ["email"] && $0.unique } == true)
        XCTAssertTrue(posts?.indexes.contains { $0.columns == ["author_id", "title"] && $0.unique } == true)
        XCTAssertTrue(posts?.indexes.contains { $0.columns == ["published"] && !$0.unique } == true)
    }

    func testDjango() throws {
        let django = SchemaModel.load(text: try read("models.py"), path: "accounts/models.py")
        let users = table(django, "users"), profile = table(django, "profile"), post = table(django, "post"), tag = table(django, "tag")
        XCTAssertEqual(django?.tables.count, 4, "the abstract base is not a table; its field is inherited")
        XCTAssertNil(table(django, "timestamped"))
        XCTAssertEqual(col(users, "id")?.pk, true); XCTAssertEqual(col(users, "created_at")?.type, "DATETIME")
        XCTAssertEqual(col(users, "email")?.type, "VARCHAR(120)"); XCTAssertEqual(col(users, "name")?.notNull, false); XCTAssertEqual(col(users, "is_admin")?.type, "BOOLEAN")
        XCTAssertEqual(profile?.foreignKeys, [SchemaModel.ForeignKey(column: "user_id", toTable: "users", toColumn: "id")]); XCTAssertEqual(col(profile, "user_id")?.notNull, true)
        XCTAssertEqual(post?.foreignKeys, [SchemaModel.ForeignKey(column: "author_id", toTable: "users", toColumn: "id")])
        XCTAssertNil(col(post, "tags"), "ManyToMany is not a column"); XCTAssertEqual(col(post, "price")?.type, "DECIMAL(10,2)")
        XCTAssertTrue(post?.indexes.contains { $0.columns == ["author_id", "title"] && $0.unique } == true)
        XCTAssertTrue(tag?.indexes.contains { $0.columns == ["label"] && $0.unique } == true)
    }

    func testTolerantDDL() {
        let postgres = "CREATE EXTENSION IF NOT EXISTS pgcrypto;\nCREATE TABLE a (id serial primary key, note text default 'x;y');\n-- a comment; with a semicolon\nALTER TABLE a ADD CONSTRAINT fk FOREIGN KEY (b) REFERENCES c(id);\nCREATE TABLE b (id int);\n"
        let tolerant = SchemaModel.load(text: postgres, path: "db/schema.sql")
        XCTAssertEqual(tolerant?.tables.map(\.name), ["a", "b"], "a rejected statement in the middle loses nothing after it")
        XCTAssertEqual(SchemaModel.statements(in: postgres).count, 4, "a ; inside a literal or a comment does not split")
        XCTAssertNil(SchemaModel.load(text: "SELECT 1;", path: "q.sql"), "no table, not a schema")
        XCTAssertNil(SchemaModel.load(text: "CREATE TABLE t (id int);", path: "notes.md"), "not a schema path")
    }

    func testTheDiff() throws {
        let original = try read("schema.prisma")
        let changed = original
            .replacingOccurrences(of: "  legacyId  Int?     @map(\"legacy_id\")\n", with: "")
            .replacingOccurrences(of: "@db.VarChar(120)", with: "@db.VarChar(80)")
            .replacingOccurrences(of: "  published Boolean  @default(false)\n", with: "  published Boolean  @default(false)\n  views     Int      @default(0)\n")
            .replacingOccurrences(of: "  @@index([createdAt])\n", with: "")
        var withoutTag = changed
        if let r = withoutTag.range(of: "model Tag {") { withoutTag = String(withoutTag[..<r.lowerBound]) }
        let old = try XCTUnwrap(SchemaModel.load(text: original, path: "schema.prisma")), new = try XCTUnwrap(SchemaModel.load(text: withoutTag, path: "schema.prisma"))
        let facts = SchemaDiff.compare(old: old, new: new)
        let summaries = facts.map { "\($0.severity):\($0.summary)" }
        XCTAssertTrue(summaries.contains("destructive:table Tag removed (2 columns)"))
        XCTAssertTrue(summaries.contains("destructive:column users.legacy_id removed"))
        XCTAssertTrue(summaries.contains("caution:column users.email type VARCHAR(120) → VARCHAR(80)"))
        XCTAssertTrue(summaries.contains("info:column posts.views added (INTEGER, NOT NULL)"))
        XCTAssertTrue(summaries.contains("info:index on users(created_at) removed"))
        XCTAssertEqual(facts.count, 5, "\(summaries)")
        XCTAssertEqual(SchemaDiff.headline(facts), "Schema: 1 table removed, 1 column removed, 1 column added, 1 type change, 1 index change")
        XCTAssertTrue(SchemaDiff.tooltip(facts)?.contains("column users.legacy_id removed") == true)
        XCTAssertTrue(SchemaDiff.compare(old: old, new: old).isEmpty, "no change is no fact")
        XCTAssertEqual(SchemaDiff.compare(old: SchemaModel.load(ddl: "CREATE TABLE a (id int);"), new: SchemaModel.load(ddl: "CREATE TABLE b (id int);")).map(\.summary),
                       ["table a removed (1 column)", "table b added (1 column)"], "a rename reads as a removal and an addition")
        XCTAssertEqual(SchemaDiff.compare(old: SchemaModel.load(ddl: "CREATE TABLE a (id int, x text);"), new: SchemaModel.load(ddl: "CREATE TABLE a (id int, x text not null, y int references b(id));")).map(\.summary),
                       ["column a.y added (INT)", "column a.x now NOT NULL", "foreign key a.y → b.id added"])
        XCTAssertEqual(SchemaDiff.facts(oldText: "", newText: "CREATE TABLE t (id int);", path: "schema.sql").map(\.summary), ["table t added (1 column)"], "an untracked schema is all additions")
        XCTAssertTrue(SchemaDiff.facts(oldText: nil, newText: "hello", path: "notes.md").isEmpty)
    }
}
