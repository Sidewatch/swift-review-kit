//
//  TestRunsTests.swift
//  ChangeFactsTests
//
//  The runners by their own names, each one's summary read as counts, and test files told by
//  path and name.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ChangeFacts

/// Tests for `TestRuns`: a runner is named through the same wrapper peeling as a database
/// command, its summary line reads out as passed / failed, a run without one is unknown and
/// never guessed from the exit status, and a changed file is a test by the frameworks' paths.
final class TestRunsTests: XCTestCase {

    func testRunnersByTheirOwnNamesAndWhatIsNotARun() {
        let cases: [(String, String?)] = [
            ("swift test 2>&1 | tail -20", "swift test"), ("cd web && npm test", nil), ("npm test", "npm test"), ("npm run test:unit", "npm test"),
            ("npx jest --ci", "jest"), ("npx vitest run", "vitest"), ("pytest -q", "pytest"), ("python -m pytest tests/", "pytest"), ("python3 -m unittest", "unittest"),
            ("go test ./...", "go test"), ("cargo test --workspace", "cargo test"), ("cargo nextest run", "cargo test"), ("bundle exec rspec spec/", "rspec"), ("bin/rails test", "rails test"),
            ("vendor/bin/phpunit", "phpunit"), ("php artisan test", "artisan test"), ("mix test", "mix test"), ("dotnet test", "dotnet test"),
            ("./gradlew test", "gradle test"), ("mvn -q test", "mvn test"), ("flutter test", "flutter test"), ("deno test -A", "deno test"), ("make test", "make test"),
            ("xcodebuild test -scheme App", "xcodebuild test"), ("bun test", "bun test"), ("npx playwright test", "playwright test"), ("ctest --output-on-failure", "ctest"),
            ("grep -n test README.md", nil), ("npm run build", nil), ("swift build", nil), ("cargo build", nil), ("go vet ./...", nil), ("", nil),
        ]
        for (line, runner) in cases {
            XCTAssertEqual(TestRuns.runner(of: line), runner, line)
        }
    }

    private func parsed(_ runner: String, _ out: String) -> String {
        let p = TestRuns.parse(runner: runner, output: out, isError: false)
        return "\(p.passed.map(String.init) ?? "-")/\(p.failed.map(String.init) ?? "-")/\(p.outcome)"
    }

    func testEachRunnersSummaryLineReadsOutAsCounts() {
        let cases: [(String, String, String)] = [
            ("swift test", "Test Suite 'All tests' passed\n\t Executed 12 tests, with 0 failures (0 unexpected) in 0.4 seconds", "12/0/passed"),
            ("swift test", "Executed 3 tests, with 1 failure (0 unexpected) in 0.4 seconds\nExecuted 12 tests, with 2 failures (0 unexpected) in 0.9 seconds", "10/2/failed"),
            ("swift test", "✔ Test run with 7 tests in 2 suites passed after 0.1 seconds.", "7/0/passed"),
            ("swift test", "✘ Test run with 7 tests in 2 suites failed after 0.1 seconds with 2 issues.", "5/2/failed"),
            ("xcodebuild test", "** TEST SUCCEEDED **", "-/-/passed"),
            ("xcodebuild test", "** TEST FAILED **", "-/-/failed"),
            ("jest", "Tests:       1 failed, 4 passed, 5 total", "4/1/failed"),
            ("jest", "Tests:       2 skipped, 4 passed, 6 total", "4/0/passed"),
            ("vitest", " Tests  9 passed (9)", "9/0/passed"),
            ("vitest", " Tests  1 failed | 8 passed (9)", "8/1/failed"),
            ("mocha", "  12 passing (40ms)\n  1 failing", "12/1/failed"),
            ("bun test", " 5 pass\n 0 fail", "5/0/passed"),
            ("tap", "# pass 3\n# fail 1", "3/1/failed"),
            ("pytest", "40 passed, 2 failed in 1.2s", "40/2/failed"),
            ("pytest", "2 failed, 40 passed, 1 error in 1.2s", "40/3/failed"),
            ("pytest", "======= 8 passed in 0.31s =======", "8/0/passed"),
            ("pytest", "no tests ran in 0.01s", "0/0/passed"),
            ("unittest", "Ran 6 tests in 0.01s\n\nOK", "6/0/passed"),
            ("unittest", "Ran 6 tests in 0.01s\n\nFAILED (failures=1, errors=1)", "4/2/failed"),
            ("go test", "--- FAIL: TestA (0.00s)\n--- FAIL: TestB (0.00s)\nFAIL\nFAIL\tapp\t0.1s", "-/2/failed"),
            ("go test", "FAIL\tapp [build failed]", "-/-/failed"),
            ("go test", "ok  \tapp\t0.1s", "-/-/passed"),
            ("cargo test", "test result: ok. 7 passed; 0 failed; 0 ignored\ntest result: ok. 3 passed; 0 failed", "10/0/passed"),
            ("rspec", "12 examples, 1 failure", "11/1/failed"),
            ("rails test", "20 runs, 41 assertions, 1 failures, 1 errors, 0 skips", "18/2/failed"),
            ("phpunit", "OK (15 tests, 30 assertions)", "15/0/passed"),
            ("phpunit", "FAILURES!\nTests: 15, Assertions: 30, Failures: 2.", "13/2/failed"),
            ("pest", "  Tests:    1 failed, 4 passed (9 assertions)", "4/1/failed"),
            ("mix test", "Finished in 0.1 seconds\n9 tests, 0 failures", "9/0/passed"),
            ("dotnet test", "Passed!  - Failed:     0, Passed:    22, Skipped:     0, Total:    22", "22/0/passed"),
            ("dotnet test", "Total tests: 22\n     Passed: 20\n     Failed: 2", "20/2/failed"),
            ("flutter test", "00:03 +12: All tests passed!", "12/0/passed"),
            ("flutter test", "00:03 +11 -1: Some tests failed.", "11/1/failed"),
            ("gradle test", "Tests run: 30, Failures: 1, Errors: 0, Skipped: 0\nBUILD FAILED", "29/1/failed"),
            ("gradle test", "BUILD SUCCESSFUL in 4s", "-/-/passed"),
            ("deno test", "ok | 4 passed | 0 failed (12ms)", "4/0/passed"),
            ("ctest", "100% tests passed, 0 tests failed out of 9", "9/0/passed"),
            ("npm test", "> app@1.0.0 test\n> echo no tests", "-/-/unknown"),
            ("make test", "everything fine", "-/-/unknown"),
        ]
        for (runner, output, expected) in cases {
            XCTAssertEqual(parsed(runner, output), expected, "\(runner): \(output.prefix(40))")
        }
    }

