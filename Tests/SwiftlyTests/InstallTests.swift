import Foundation
@testable import Swiftly
@testable import SwiftlyCore
import XCTest

final class InstallTests: SwiftlyTests {
    /// Tests that `swiftly install latest` successfully installs the latest stable release of Swift.
    ///
    /// It stops short of verifying that it actually installs the _most_ recently released version, which is the intended
    /// behavior, since determining which version is the latest is non-trivial and would require duplicating code
    /// from within swiftly itself.
    func testInstallLatest() async throws {
        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", "latest"])
            try await cmd.run()

            let config = try Config.load()

            guard !config.installedToolchains.isEmpty else {
                XCTFail("expected to install latest main snapshot toolchain but installed toolchains is empty in the config")
                return
            }

            let installedToolchain = config.installedToolchains.first!

            guard case let .stable(release) = installedToolchain else {
                XCTFail("expected swiftly install latest to insall release toolchain but got \(installedToolchain)")
                return
            }

            // As of writing this, 5.8.0 is the latest stable release. Assert it is at least that new.
            XCTAssertTrue(release >= ToolchainVersion.StableRelease(major: 5, minor: 8, patch: 0))

            try await validateInstalledToolchains([installedToolchain], description: "install latest")
        }
    }

    /// Tests that `swiftly install a.b` installs the latest patch version of Swift a.b.
    func testInstallLatestPatchVersion() async throws {
        guard try self.baseTestConfig().platform.name != "ubi9" else {
            print("Skipping test due to insufficient download availability for ubi9")
            return
        }

        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", "5.7"])
            try await cmd.run()

            let config = try Config.load()

            guard !config.installedToolchains.isEmpty else {
                XCTFail("expected swiftly install latest to insall release toolchain but installed toolchains is empty in config")
                return
            }

            let installedToolchain = config.installedToolchains.first!

            guard case let .stable(release) = installedToolchain else {
                XCTFail("expected swiftly install latest to insall release toolchain but got \(installedToolchain)")
                return
            }

            // As of writing this, 5.7.3 is the latest 5.7 patch release. Assert it is at least that new.
            XCTAssertTrue(release >= ToolchainVersion.StableRelease(major: 5, minor: 7, patch: 3))

            try await validateInstalledToolchains([installedToolchain], description: "install latest")
        }
    }

    /// Tests that swiftly can install different stable release versions by their full a.b.c versions.
    func testInstallReleases() async throws {
        guard try self.baseTestConfig().platform.name != "ubi9" else {
            print("Skipping test due to insufficient download availability for ubi9")
            return
        }

        try await self.withTestHome {
            var installedToolchains: Set<ToolchainVersion> = []

            var cmd = try self.parseCommand(Install.self, ["install", "5.7.0"])
            try await cmd.run()

            installedToolchains.insert(ToolchainVersion(major: 5, minor: 7, patch: 0))
            try await validateInstalledToolchains(
                installedToolchains,
                description: "install a stable release toolchain"
            )

            cmd = try self.parseCommand(Install.self, ["install", "5.7.2"])
            try await cmd.run()

            installedToolchains.insert(ToolchainVersion(major: 5, minor: 7, patch: 2))
            try await validateInstalledToolchains(
                installedToolchains,
                description: "install another stable release toolchain"
            )
        }
    }

    /// Tests that swiftly can install main and release snapshots by their full snapshot names.
    func testInstallSnapshots() async throws {
        try await self.withTestHome {
            var installedToolchains: Set<ToolchainVersion> = []

            var cmd = try self.parseCommand(Install.self, ["install", "main-snapshot-2023-04-01"])
            try await cmd.run()

            installedToolchains.insert(ToolchainVersion(snapshotBranch: .main, date: "2023-04-01"))
            try await validateInstalledToolchains(
                installedToolchains,
                description: "install a main snapshot toolchain"
            )

            cmd = try self.parseCommand(Install.self, ["install", "5.9-snapshot-2023-04-01"])
            try await cmd.run()

            installedToolchains.insert(
                ToolchainVersion(snapshotBranch: .release(major: 5, minor: 9), date: "2023-04-01"))
            try await validateInstalledToolchains(
                installedToolchains,
                description: "install a 5.9 snapshot toolchain"
            )
        }
    }

    /// Tests that `swiftly install main-snapshot` installs the latest available main snapshot.
    func testInstallLatestMainSnapshot() async throws {
        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", "main-snapshot"])
            try await cmd.run()

            let config = try Config.load()

            guard !config.installedToolchains.isEmpty else {
                XCTFail("expected to install latest main snapshot toolchain but installed toolchains is empty in the config")
                return
            }

            let installedToolchain = config.installedToolchains.first!

            guard case let .snapshot(snapshot) = installedToolchain, snapshot.branch == .main else {
                XCTFail("expected to install latest main snapshot toolchain but got \(installedToolchain)")
                return
            }

            // As of writing this, this is the date of the latest main snapshot. Assert it is at least that new.
            XCTAssertTrue(snapshot.date >= "2023-04-01")

            try await validateInstalledToolchains(
                [installedToolchain],
                description: "install the latest main snapshot toolchain"
            )
        }
    }

    /// Tests that `swiftly install a.b-snapshot` installs the latest available a.b release snapshot.
    func testInstallLatestReleaseSnapshot() async throws {
        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", "5.9-snapshot"])
            try await cmd.run()

            let config = try Config.load()

            guard !config.installedToolchains.isEmpty else {
                XCTFail("expected to install latest main snapshot toolchain but installed toolchains is empty in the config")
                return
            }

            let installedToolchain = config.installedToolchains.first!

            guard case let .snapshot(snapshot) = installedToolchain, snapshot.branch == .release(major: 5, minor: 9) else {
                XCTFail("expected swiftly install 5.9-snapshot to install snapshot toolchain but got \(installedToolchain)")
                return
            }

            // As of writing this, this is the date of the latest 5.7 snapshot. Assert it is at least that new.
            XCTAssertTrue(snapshot.date >= "2023-04-01")

            try await validateInstalledToolchains(
                [installedToolchain],
                description: "install the latest 5.9 snapshot toolchain"
            )
        }
    }

    /// Tests that swiftly can install both stable release toolchains and snapshot toolchains.
    func testInstallReleaseAndSnapshots() async throws {
        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", "main-snapshot-2023-04-01"])
            try await cmd.run()

            cmd = try self.parseCommand(Install.self, ["install", "5.9-snapshot-2023-03-28"])
            try await cmd.run()

            cmd = try self.parseCommand(Install.self, ["install", "5.8.0"])
            try await cmd.run()

            try await validateInstalledToolchains(
                [
                    ToolchainVersion(snapshotBranch: .main, date: "2023-04-01"),
                    ToolchainVersion(snapshotBranch: .release(major: 5, minor: 9), date: "2023-03-28"),
                    ToolchainVersion(major: 5, minor: 8, patch: 0),
                ],
                description: "install both snapshots and releases"
            )
        }
    }

    func duplicateTest(_ version: String) async throws {
        try await self.withTestHome {
            var cmd = try self.parseCommand(Install.self, ["install", version])
            try await cmd.run()

            let before = try Config.load()

            let startTime = Date()
            cmd = try self.parseCommand(Install.self, ["install", version])
            try await cmd.run()

            // Assert that swiftly didn't attempt to download a new toolchain.
            XCTAssertTrue(startTime.timeIntervalSinceNow.magnitude < 10)

            let after = try Config.load()
            XCTAssertEqual(before, after)
        }
    }

    /// Tests that attempting to install stable releases that are already installed doesn't result in an error.
    func testInstallDuplicateReleases() async throws {
        try await self.duplicateTest("5.8.0")
        try await self.duplicateTest("latest")
    }

    /// Tests that attempting to install main snapshots that are already installed doesn't result in an error.
    func testInstallDuplicateMainSnapshots() async throws {
        try await self.duplicateTest("main-snapshot-2023-04-01")
        try await self.duplicateTest("main-snapshot")
    }

    /// Tests that attempting to install release snapshots that are already installed doesn't result in an error.
    func testInstallDuplicateReleaseSnapshots() async throws {
        try await self.duplicateTest("5.9-snapshot-2023-04-01")
        try await self.duplicateTest("5.9-snapshot")
    }

    /// Verify that the installed toolchain will be used if no toolchains currently are installed.
    func testInstallUsesFirstToolchain() async throws {
        guard try self.baseTestConfig().platform.name != "ubi9" else {
            print("Skipping test due to insufficient download availability for ubi9")
            return
        }

        try await self.withTestHome {
            let config = try Config.load()
            XCTAssertTrue(config.inUse == nil)
            try await validateInUse(expected: nil)

            var cmd = try self.parseCommand(Install.self, ["install", "5.7.0"])
            try await cmd.run()

            try await validateInUse(expected: ToolchainVersion(major: 5, minor: 7, patch: 0))

            var installOther = try self.parseCommand(Install.self, ["install", "5.7.1"])
            try await installOther.run()

            // Verify that 5.7.0 is still in use.
            try await self.validateInUse(expected: ToolchainVersion(major: 5, minor: 7, patch: 0))
        }
    }

    /// Verify that the installed toolchain will be marked as in-use if the --use flag is specified.
    func testInstallUseFlag() async throws {
        try await self.withTestHome {
            try await self.installMockedToolchain(toolchain: Self.oldStable)
            var use = try self.parseCommand(Use.self, ["use", Self.oldStable.name])
            try await use.run()
            try await validateInUse(expected: Self.oldStable)
            try await self.installMockedToolchain(selector: Self.newStable.name, args: ["--use"])
            try await self.validateInUse(expected: Self.newStable)
        }
    }
}
