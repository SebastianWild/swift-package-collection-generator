//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Package Collection Generator open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift Package Collection Generator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Package Collection Generator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

import Basics
@testable import PackageCollectionGenerator
import TSCBasic

final class GitHubPackageMetadataProviderTests: XCTestCase {
    // MARK: - GitHub.com Tests

    func test_apiURL_github() throws {
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")
        let provider = GitHubPackageMetadataProvider()

        do {
            let sshURLRetVal = provider.apiURL("git@github.com:octocat/Hello-World.git")
            XCTAssertEqual(apiURL, sshURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://github.com/octocat/Hello-World.git")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://github.com/octocat/Hello-World")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        XCTAssertNil(provider.apiURL("bad/Hello-World.git"))
    }

    func testGood_github() throws {
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.github("github.com"): "foo"]

        let handler: HTTPClient.Handler = { request, _, completion in
            guard request.headers.get("Authorization").first == "token \(authTokens.first!.value)" else {
                return completion(.success(.init(statusCode: 401)))
            }

            switch (request.method, request.url) {
            case (.get, apiURL):
                let data = self.readGitHubData(filename: "metadata.json")!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            case (.get, apiURL.appendingPathComponent("readme")):
                let data = self.readGitHubData(filename: "readme.json")!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            case (.get, apiURL.appendingPathComponent("license")):
                let data = self.readGitHubData(filename: "license.json")!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        let metadata = try tsc_await { callback in provider.get(repoURL, callback: callback) }

        XCTAssertEqual("This your first repo!", metadata.summary)
        XCTAssertEqual(["octocat", "atom", "electron", "api"], metadata.keywords)
        XCTAssertEqual(URL(string: "https://raw.githubusercontent.com/octokit/octokit.rb/master/README.md"), metadata.readmeURL)
        XCTAssertEqual("MIT", metadata.license?.name)
        XCTAssertEqual(URL(string: "https://raw.githubusercontent.com/benbalter/gman/master/LICENSE?lab=true"), metadata.license?.url)
    }

    func testInvalidAuthToken() throws {
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.github("github.com"): "foo"]

        let handler: HTTPClient.Handler = { request, _, completion in
            if request.headers.get("Authorization").first == "token \(authTokens.first!.value)" {
                completion(.success(.init(statusCode: 401)))
            } else {
                XCTFail("expected correct authorization header")
                completion(.success(.init(statusCode: 500)))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidAuthToken(apiURL))
        }
    }

    func testRepoNotFound() throws {
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.github("github.com"): "foo"]

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 404)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .notFound(apiURL))
        }
    }

    func testOthersNotFound() throws {
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.github("github.com"): "foo"]

        let handler: HTTPClient.Handler = { request, _, completion in
            guard request.headers.get("Authorization").first == "token \(authTokens.first!.value)" else {
                return completion(.success(.init(statusCode: 401)))
            }

            switch (request.method, request.url) {
            case (.get, apiURL):
                let data = self.readGitHubData(filename: "metadata.json")!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                completion(.success(.init(statusCode: 500)))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        let metadata = try tsc_await { callback in provider.get(repoURL, callback: callback) }

        XCTAssertEqual("This your first repo!", metadata.summary)
        XCTAssertEqual(["octocat", "atom", "electron", "api"], metadata.keywords)
        XCTAssertNil(metadata.readmeURL)
        XCTAssertNil(metadata.license)
    }

    func testPermissionDenied() throws {
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 401)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .permissionDenied(apiURL))
        }
    }

    func testInvalidURL() throws {
        let repoURL = URL(string: "/")!
        let provider = GitHubPackageMetadataProvider()
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidGitURL(repoURL))
        }
    }

    func testForRealz() throws {
        #if ENABLE_GITHUB_NETWORK_TEST
        #else
        try XCTSkipIf(true)
        #endif

        let repoURL = URL(string: "https://github.com/apple/swift-numerics.git")!

        var httpClient = HTTPClient()
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        httpClient.configuration.requestHeaders = .init()
        httpClient.configuration.requestHeaders!.add(name: "Cache-Control", value: "no-cache")

        var authTokens: [AuthTokenType: String] = [:]
        if let token = ProcessEnv.vars["GITHUB_API_TOKEN"] {
            authTokens[.github("github.com")] = token
        }

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        for _ in 0 ... 60 {
            let metadata = try tsc_await { callback in provider.get(repoURL, callback: callback) }
            XCTAssertNotNil(metadata)
            XCTAssert(metadata.keywords!.count > 0)
            XCTAssertNotNil(metadata.readmeURL)
            XCTAssertNotNil(metadata.license)
        }
    }
}

extension GitHubPackageMetadataProviderTests {
    // MARK: - GitHub Enterprise Tests

