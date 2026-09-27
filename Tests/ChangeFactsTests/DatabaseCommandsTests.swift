//
//  DatabaseCommandsTests.swift
//  ChangeFactsTests
//
//  Ported from Sidewatch's --selftest-change-facts: the database commands a shell line ran, with
//  the severity the SQL or the subcommand earns.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ChangeFacts

/// Tests for `DatabaseCommands`: inline SQL is classified by `DestructiveSQL`, a fed file is
/// named, a bare session is informational, and each framework's own destructive subcommands,
/// cautions and harmless ones read as documented. `tool|D|summary` is destructive, `C` caution,
/// `-` informational.
final class DatabaseCommandsTests: XCTestCase {

    private func cmds(_ line: String) -> [String] {
        DatabaseCommands.detect(line).map { "\($0.tool)|\($0.severity.map { $0 == .destructive ? "D" : "C" } ?? "-")|\($0.summary)" }
    }

    func testPsqlInlineSQLIsClassifiedAFileIsNamedAndABareSessionIsInformational() {
        XCTAssertEqual(cmds("psql \"$DATABASE_URL\" -c \"DELETE FROM sessions\""), ["psql|D|DELETE without WHERE on sessions"])
        XCTAssertEqual(cmds("psql -c 'DELETE FROM sessions WHERE expires_at < now()'"), ["psql|-|DELETE FROM sessions WHERE expires_at < now()"])
        XCTAssertEqual(cmds("psql app -f schema.sql"), ["psql|C|runs schema.sql"])
        XCTAssertEqual(cmds("psql app_dev"), ["psql|-|opens a psql session"])
        XCTAssertEqual(cmds("psql --command=\"TRUNCATE t\""), ["psql|D|TRUNCATE t"], "--option=value")
    }

    func testWrappersArePeeledBeforeTheToolIsRead() {
        XCTAssertEqual(cmds("cd app && DATABASE_URL=postgres://x npx prisma migrate reset --force"), ["prisma|D|prisma migrate reset — drops and recreates the database"])
        XCTAssertEqual(cmds("sudo -u postgres psql -c 'TRUNCATE t'"), ["psql|D|TRUNCATE t"])
        XCTAssertEqual(cmds("bundle exec rails db:drop"), ["rails|D|rails db:drop"])
        XCTAssertEqual(cmds("docker compose exec -T db psql -U app app_dev -c 'DROP TABLE t'"), ["psql|D|DROP TABLE t"])
        XCTAssertEqual(cmds("kubectl exec pod-1 -- psql -c 'DROP TABLE t'"), ["psql|D|DROP TABLE t"])
        XCTAssertEqual(cmds("sh -c \"psql -c 'DROP TABLE t'\""), ["psql|D|DROP TABLE t"])
        XCTAssertEqual(cmds("ssh db.internal 'psql -c \"DROP TABLE t\"'"), ["psql|D|DROP TABLE t"])
    }

    func testAHeredocBodyIsTheSQLTheWorstStatementLeadsAndTheRestAreCounted() {
        XCTAssertEqual(cmds("psql app <<'SQL'\nUPDATE users SET plan = 'free';\nSELECT count(*) FROM users;\nDROP TABLE t;\nSQL"),
                       ["psql|D|UPDATE without WHERE on users (+1 more)"])
        let command = DatabaseCommands.detect("psql app <<'SQL'\nDROP TABLE t;\nSQL", timestamp: "10:42").first
        XCTAssertEqual(command?.timestamp, "10:42")
        XCTAssertEqual(command?.text, "psql app <<'SQL'\nDROP TABLE t;\nSQL", "the segment as it was run, body included")
    }

