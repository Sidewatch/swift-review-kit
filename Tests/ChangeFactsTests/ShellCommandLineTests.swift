//
//  ShellCommandLineTests.swift
//  ChangeFactsTests
//
//  Tests for the shell reading the command readers share: segments, words, and the tool at the
//  front once the wrappers are peeled.
//
//  Created by David Sherlock on 9/22/26.
//

import XCTest
@testable import ChangeFacts

/// Tests for `ShellCommandLine`: a line splits where a shell would, quotes and heredocs hold,
/// and the tool named is the one that really runs.
final class ShellCommandLineTests: XCTestCase {

    func testALineSplitsOnAndOrSemicolonPipeAndNewlineButNotInsideQuotes() {
        let line = "cd app && psql -c \"DELETE FROM a; DELETE FROM b\" | tee log; echo 'x && y'\nswift test || echo failed"
        XCTAssertEqual(ShellCommandLine.segments(of: line),
                       ["cd app", "psql -c \"DELETE FROM a; DELETE FROM b\"", "tee log", "echo 'x && y'", "swift test", "echo failed"])
    }

    func testAHeredocStaysWithTheSegmentThatOpenedIt() {
        let line = "psql <<'SQL'\nDROP TABLE a && b;\nSQL\necho done"
        XCTAssertEqual(ShellCommandLine.segments(of: line), ["psql <<'SQL'\nDROP TABLE a && b;\nSQL", "echo done"])
        XCTAssertEqual(ShellCommandLine.segments(of: "cat <<-EOF\n\tindented\n\tEOF"), ["cat <<-EOF\n\tindented\n\tEOF"], "<<- strips tabs before the closing tag")
        XCTAssertEqual(ShellCommandLine.segments(of: "psql << \"SQL\"\nSELECT 1;\nSQL"), ["psql << \"SQL\"\nSELECT 1;\nSQL"])
    }

    func testABackslashContinuedLineIsOneSegmentAndEmptySegmentsAreDropped() {
        XCTAssertEqual(ShellCommandLine.segments(of: "psql \\\n  -c 'SELECT 1'"), ["psql -c 'SELECT 1'"])
        XCTAssertEqual(ShellCommandLine.segments(of: "a;; b\n\n"), ["a", "b"])
        XCTAssertEqual(ShellCommandLine.segments(of: ""), [])
    }

    func testWordsGroupByQuotesAndDropThem() {
        XCTAssertEqual(ShellCommandLine.words("psql -c \"DELETE FROM a; b\" 'x y' plain"), ["psql", "-c", "DELETE FROM a; b", "x y", "plain"])
        XCTAssertEqual(ShellCommandLine.words("echo \"a \\\"q\\\" b\" c\\ d"), ["echo", "a \"q\" b", "c d"], "backslash escapes inside and outside quotes")
        XCTAssertEqual(ShellCommandLine.words("psql -c ''"), ["psql", "-c", ""], "an empty quoted string is a word")
        XCTAssertEqual(ShellCommandLine.words("   "), [])
    }

    func testTheToolIsWhatRunsOnceTheWrappersArePeeled() {
        let cases: [(String, String, [String])] = [
            ("DATABASE_URL=postgres://x npx prisma migrate reset --force", "prisma", ["migrate", "reset", "--force"]),
            ("sudo -u postgres psql -c 'TRUNCATE t'", "psql", ["-c", "TRUNCATE t"]),
            ("bundle exec rails db:drop", "rails", ["db:drop"]),
            ("poetry run alembic downgrade base", "alembic", ["downgrade", "base"]),
            ("pnpm dlx prisma migrate deploy", "prisma", ["migrate", "deploy"]),
            ("yarn typeorm schema:drop", "typeorm", ["schema:drop"]),
            ("docker compose exec -T db psql -U app app_dev -c 'DROP TABLE t'", "psql", ["-U", "app", "app_dev", "-c", "DROP TABLE t"]),
            ("docker exec -it -e X=1 mydb mysql -e 'x'", "mysql", ["-e", "x"]),
            ("kubectl exec pod-1 -- psql -c 'DROP TABLE t'", "psql", ["-c", "DROP TABLE t"]),
            ("sh -c \"psql -c 'DROP TABLE t'\"", "psql", ["-c", "DROP TABLE t"]),
            ("ssh db.internal 'psql -c \"DROP TABLE t\"'", "psql", ["-c", "DROP TABLE t"]),
            ("time /usr/local/bin/psql app", "psql", ["app"]),
            ("python manage.py migrate accounts zero", "manage.py", ["migrate", "accounts", "zero"]),
            ("php artisan migrate:fresh --seed", "artisan", ["migrate:fresh", "--seed"]),
            ("node ace migration:run", "ace", ["migration:run"]),
            ("bun run/seed.ts", "seed.ts", []),
            ("bun test", "bun", ["test"]),
            ("deno test -A", "deno", ["test", "-A"]),
            ("npm install", "npm", ["install"]),
            ("docker build .", "docker", ["build", "."]),
            ("kubectl exec pod-1 psql", "kubectl", ["exec", "pod-1", "psql"]),
        ]
        for (line, tool, args) in cases {
            let call = ShellCommandLine.invocation(of: line)
            XCTAssertEqual(call?.tool, tool, line)
            XCTAssertEqual(call?.arguments, args, line)
        }
    }

    func testAHeredocBodyRidesOnTheInvocationAndAnEmptySegmentHasNone() {
        let call = ShellCommandLine.invocation(of: "psql app <<'SQL'\nDROP TABLE a;\nSQL")
        XCTAssertEqual(call?.tool, "psql")
        XCTAssertEqual(call?.arguments, ["app", "<<SQL"])
        XCTAssertEqual(call?.heredoc, "DROP TABLE a;\nSQL")
        XCTAssertNil(ShellCommandLine.invocation(of: ""))
        XCTAssertNil(ShellCommandLine.invocation(of: "python"), "an interpreter with no script runs nothing nameable")
    }
}
