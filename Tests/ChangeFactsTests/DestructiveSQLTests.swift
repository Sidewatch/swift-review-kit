//
//  DestructiveSQLTests.swift
//  ChangeFactsTests
//
//  The SQL forms, the comment and literal rules per dialect, added-lines-only, the skips, the
//  migration DSLs against fixture files, and the diff-chunk marks.
//  Every case is mutation-verified.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import XCTest
@testable import ChangeFacts

final class DestructiveSQLTests: XCTestCase {
    typealias F = DestructiveSQL.Finding

    private func sql(_ text: String, _ path: String = "migrations/x.sql", added: Set<Int>? = nil) -> [String] {
        DestructiveSQL.findings(in: text, path: path, addedLines: added).map { "\($0.line):\($0.severity == .destructive ? "D" : "C"):\($0.summary)" }
    }
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/migrations/" + name, withExtension: nil), "fixture \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDropTableNamesTheTable() {
        XCTAssertEqual(sql("DROP TABLE users;"), ["1:D:DROP TABLE users"])
        XCTAssertEqual(sql("drop table if exists \"public\".\"x\";"), ["1:D:DROP TABLE public.x"])
    }

    func testCommentsAndLiteralsAreNotStatements() {
        XCTAssertTrue(sql("-- DROP TABLE users;\nSELECT 1;").isEmpty)
        XCTAssertTrue(sql("/* DELETE FROM users;\n */ SELECT 1;").isEmpty)
        XCTAssertTrue(sql("# drop_table :users\nadd_column :users, :x, :string", "db/migrate/1_x.rb").isEmpty)
        XCTAssertTrue(sql("// await knex.schema.dropTable('users')\nfoo()", "migrations/1.js").filter { !$0.contains("no down") }.isEmpty)
        XCTAssertTrue(sql("INSERT INTO t (body) VALUES ('please run DROP TABLE x'), ('DELETE FROM y');").isEmpty, "a literal in a .sql file is data")
    }

    func testWhereConditionsOnTheSameOrNextLine() {
        XCTAssertTrue(sql("DELETE FROM sessions WHERE expires_at < now();").isEmpty)
        XCTAssertTrue(sql("DELETE FROM sessions\n  WHERE user_id IS NULL;").isEmpty)
        XCTAssertTrue(sql("UPDATE users\n   SET last_seen = NOW()\n WHERE id = 42;").isEmpty)
        XCTAssertEqual(sql("SELECT 1;\nDELETE FROM login_attempts;\nUPDATE users SET plan = 'free';\nDELETE FROM carts WHERE 1=1;"),
                       ["2:D:DELETE without WHERE on login_attempts", "3:D:UPDATE without WHERE on users", "4:D:DELETE WHERE 1=1 on carts"])
    }

    func testTheOtherFormsAndWhatLosesNoRows() {
        XCTAssertEqual(sql("TRUNCATE TABLE analytics_events;"), ["1:D:TRUNCATE analytics_events"])
        XCTAssertEqual(sql("DROP DATABASE app_dev;"), ["1:D:DROP DATABASE app_dev"])
        XCTAssertEqual(sql("ALTER TABLE users DROP COLUMN bio;"), ["1:D:DROP COLUMN users.bio"])
        XCTAssertEqual(sql("ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(120);"), ["1:C:column type changed: users.email"])
        XCTAssertEqual(sql("ALTER TABLE users MODIFY COLUMN age VARCHAR(8);"), ["1:C:column type changed: users.age"])
        XCTAssertTrue(sql("DROP INDEX idx_users_email;").isEmpty)
        XCTAssertTrue(sql("ALTER TABLE users DROP CONSTRAINT users_pkey;").isEmpty)
    }

    func testCaseAndCRLF() {
        XCTAssertEqual(sql("delete from t;"), ["1:D:DELETE without WHERE on t"])
        XCTAssertEqual(sql("SELECT 1;\r\nSELECT 2;\r\nDROP TABLE t;\r\n"), ["3:D:DROP TABLE t"])
    }

    func testAddedLinesOnly() {
        XCTAssertTrue(sql("DELETE FROM t\n WHERE id = 1;", added: [2]).isEmpty, "a WHERE added under an old DELETE conditions it")
        XCTAssertEqual(sql("DROP TABLE a;\nDROP TABLE b;", added: [2]), ["2:D:DROP TABLE b"])
        XCTAssertTrue(sql("DELETE FROM t\n;\nSELECT 1;", added: [3]).isEmpty)
    }

