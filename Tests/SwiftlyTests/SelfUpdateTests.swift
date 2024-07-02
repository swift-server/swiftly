import AsyncHTTPClient
import Foundation
import NIO
@testable import Swiftly
@testable import SwiftlyCore
import XCTest

final class SelfUpdateTests: SwiftlyTests {
    private static var newMajorVersion: String {
        "\(SwiftlyCore.version.major + 1).0.0"
    }

    private static var newMinorVersion: String {
        "\(SwiftlyCore.version.major).\(SwiftlyCore.version.minor + 1).0"
    }

    private static var newPatchVersion: String {
        "\(SwiftlyCore.version.major).\(SwiftlyCore.version.minor).\(SwiftlyCore.version.patch + 1)"
    }

    private static func makeMockHTTPClient(latestVersion: String) -> SwiftlyHTTPClient {
        .mocked { request in
            guard let url = URL(string: request.url) else {
                throw SwiftlyTestError(message: "invalid url \(request.url)")
            }

            switch url.host {
            case "api.github.com":
                let nextRelease = SwiftlyGitHubRelease(tag: latestVersion)
                var buffer = ByteBuffer()
                try buffer.writeJSONEncodable(nextRelease)
                return HTTPClientResponse(body: .bytes(buffer))
            case "github.com":
                let buffer = ByteBuffer(string: latestVersion)
                return HTTPClientResponse(body: .bytes(buffer))
            default:
                throw SwiftlyTestError(message: "unknown url host: \(String(describing: url.host))")
            }
        }
    }

    func runSelfUpdateTest(latestVersion: String, shouldUpdate: Bool = true) async throws {
        try await self.withTestHome {
            let swiftlyURL = Swiftly.currentPlatform.swiftlyBinDir.appendingPathComponent("swiftly", isDirectory: false)
            try Data("old".utf8).write(to: swiftlyURL)

            var update = try self.parseCommand(SelfUpdate.self, ["self-update"])
            SelfUpdate.httpClient = Self.makeMockHTTPClient(latestVersion: latestVersion)
            try await update.run()

            let swiftly = try Data(contentsOf: swiftlyURL)

            if shouldUpdate {
                XCTAssertEqual(String(decoding: swiftly, as: UTF8.self), latestVersion)
            } else {
                XCTAssertEqual(String(decoding: swiftly, as: UTF8.self), "old")
            }
        }
    }

    func testSelfUpdate() async throws {
        try await self.runSelfUpdateTest(latestVersion: Self.newPatchVersion)
        try await self.runSelfUpdateTest(latestVersion: Self.newMinorVersion)
        try await self.runSelfUpdateTest(latestVersion: Self.newMajorVersion)
    }

    /// Verify updating the most up-to-date toolchain has no effect.
    func testSelfUpdateAlreadyUpToDate() async throws {
        try await self.runSelfUpdateTest(latestVersion: String(describing: SwiftlyCore.version), shouldUpdate: false)
    }

    /// Tests that attempting to self-update using the actual GitHub API works as expected.
    func testSelfUpdateIntegration() async throws {
        try await self.withTestHome {
            let swiftlyURL = Swiftly.currentPlatform.swiftlyBinDir.appendingPathComponent("swiftly", isDirectory: false)
            try Data("old".utf8).write(to: swiftlyURL)

            var update = try self.parseCommand(SelfUpdate.self, ["self-update"])
            try await update.run()
        }
    }
}