    func testTheFrameworksOwnDestructiveSubcommandsCautionsAndHarmlessOnes() {
        let cases: [(String, [String])] = [
            ("pnpm dlx prisma migrate deploy", ["prisma|-|prisma migrate deploy"]),
            ("npx prisma db push --force-reset", ["prisma|D|prisma db push --force-reset — drops and recreates the database"]),
            ("npx prisma db push --accept-data-loss", ["prisma|D|prisma db push --accept-data-loss"]),
            ("python manage.py flush --noinput", ["manage.py|D|manage.py flush — deletes every row"]),
            ("python3 manage.py migrate", ["manage.py|-|manage.py migrate"]),
            ("python manage.py migrate accounts zero", ["manage.py|D|manage.py migrate … zero — unapplies the app's migrations"]),
            ("python manage.py runserver", []),
            ("php artisan migrate:fresh --seed", ["artisan|D|artisan migrate:fresh"]),
            ("php artisan migrate:rollback", ["artisan|C|artisan migrate:rollback"]),
            ("mix ecto.reset", ["mix|D|mix ecto.reset"]),
            ("mix ecto.migrate", ["mix|-|mix ecto.migrate"]),
            ("alembic downgrade base", ["alembic|D|alembic downgrade base"]),
            ("alembic downgrade -1", ["alembic|C|alembic downgrade -1"]),
            ("alembic upgrade head", ["alembic|-|alembic upgrade"]),
            ("flyway clean", ["flyway|D|flyway clean — drops every object in the schema"]),
            ("liquibase dropAll", ["liquibase|D|liquibase dropAll"]),
            ("knex migrate:rollback --all", ["knex|D|knex migrate:rollback --all"]),
            ("knex migrate:rollback", ["knex|C|knex migrate:rollback"]),
            ("yarn typeorm schema:drop", ["typeorm|D|typeorm schema:drop"]),
            ("npx sequelize db:migrate:undo:all", ["sequelize|D|sequelize db:migrate:undo:all"]),
            ("bin/rails db:migrate && bin/rails db:seed", ["rails|-|rails db:migrate", "rails|-|rails db:seed"]),
            ("rake db:schema:load", ["rake|D|rake db:schema:load"]),
            ("rails db:rollback STEP=2", ["rails|C|rails db:rollback"]),
            ("rails server", []),
            ("dropdb app_dev", ["dropdb|D|dropdb app_dev — drops the database"]),
            ("createdb app_dev", ["createdb|-|createdb app_dev"]),
            ("pg_dump app > backup.sql", ["pg_dump|-|pg_dump — a backup"]),
            ("pg_restore --clean -d app backup.dump", ["pg_restore|C|pg_restore --clean — drops objects before restoring"]),
            ("supabase db reset", ["supabase|D|supabase db reset"]),
            ("atlas schema clean", ["atlas|D|atlas schema clean"]),
            ("dbmate drop", ["dbmate|D|dbmate drop"]),
            ("goose down", ["goose|C|goose down"]),
            ("goose reset", ["goose|D|goose reset"]),
            ("migrate -path db -database $URL down -all", ["migrate|D|migrate down -all"]),   // the verb after the flag values
            ("migrate -path db -database $URL up", ["migrate|-|migrate up"]),
            ("migrate -path db -database $URL drop -f", ["migrate|D|migrate drop"]),
            ("migrate -path db -database $URL version", []),
            ("npx drizzle-kit push", ["drizzle-kit|-|drizzle-kit push"]),
            ("turso db destroy prod", ["turso|D|turso db destroy"]),
        ]
        for (line, expected) in cases {
            XCTAssertEqual(cmds(line), expected, line)
        }
    }

    func testTheOtherClientsInlineSQLAndTheirOwnDestructiveVerbs() {
        XCTAssertEqual(cmds("mysql -u root app -e 'TRUNCATE t'"), ["mysql|D|TRUNCATE t"])
        XCTAssertEqual(cmds("mysql app < dump.sql"), ["mysql|C|runs dump.sql"], "a file fed on stdin is named")
        XCTAssertEqual(cmds("sqlite3 app.db \"DELETE FROM carts WHERE user_id IS NULL\""), ["sqlite3|-|DELETE FROM carts WHERE user_id IS NULL"])
        XCTAssertEqual(cmds("sqlite3 app.db 'DELETE FROM carts'"), ["sqlite3|D|DELETE without WHERE on carts"])
        XCTAssertEqual(cmds("sqlite3 app.db"), ["sqlite3|-|opens app.db"])
        XCTAssertEqual(cmds("mongosh app --eval 'db.dropDatabase()'"), ["mongosh|D|dropDatabase()"])
        XCTAssertEqual(cmds("mongosh app --eval 'db.users.deleteMany({})'"), ["mongosh|D|deleteMany({}) — every document"])
        XCTAssertEqual(cmds("redis-cli FLUSHALL"), ["redis-cli|D|FLUSHALL — every key"])
        XCTAssertEqual(cmds("redis-cli -n 2 flushdb"), ["redis-cli|D|FLUSHDB — every key in the database"])
        XCTAssertEqual(cmds("redis-cli GET k"), ["redis-cli|-|GET k"])
        XCTAssertEqual(cmds("npx wrangler d1 execute DB --command \"DROP TABLE t\""), ["wrangler|D|d1: DROP TABLE t"])
        XCTAssertEqual(cmds("clickhouse-client -q 'TRUNCATE TABLE events'"), ["clickhouse-client|D|TRUNCATE events"])
    }

    func testEverythingElseIsNotADatabaseCommand() {
        XCTAssertEqual(cmds("grep -rn \"DELETE FROM\" src | head"), [], "a grep for DELETE")
        XCTAssertEqual(cmds("npm run build && swift test"), [], "a build and a test run")
        XCTAssertEqual(cmds("./scripts/reset-db.sh"), [], "a script is not seen through")
        XCTAssertEqual(cmds("git commit -m 'drop table users'"), [])
        XCTAssertEqual(cmds("wrangler deploy"), [])
        XCTAssertEqual(DatabaseCommands.detect(""), [])
    }
}