    func testProseDataTestsAndVendoredTreesAreNeverScanned() {
        XCTAssertTrue(sql("DROP TABLE users", "docs/README.md").isEmpty)
        XCTAssertTrue(sql("DROP TABLE users", "fixtures/x.json").isEmpty)
        XCTAssertTrue(sql("DROP TABLE users;", "app/tests/schema.sql").isEmpty)
        XCTAssertTrue(sql("DROP TABLE users;", "src/db.test.js").isEmpty)
        XCTAssertTrue(sql("DROP TABLE users;", "node_modules/pg/x.sql").isEmpty)
        XCTAssertNil(DestructiveSQL.dialect(forPath: "x.yaml"))
    }

    func testADumpIsOneFinding() throws {
        XCTAssertEqual(sql(try fixture("dump.sql"), "backups/dump.sql"), ["1:D:database dump (3 DROP TABLE)"])
    }

    func testMigrationDSLsAgainstTheFixtures() throws {
        XCTAssertEqual(sql(try fixture("20260920120000_remove_profile_fields.rb"), "db/migrate/20260920120000_remove_profile_fields.rb"),
                       ["1:C:no down migration", "3:D:remove_column users.bio", "4:C:column type changed: users.age", "5:D:drop_table legacy_profiles", "7:D:DELETE without WHERE on sessions"])
        XCTAssertEqual(sql(try fixture("0007_delete_profile.py"), "accounts/migrations/0007_delete_profile.py"),
                       ["8:D:RemoveField profile.bio", "9:C:column type changed: profile.age", "10:D:DeleteModel LegacyProfile", "11:D:UPDATE without WHERE on accounts_profile"])
        XCTAssertEqual(sql(try fixture("alembic/versions/ab12cd34_drop_bio.py"), "alembic/versions/ab12cd34_drop_bio.py"),
                       ["1:C:downgrade is a pass", "13:D:op.drop_column profiles.bio", "14:C:column type changed: profiles.age"])
        XCTAssertEqual(sql(try fixture("20260920_drop_legacy.js"), "migrations/20260920_drop_legacy.js"),
                       ["1:C:no down migration", "3:D:dropTable legacy_profiles", "5:D:dropColumn bio", "8:D:DELETE without WHERE on sessions"])
        XCTAssertEqual(sql(try fixture("2026_09_20_000000_drop_legacy_tables.php"), "database/migrations/2026_09_20_000000_drop_legacy_tables.php"),
                       ["1:C:down migration is empty", "12:D:Schema::drop legacy_profiles", "14:D:dropColumn bio", "15:C:column type changed: age", "17:D:TRUNCATE analytics_events"])
        XCTAssertEqual(sql(try fixture("prisma/20260920_remove_legacy/migration.sql"), "prisma/migrations/20260920_remove_legacy/migration.sql"),
                       ["4:D:DROP COLUMN User.legacyId", "5:C:column type changed: User.email", "10:D:DROP TABLE LegacyProfile"])
    }

    func testEctoAndEFCoreForms() {
        XCTAssertEqual(sql("drop table(:users)\nremove :bio\nmodify :age, :string", "priv/repo/migrations/1_x.exs"),
                       ["1:D:drop table users", "2:D:remove :bio", "3:C:column type changed: age"])
        XCTAssertEqual(sql("migrationBuilder.DropTable(name: \"Users\");\nmigrationBuilder.DropColumn(name: \"Bio\", table: \"Users\");\nmigrationBuilder.AlterColumn<string>(name: \"Age\", table: \"Users\");", "Migrations/1_X.cs"),
                       ["1:D:DropTable Users", "2:D:DropColumn Bio", "3:C:column type changed: Age"])
    }

    func testTooltipLeadsWithTheWorstSeverity() {
        XCTAssertEqual(DestructiveSQL.tooltip(for: [F(line: 4, endLine: 4, severity: .caution, summary: "column type changed: a.b"), F(line: 9, endLine: 9, severity: .destructive, summary: "DROP TABLE t")]),
                       "Destructive SQL added — line 4: column type changed: a.b; line 9: DROP TABLE t")
        XCTAssertTrue(DestructiveSQL.tooltip(for: [F(line: 4, endLine: 4, severity: .caution, summary: "x")])?.hasPrefix("SQL caution added") == true)
        XCTAssertNil(DestructiveSQL.tooltip(for: []))
    }

    func testDiffChunkMarksSitOnTheStatementsOwnVisibleLine() {
        let chunk = ["diff --git a/db/cleanup.sql b/db/cleanup.sql", "index 1..2 100644", "--- a/db/cleanup.sql", "+++ b/db/cleanup.sql",
                     "@@ -1,4 +1,6 @@", " DELETE FROM sessions", "+ WHERE user_id IS NULL;", "-DROP TABLE users;", "+-- DROP TABLE users;",
                     "+DELETE FROM login_attempts;", " SELECT 1;"]
        let marks = DestructiveSQL.marks(forChunk: chunk, path: "db/cleanup.sql")
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[5]?.summary, "DELETE without WHERE on login_attempts", "not the WHERE completing an old DELETE, not the removed DROP, not the comment")
    }
}
