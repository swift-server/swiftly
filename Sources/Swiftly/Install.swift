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

    @Flag(name: .shortAndLong, help: "Mark the newly installed toolchain as in-use.")
    var use: Bool = false

    @Option(help: ArgumentHelp(
        "A GitHub authentiation token to use for any GitHub API requests.",
        discussion: """

        This is useful to avoid GitHub's low rate limits. If an installation
        fails with an \"unauthorized\" status code, it likely means the rate limit has been hit.
        """
    ))
    var token: String?

    @Flag(help: "Skip PGP verification of the installed toolchain's signature.")
    var noVerify = false

    public var httpClient = SwiftlyHTTPClient()

    private enum CodingKeys: String, CodingKey {
        case version, token, use, noVerify
    }

    mutating func run() async throws {
        let selector = try ToolchainSelector(parsing: self.version)
        self.httpClient.githubToken = self.token
        let toolchainVersion = try await self.resolve(selector: selector)
        var config = try Config.load()
        try await Self.execute(
            version: toolchainVersion,
            &config,
            self.httpClient,
            useInstalledToolchain: self.use,
            verifySignature: !self.noVerify
        )
    }

    internal static func execute(
        version: ToolchainVersion,
        _ config: inout Config,
        _ httpClient: SwiftlyHTTPClient,
        useInstalledToolchain: Bool,
        verifySignature: Bool
    ) async throws {
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

        var platformString = config.platform.name
        var platformFullString = config.platform.nameFull
        if let arch = config.platform.architecture {
            platformString += "-\(arch)"
            platformFullString += "-\(arch)"
        }

        switch version {
        case let .stable(stableVersion):
            // Building URL path that looks like:
            // swift-5.6.2-release/ubuntu2004/swift-5.6.2-RELEASE/swift-5.6.2-RELEASE-ubuntu20.04.tar.gz
            var versionString = "\(stableVersion.major).\(stableVersion.minor)"
            if stableVersion.patch != 0 {
                versionString += ".\(stableVersion.patch)"
            }

            url += "swift-\(versionString)-release/"
            url += "\(platformString)/"
            url += "swift-\(versionString)-RELEASE/"
            url += "swift-\(versionString)-RELEASE-\(platformFullString).\(Swiftly.currentPlatform.toolchainFileExtension)"
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

            url += "\(platformString)/"
            url += "\(snapshotString)-\(release.date)-a/"
            url += "\(snapshotString)-\(release.date)-a-\(platformFullString).\(Swiftly.currentPlatform.toolchainFileExtension)"
        }

        guard let url = URL(string: url) else {
            throw Error(message: "Invalid toolchain URL: \(url)")
        }

        let animation = PercentProgressAnimation(
            stream: stdoutStream,
            header: "Downloading \(version)"
        )

        var lastUpdate = Date()

        do {
            try await httpClient.downloadFile(
                url: url,
                to: tmpFile,
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
        } catch _ as SwiftlyHTTPClient.DownloadNotFoundError {
            SwiftlyCore.print("\(version) does not exist, exiting")
            return
        } catch {
            animation.complete(success: false)
            throw error
        }
        animation.complete(success: true)

        if verifySignature {
            try await Swiftly.currentPlatform.verifySignature(
                httpClient: httpClient,
                archiveDownloadURL: url,
                archive: tmpFile
            )
        }

        try Swiftly.currentPlatform.install(from: tmpFile, version: version)

        config.installedToolchains.insert(version)
        try config.save()

        // If this is the first installed toolchain, mark it as in-use regardless of whether the
        // --use argument was provided.
        if useInstalledToolchain || config.inUse == nil {
            try await Use.execute(version, &config)
        }

        SwiftlyCore.print("\(version) installed successfully!")
    }

    /// Utilize the GitHub API along with the provided selector to select a toolchain for install.
    /// TODO: update this to use an official swift.org API
    func resolve(selector: ToolchainSelector) async throws -> ToolchainVersion {
        switch selector {
        case .latest:
            SwiftlyCore.print("Fetching the latest stable Swift release...")

            guard let release = try await self.httpClient.getReleaseToolchains(limit: 1).first else {
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
            let toolchain = try await self.httpClient.getReleaseToolchains(limit: 1) { release in
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
            let snapshot = try await self.httpClient.getSnapshotToolchains(limit: 1) { snapshot in
                snapshot.branch == branch
            }.first

            guard let snapshot else {
                throw Error(message: "No snapshot toolchain found for branch \(branch)")
            }

            return .snapshot(snapshot)
        }
    }
}
