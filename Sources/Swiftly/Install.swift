import _StringProcessing
import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility

import SwiftlyCore

struct Install: SwiftlyCommand {
    public static var configuration = CommandConfiguration(
        abstract: "Install a new toolchain."
    )

    @Argument(help: ArgumentHelp(
        "The version of the toolchain to install.",
        discussion: """

        The string "latest" can be provided to install the most recent stable version release:

            $ swiftly install latest

        A specific toolchain can be installed by providing a full toolchain name, for example \
        a stable release version with patch (e.g. a.b.c):

            $ swiftly install 5.4.2

        Or a snapshot with date:

            $ swiftly install 5.7-snapshot-2022-06-20
            $ swiftly install main-snapshot-2022-06-20

        The latest patch release of a specific minor version can be installed by omitting the \
        patch version:

            $ swiftly install 5.6

        Likewise, the latest snapshot associated with a given development branch can be \
        installed by omitting the date:

            $ swiftly install 5.7-snapshot
            $ swiftly install main-snapshot
        """
    ))
    var version: String

    @Option(help: ArgumentHelp(
        "A GitHub authentiation token to use for any GitHub API requests.",
        discussion: """

        This is useful to avoid GitHub's low rate limits. If an installation
        fails with an \"unauthorized\" status code, it likely means the rate limit has been hit.
        """
    ))
    var token: String?

    mutating func run() async throws {
        let selector = try ToolchainSelector(parsing: self.version)
        HTTP.githubToken = self.token
        let toolchainVersion = try await self.resolve(selector: selector)
        try await Self.execute(version: toolchainVersion)
    }

    internal static func execute(version: ToolchainVersion) async throws {
        var config = try Config.load()

        guard !config.installedToolchains.contains(version) else {
            SwiftlyCore.print("\(version) is already installed, exiting.")
            return
        }
        SwiftlyCore.print("Installing \(version)")

        let tmpFile = Swiftly.currentPlatform.getTempFilePath()
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: tmpFile)
        }

        var url = "https://download.swift.org/"
        switch version {
        case let .stable(stableVersion):
            // Building URL path that looks like:
            // swift-5.6.2-release/ubuntu2004/swift-5.6.2-RELEASE/swift-5.6.2-RELEASE-ubuntu20.04.tar.gz
            var versionString = "\(stableVersion.major).\(stableVersion.minor)"
            if stableVersion.patch != 0 {
                versionString += ".\(stableVersion.patch)"
            }
            url += "swift-\(versionString)-release/"
            url += "\(config.platform.name)/"
            url += "swift-\(versionString)-RELEASE/"
            url += "swift-\(versionString)-RELEASE-\(config.platform.nameFull).\(Swiftly.currentPlatform.toolchainFileExtension)"
        case let .snapshot(release):
            let snapshotString: String
            switch release.branch {
            case let .release(major, minor):
                url += "swift-\(major).\(minor)-branch/"
                snapshotString = "swift-\(major).\(minor)-DEVELOPMENT-SNAPSHOT"
            case .main:
                url += "development/"
                snapshotString = "swift-DEVELOPMENT-SNAPSHOT"
            }

            url += "\(config.platform.name)/"
            url += "\(snapshotString)-\(release.date)-a/"
            url += "\(snapshotString)-\(release.date)-a-\(config.platform.nameFull).\(Swiftly.currentPlatform.toolchainFileExtension)"
        }

        let animation = PercentProgressAnimation(
            stream: stdoutStream,
            header: "Downloading \(version)"
        )

        var lastUpdate = Date()

        do {
            try await HTTP.downloadToolchain(
                url: url,
                to: tmpFile.path,
                reportProgress: { progress in
                    let now = Date()

                    guard lastUpdate.distance(to: now) > 0.25 || progress.receivedBytes == progress.totalBytes else {
                        return
                    }

                    let downloadedMiB = Double(progress.receivedBytes) / (1024.0 * 1024.0)
                    let totalMiB = Double(progress.totalBytes!) / (1024.0 * 1024.0)

                    lastUpdate = Date()

                    animation.update(
                        step: progress.receivedBytes,
                        total: progress.totalBytes!,
                        text: "Downloaded \(String(format: "%.1f", downloadedMiB)) MiB of \(String(format: "%.1f", totalMiB)) MiB"
                    )
                }
            )
        } catch _ as HTTP.DownloadNotFoundError {
            SwiftlyCore.print("\(version) does not exist, exiting")
            return
        } catch {
            animation.complete(success: false)
            throw error
        }

        animation.complete(success: true)

        try Swiftly.currentPlatform.install(from: tmpFile, version: version)

        config.installedToolchains.insert(version)
        try config.save()

        // If this is the first installed toolchain, mark it as in-use.
        if config.inUse == nil {
            try await Use.execute(version, config: &config)
        }

        SwiftlyCore.print("\(version) installed successfully!")
    }

    /// Utilize the GitHub API along with the provided selector to select a toolchain for install.
    /// TODO: update this to use an official swift.org API
    func resolve(selector: ToolchainSelector) async throws -> ToolchainVersion {
        switch selector {
        case .latest:
            SwiftlyCore.print("Fetching the latest stable Swift release...")

            guard let release = try await HTTP.getReleaseToolchains(limit: 1).first else {
                throw Error(message: "couldn't get latest releases")
            }
            return .stable(release)

        case let .stable(major, minor, patch):
            guard let minor else {
                throw Error(
                    message: "Need to provide at least major and minor versions when installing a release toolchain."
                )
            }

            if let patch {
                return .stable(ToolchainVersion.StableRelease(major: major, minor: minor, patch: patch))
            }

            SwiftlyCore.print("Fetching the latest stable Swift \(major).\(minor) release...")
            // If a patch was not provided, perform a lookup to get the latest patch release
            // of the provided major/minor version pair.
            let toolchain = try await HTTP.getReleaseToolchains(limit: 1) { release in
                release.major == major && release.minor == minor
            }.first

            guard let toolchain else {
                throw Error(message: "No release toolchain found matching \(major).\(minor)")
            }

            return .stable(toolchain)

        case let .snapshot(branch, date):
            if let date {
                return ToolchainVersion(snapshotBranch: branch, date: date)
            }

            SwiftlyCore.print("Fetching the latest \(branch) branch snapshot...")
            // If a date was not provided, perform a lookup to find the most recent snapshot
            // for the given branch.
            let snapshot = try await HTTP.getSnapshotToolchains(limit: 1) { snapshot in
                snapshot.branch == branch
            }.first

            guard let snapshot else {
                throw Error(message: "No snapshot toolchain found for branch \(branch)")
            }

            return .snapshot(snapshot)
        }
    }
}