    func testARunWithoutASummaryIsUnknownNeverGuessedFromTheExitStatus() {
        XCTAssertEqual(TestRuns.parse(runner: "npm test", output: "", isError: true), .unknown)
        XCTAssertEqual(TestRuns.parse(runner: "pytest", output: "Traceback (most recent call last)…", isError: true).outcome, .unknown)
    }

    func testRunsReadEverySegmentOfALineAgainstItsOneOutput() {
        let runs = TestRuns.runs(in: "swift build && swift test 2>&1 | tail -20", output: "Executed 3 tests, with 0 failures (0 unexpected)", isError: false, timestamp: "11:00")
        XCTAssertEqual(runs.map(\.summary), ["swift test: 3 passed, 0 failed"])
        XCTAssertEqual(runs.first?.command, "swift test 2>&1")
        XCTAssertEqual(runs.first?.timestamp, "11:00")
        XCTAssertEqual(TestRuns.runs(in: "npm run build", output: "ok", isError: false), [])
    }

    func testRunSummariesSayWhatWasRead() {
        func run(_ p: Int?, _ f: Int?, _ o: TestRuns.Outcome) -> String {
            TestRuns.Run(runner: "r", command: "", passed: p, failed: f, outcome: o, timestamp: "").summary
        }
        XCTAssertEqual(run(12, 0, .passed), "r: 12 passed, 0 failed")
        XCTAssertEqual(run(12, nil, .passed), "r: 12 passed")
        XCTAssertEqual(run(nil, 2, .failed), "r: 2 failed")
        XCTAssertEqual(run(nil, nil, .failed), "r: FAIL")
        XCTAssertEqual(run(nil, nil, .passed), "r: passed")
        XCTAssertEqual(run(nil, nil, .unknown), "r: no summary")
    }

    func testTestFilesByPathAndNameAndTheTallyOfChangedFiles() {
        for path in ["Tests/AppTests/FooTests.swift", "src/__tests__/a.js", "spec/models/user_spec.rb", "pkg/x_test.go", "tests/test_api.py", "app/Foo.test.tsx", "UserTest.java", "Testing/Fixture.cs"] {
            XCTAssertTrue(TestRuns.isTestPath(path), path)
        }
        for path in ["Sources/App/Foo.swift", "src/contest.js", "docs/manual.md", "attest.go", "src/latest.ts"] {
            XCTAssertFalse(TestRuns.isTestPath(path), path)
        }
        XCTAssertEqual(TestRuns.testFilesTally(["a.swift", "b.swift"]), "2 changed files, none are tests")
        XCTAssertEqual(TestRuns.testFilesTally(["a.swift", "Tests/ATests.swift"]), "2 changed files, 1 is a test")
        XCTAssertEqual(TestRuns.testFilesTally(["x_test.go", "y_test.go", "z.go"]), "3 changed files, 2 are tests")
        XCTAssertEqual(TestRuns.testFilesTally(["a.py"]), "1 changed file, none are tests")
        XCTAssertNil(TestRuns.testFilesTally([]))
    }
}
