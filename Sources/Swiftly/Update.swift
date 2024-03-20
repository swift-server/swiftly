import ArgumentParser
import SwiftlyCore

struct Update: SwiftlyCommand {
    public static var configuration = CommandConfiguration(
        abstract: "Update an installed toolchain to a newer version."
    )

    @Argument(help: ArgumentHelp(
        "The installed toolchain to update.",
        discussion: """

        Updating a toolchain involves uninstalling it and installing a new toolchain that is \
        newer than it.

        If no argument is provided to the update command, the currently in-use toolchain will \
        be updated. If that toolchain is a stable release, it will be updated to the latest \
        patch version for that major.minor version. If the currently in-use toolchain is a \
        snapshot, then it will be updated to the latest snapshot for that development branch.

            $ swiftly update

        The string "latest" can be provided to update the installed stable release toolchain \
        with the newest version to the latest available stable release. This may update the \
        toolchain to later major, minor, or patch versions.

            $ swiftly update latest

        A specific stable release can be updated to the latest patch version for that release by \
        specifying the entire version:

            $ swiftly update 5.6.0

        Omitting the patch in the specified version will update the latest installed toolchain for \
        the provided minor version to the latest available release for that minor version. For \
        example, the following will update the latest installed Swift 5.4 release toolchain to \
        the latest available Swift 5.4 release:

            $ swiftly update 5.4

        Similarly, omitting the minor in the specified version will update the latest installed \
        toolchain for the provided major version to the latest available release for that major \
        version. Note that this may update the toolchain to a later minor version.

            $ swiftly update 5

        The latest snapshot toolchain for a given development branch can be updated to \
        the latest available snapshot for that branch by specifying just the branch:

            $ swiftly update 5.7-snapshot
            $ swiftly update main-snapshot

        A specific snapshot toolchain can be updated by including the date:

            $ swiftly update 5.9-snapshot-2023-09-20
            $ swiftly update main-snapshot-2023-09-20
        """
    ))
    var toolchain: String?

    @Flag(
        name: [.long, .customShort("y")],
        help: "Update the selected toolchains without prompting for confirmation."
    )
    var assumeYes: Bool = false

    @Flag(help: "Skip PGP verification of the installed toolchain's signature.")
    var noVerify = false

    public var httpClient = SwiftlyHTTPClient()

    private enum CodingKeys: String, CodingKey {
        case toolchain, assumeYes, noVerify
    }

    public mutating func run() async throws {
        var config = try Config.load()

        guard let parameters = try self.resolveUpdateParameters(config) else {
            if let toolchain = self.toolchain {
                SwiftlyCore.print("No installed toolchain matched \"\(toolchain)\"")
            } else {
                SwiftlyCore.print("No toolchains are currently installed")
            }
            return
        }

        guard let newToolchain = try await self.lookupNewToolchain(parameters) else {
            SwiftlyCore.print("\(parameters.oldToolchain) is already up to date")
            return
        }

        guard !config.installedToolchains.contains(newToolchain) else {
            SwiftlyCore.print("The newest version of \(parameters.oldToolchain) (\(newToolchain)) is already installed")
            return
        }

        if !self.assumeYes {
            SwiftlyCore.print("Update \(parameters.oldToolchain) ⟶ \(newToolchain)?")
            guard SwiftlyCore.promptForConfirmation(defaultBehavior: true) else {
                SwiftlyCore.print("Aborting")
                return
            }
        }

        try await Install.execute(
            version: newToolchain,
            &config,
            self.httpClient,
            useInstalledToolchain: config.inUse == parameters.oldToolchain,
            verifySignature: !self.noVerify
        )

        try await Uninstall.execute(parameters.oldToolchain, &config)
        SwiftlyCore.print("Successfully updated \(parameters.oldToolchain) ⟶ \(newToolchain)")
    }

    /// Using the provided toolchain selector and the current config, returns a set of parameters that determines
    /// what new toolchains the selected toolchain can be updated to.
    ///
    /// If the selector does not match an installed toolchain, this returns nil.
    /// If no selector is provided, the currently in-use toolchain will be used as the basis for the returned
    /// parameters.
    private func resolveUpdateParameters(_ config: Config) throws -> UpdateParameters? {
        let selector = try self.toolchain.map { try ToolchainSelector(parsing: $0) }

        let oldToolchain: ToolchainVersion?
        if let selector {
            let toolchains = config.listInstalledToolchains(selector: selector)
            // When multiple toolchains are matched, update the latest one.
            // This is for situations such as `swiftly update 5.5` when both
            // 5.5.1 and 5.5.2 are installed (5.5.2 will be updated).
            oldToolchain = toolchains.max()
        } else {
            oldToolchain = config.inUse
        }

        guard let oldToolchain else {
            return nil
        }

        switch oldToolchain {
        case let .snapshot(snapshot):
            return .snapshot(old: snapshot)
        case let .stable(stable):
            switch selector {
            case .none:
                return .stable(old: stable, target: .latestPatch)
            case let .stable(_, minor, _):
                if minor == nil {
                    return .stable(old: stable, target: .latestMinor)
                } else {
                    return .stable(old: stable, target: .latestPatch)
                }
            case .latest:
                return .stable(old: stable, target: .latest)
            default:
                fatalError("unreachable")
            }
        }
    }

    /// Tries to find a toolchain version that meets the provided parameters, if one exists.
    /// This does not download the toolchain, but it does query the GitHub API to find the suitable toolchain.
    private func lookupNewToolchain(_ bounds: UpdateParameters) async throws -> ToolchainVersion? {
        switch bounds {
        case let .stable(old, range):
            return try await self.httpClient.getReleaseToolchains(limit: 1) { release in
                switch range {
                case .latest:
                    return release > old
                case .latestMinor:
                    return release.major == old.major && release > old
                case .latestPatch:
                    return release.major == old.major && release.minor == old.minor && release > old
                }
            }.first.map(ToolchainVersion.stable)
        case let .snapshot(old):
            return try await self.httpClient.getSnapshotToolchains(limit: 1) { snapshot in
                snapshot.branch == old.branch && snapshot.date > old.date
            }.first.map(ToolchainVersion.snapshot)
        }
    }
}

/// Enum that models an update operation.
///
/// For snapshots, includes the old version of the snapshot that will be updated to the latest snapshot on the same
/// branch.
enum UpdateParameters {
    /// Bounds of an update to a stable release toolchain.
    enum StableUpdateTarget {
        /// No bounds on the update. The old toolchain will be replaced with the latest available stable release of any
        /// major version.
        case latest

        /// The old toolchain will be replaced with the latest available stable release with the same major version.
        case latestMinor

        /// The old toolchain will be replaced with the latest available stable release with the same major and minor
        /// versions.
        case latestPatch
    }

    /// Stable release update operation.
    ///
    /// "old" refers to the toolchain version being updated, and "target" specifies a range of acceptable versions to
    /// update to relative to "old".
    ///
    /// For example, .stable(old: "5.0.0", target: .latestMinor) models an update operation that will replace the
    /// installed 5.0.0 release toolchain to the latest 5.x.y release.
    case stable(old: ToolchainVersion.StableRelease, target: StableUpdateTarget)

    /// Snapshot toolchain update operation.
    ///
    /// "old" refers to the snapshot toolchain that will be updated. It will be replaced with the latest available
    /// snapshot toolchain with the same branch as "old", if one exists.
    case snapshot(old: ToolchainVersion.Snapshot)

    var oldToolchain: ToolchainVersion {
        switch self {
        case let .stable(old, _):
            return .stable(old)
        case let .snapshot(old):
            return .snapshot(old)
        }
    }
}