    func test_apiURL_githubEnterprise() throws {
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")
        let authTokens = [AuthTokenType.githubEnterprise("githubEnterprise.foo"): "bar"]
        let provider = GitHubPackageMetadataProvider(authTokens: authTokens)

        do {
            let sshURLRetVal = provider.apiURL("git@githubEnterprise.foo:octocat/Hello-World.git")
            XCTAssertEqual(apiURL, sshURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://githubEnterprise.foo/octocat/Hello-World.git")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://githubEnterprise.foo/octocat/Hello-World")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        XCTAssertNil(provider.apiURL("bad/Hello-World.git"))
    }

    func testGood_githubEnterprise() throws {
        let repoURL = URL(string: "https://githubEnterprise.foo/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.githubEnterprise("githubEnterprise.foo"): "bar"]

        let handler: HTTPClient.Handler = { request, _, completion in
            guard request.headers.get("Authorization").first == "Basic \(authTokens.first!.value)" else {
                return completion(.success(.init(statusCode: 401)))
            }

            switch (request.method, request.url) {
            case (.get, apiURL):
                let data = self.readGitHubData(filename: "metadata.json", isGitHubEnterprise: true)!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            case (.get, apiURL.appendingPathComponent("readme")):
                let data = self.readGitHubData(filename: "readme.json", isGitHubEnterprise: true)!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            case (.get, apiURL.appendingPathComponent("license")):
                let data = self.readGitHubData(filename: "license.json", isGitHubEnterprise: true)!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        let metadata = try tsc_await { callback in provider.get(repoURL, callback: callback) }

        XCTAssertEqual("This your first repo!", metadata.summary)
        XCTAssertEqual(["octocat", "atom", "electron", "api"], metadata.keywords)
        XCTAssertEqual(URL(string: "https://githubEnterprise.foo/raw/octokit/octokit.rb/master/README.md"), metadata.readmeURL)
        XCTAssertEqual("MIT", metadata.license?.name)
        XCTAssertEqual(URL(string: "https://githubEnterprise.foo/raw/benbalter/gman/master/LICENSE?lab=true"), metadata.license?.url)
    }

    func testInvalidAuthToken_githubEnterprise() throws {
        let repoURL = URL(string: "https://githubEnterprise.foo/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.githubEnterprise("githubEnterprise.foo"): "bar"]

        let handler: HTTPClient.Handler = { request, _, completion in
            if request.headers.get("Authorization").first == "Basic \(authTokens.first!.value)" {
                completion(.success(.init(statusCode: 401)))
            } else {
                XCTFail("expected correct authorization header")
                completion(.success(.init(statusCode: 500)))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidAuthToken(apiURL))
        }
    }

    func testRepoNotFound_githubEnterprise() throws {
        let repoURL = URL(string: "https://githubEnterprise.foo/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.githubEnterprise("githubEnterprise.foo"): "bar"]

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 404)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .notFound(apiURL))
        }
    }

    func testOthersNotFound_githubEnterprise() throws {
        let repoURL = URL(string: "https://githubEnterprise.foo/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.githubEnterprise("githubEnterprise.foo"): "bar"]

        let handler: HTTPClient.Handler = { request, _, completion in
            guard request.headers.get("Authorization").first == "Basic \(authTokens.first!.value)" else {
                return completion(.success(.init(statusCode: 401)))
            }

            switch (request.method, request.url) {
            case (.get, apiURL):
                let data = self.readGitHubData(filename: "metadata.json")!
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                completion(.success(.init(statusCode: 500)))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(authTokens: authTokens, httpClient: httpClient)
        let metadata = try tsc_await { callback in provider.get(repoURL, callback: callback) }

        XCTAssertEqual("This your first repo!", metadata.summary)
        XCTAssertEqual(["octocat", "atom", "electron", "api"], metadata.keywords)
        XCTAssertNil(metadata.readmeURL)
        XCTAssertNil(metadata.license)
    }

    /**
     This test is skipped right now - it will fail since the `GitHubPackageMetadataProvider.Errors` case `.permissionDenied` will have its associated value contain the wrong URL.
     This is because current logic uses the supplied auth tokens to infer the API URL, which is inherently flawed and will fail if no tokens are provided - since it cannot infer what API URL format it should use
     */
    func skipped_testPermissionDenied_githubEnterprise() throws {
        let repoURL = URL(string: "https://githubEnterprise.foo/octocat/Hello-World.git")!
        let apiURL = URL(string: "https://githubEnterprise.foo/api/v3/repos/octocat/Hello-World")!

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 401)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(repoURL, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .permissionDenied(apiURL))
        }
    }
}

// MARK: - Helpers

extension GitHubPackageMetadataProviderTests {
    private func readGitHubData(filename: String, isGitHubEnterprise: Bool = false) -> Data? {
        let gitHubDirName = isGitHubEnterprise ? "GitHubEnterprise" : "GitHub"
        let path = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", gitHubDirName, filename)
        guard let contents = try? localFileSystem.readFileContents(path).contents else {
            return nil
        }
        return Data(contents)
    }
}
