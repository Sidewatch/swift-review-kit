//
//  DependencyChangesTests.swift
//  ChangeFactsTests
//
//  Every manifest parser, the facts (adds, removes, bumps) and the headline. Ported from
//  Sidewatch's `--selftest-change-facts` on 22 Sep 2026.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ChangeFacts

final class DependencyChangesTests: XCTestCase {
    private func decl(_ text: String, _ path: String) -> [String: String] { DependencyChanges.declarations(in: text, path: path) ?? [:] }

    func testManifestsAreRecognisedByName() {
        XCTAssertTrue(DependencyManifest.isManifest("web/package.json"))
        XCTAssertTrue(DependencyManifest.isManifest("Package.swift"))
        XCTAssertFalse(DependencyManifest.isManifest("src/main.swift"))
        XCTAssertTrue(DependencyChanges.isLockfile("a/package-lock.json"))
    }

    func testJSONManifests() {
        XCTAssertEqual(decl(#"{"name":"app","dependencies":{"stripe":"^12.0.0","left-pad":"1.3.0"},"devDependencies":{"vitest":"~1.2"}}"#, "web/package.json"),
                       ["stripe": "^12.0.0", "left-pad": "1.3.0", "vitest": "~1.2"])
        XCTAssertEqual(decl(#"{"require":{"php":">=8.2","laravel/framework":"^11.0"},"require-dev":{"phpunit/phpunit":"^10"}}"#, "composer.json"),
                       ["php": ">=8.2", "laravel/framework": "^11.0", "phpunit/phpunit": "^10"])
    }

    func testPythonManifests() {
        XCTAssertEqual(decl("requests>=2.31\nDjango==5.0.1  # web\n-r base.txt\nboto3[s3]~=1.34\n", "requirements.txt"), ["requests": ">=2.31", "Django": "==5.0.1", "boto3": "~=1.34"])
        XCTAssertEqual(decl("[packages]\nflask = \"*\"\nredis = {version = \"~=5.0\", extras = [\"hiredis\"]}\n[dev-packages]\npytest = \"*\"\n", "Pipfile"), ["flask": "*", "redis": "~=5.0", "pytest": "*"])
        XCTAssertEqual(decl("[project]\nname = \"x\"\ndependencies = [\n  \"fastapi>=0.110\",\n  \"pydantic\",\n]\n[tool.poetry.dependencies]\npython = \"^3.12\"\nhttpx = \"^0.27\"\n[tool.poetry.group.dev.dependencies]\nruff = \"^0.4\"\n", "pyproject.toml"),
                       ["fastapi": ">=0.110", "pydantic": "", "httpx": "^0.27", "ruff": "^0.4"], "the interpreter's own version is not a dependency")
    }

    func testSwiftRustGoRubyAndCocoaManifests() {
        XCTAssertEqual(decl(".package(url: \"https://github.com/apple/swift-nio.git\", from: \"2.60.0\"),\n.package(url: \"https://github.com/x/y\", exact: \"1.0.0\"),\n.package(path: \"../Libraries/swift-git-kit\"),", "Package.swift"),
                       ["swift-nio": "2.60.0", "y": "1.0.0", "swift-git-kit": "path"], "the version as written, a path dependency as \"path\"")
        XCTAssertEqual(decl("[package]\nname = \"a\"\n[dependencies]\nserde = \"1.0\"\ntokio = { version = \"1.36\", features = [\"full\"] }\n[dependencies.reqwest]\nversion = \"0.12\"\n[dev-dependencies]\ninsta = \"1\"\n", "Cargo.toml"),
                       ["serde": "1.0", "tokio": "1.36", "reqwest": "0.12", "insta": "1"])
        XCTAssertEqual(decl("module app\ngo 1.22\nrequire github.com/lib/pq v1.10.9\nrequire (\n\tgithub.com/gin-gonic/gin v1.9.1\n\tgolang.org/x/text v0.14.0 // indirect\n)\n", "go.mod"),
                       ["github.com/lib/pq": "v1.10.9", "github.com/gin-gonic/gin": "v1.9.1", "golang.org/x/text": "v0.14.0"])
        XCTAssertEqual(decl("source 'https://rubygems.org'\ngem 'rails', '~> 7.1'\ngem \"pg\"\n# gem 'nope'\n", "Gemfile"), ["rails": "~> 7.1", "pg": ""])
        XCTAssertEqual(decl("pod 'Alamofire', '~> 5.8'\npod 'Kingfisher'\n", "Podfile"), ["Alamofire": "~> 5.8", "Kingfisher": ""])
        XCTAssertEqual(decl("github \"ReactiveX/RxSwift\" ~> 6.0\n", "Cartfile"), ["ReactiveX/RxSwift": "~> 6.0"])
    }

    func testDartElixirGradleAndMaven() {
        XCTAssertEqual(decl("name: app\ndependencies:\n  http: ^1.2.0\n  flutter:\n    sdk: flutter\ndev_dependencies:\n  lints: ^3.0.0\nflutter:\n  uses-material-design: true\n", "pubspec.yaml"),
                       ["http": "^1.2.0", "flutter": "git/path", "lints": "^3.0.0"])
        XCTAssertEqual(decl("defp deps do\n  [{:phoenix, \"~> 1.7\"}, {:ecto_sql, \"~> 3.10\"}, {:my_lib, github: \"me/my_lib\"}]\nend\n", "mix.exs"),
                       ["phoenix": "~> 1.7", "ecto_sql": "~> 3.10", "my_lib": "github"])
        XCTAssertEqual(decl("dependencies {\n  implementation(\"com.squareup.okhttp3:okhttp:4.12.0\")\n  testImplementation 'junit:junit:4.13.2'\n}\n", "build.gradle.kts"),
                       ["com.squareup.okhttp3:okhttp": "4.12.0", "junit:junit": "4.13.2"])
        XCTAssertEqual(decl("<project><dependencies><dependency><groupId>org.springframework</groupId><artifactId>spring-core</artifactId><version>6.1.4</version></dependency></dependencies></project>", "pom.xml"),
                       ["org.springframework:spring-core": "6.1.4"])
    }

    func testFactsAndHeadline() {
        let facts = DependencyChanges.facts(oldText: #"{"dependencies":{"axios":"1.6.0","lodash":"4.17.21","react":"18.2.0"}}"#,
                                            newText: #"{"dependencies":{"axios":"1.7.0","react":"18.2.0","stripe":"^12.0.0"},"devDependencies":{"vitest":"~1.2"}}"#, path: "package.json")
        XCTAssertEqual(facts.map(\.summary), ["bumps axios 1.6.0 → 1.7.0", "adds stripe ^12.0.0", "adds vitest ~1.2", "removes lodash"])
        XCTAssertTrue(DependencyChanges.facts(oldText: "x", newText: "y", path: "package-lock.json").isEmpty, "a lockfile has no facts")
        XCTAssertTrue(DependencyChanges.facts(oldText: nil, newText: "<x/>", path: "Gopkg.toml").isEmpty, "an unread manifest has none")
        XCTAssertEqual(DependencyChanges.headline(facts), "Dependencies: adds stripe ^12.0.0, vitest ~1.2; removes lodash; bumps axios 1.6.0 → 1.7.0")
        XCTAssertNil(DependencyChanges.headline([]))
    }
}
