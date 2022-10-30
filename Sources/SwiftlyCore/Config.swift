import Foundation

/// Struct modelling the config.json file used to track installed toolchains,
/// the current in-use tooolchain, and information about the platform.
///
/// TODO: implement cache
public struct Config: Codable, Equatable {
    // TODO: support other locations
    public static var swiftlyHomeDir =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swiftly", isDirectory: true)

    public static var swiftlyBinDir: URL {
        Self.swiftlyHomeDir.appendingPathComponent("bin", isDirectory: true)
    }

    public static var swiftlyToolchainsDir: URL {
        Self.swiftlyHomeDir.appendingPathComponent("toolchains", isDirectory: true)
    }

    public static var swiftlyConfigFile: URL {
        Self.swiftlyHomeDir.appendingPathComponent("config.json")
    }

    /// The list of directories that swiftly needs to exist in order to execute.
    /// If they do not exist when a swiftly command is invoked, they will be created.
    public static var requiredDirectories: [URL] {
        [
            Self.swiftlyHomeDir,
            Self.swiftlyBinDir,
            Self.swiftlyToolchainsDir
        ]
    }

    /// This is the list of executables included in a Swift toolchain that swiftly will create symlinks to in its `bin`
    /// directory.
    ///
    /// swiftly doesn't create links for every entry in a toolchain's `bin` directory since some of them are
    /// forked versions of executables not specific to Swift (e.g. clang), and we don't want to override those.
    public static let symlinkedExecutables: [String] = [
        "swift",
        "swiftc",
        "sourcekit-lsp",
        "docc"
    ]

    public struct PlatformDefinition: Codable, Equatable {
        public let name: String
        public let nameFull: String
        public let namePretty: String
    }

    public var inUse: ToolchainVersion?
    public var installedToolchains: Set<ToolchainVersion>
    public var platform: PlatformDefinition

    internal init(inUse: ToolchainVersion?, installedToolchains: Set<ToolchainVersion>, platform: PlatformDefinition) {
        self.inUse = inUse
        self.installedToolchains = installedToolchains
        self.platform = platform
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }

    /// Read the config file from disk.
    public static func load() throws -> Config {
        do {
            let data = try Data(contentsOf: Self.swiftlyConfigFile)
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            let msg = """
            Could not load swiftly's configuration file at \(Self.swiftlyConfigFile.path) due to error: \"\(error)\".
            To use swiftly, modify the configuration file to fix the issue or perform a clean installation.
            """
            throw Error(message: msg)
        }
    }

    /// Write the contents of this `Config` struct to disk.
    public func save() throws {
        let outData = try Self.makeEncoder().encode(self)
        try outData.write(to: Self.swiftlyConfigFile, options: .atomic)
    }

    public func listInstalledToolchains(selector: ToolchainSelector?) -> [ToolchainVersion] {
        guard let selector else {
            return Array(self.installedToolchains)
        }

        if case .latest = selector {
            var ts: [ToolchainVersion] = []
            if let t = self.installedToolchains.filter({ $0.isStableRelease() }).max() {
                ts.append(t)
            }
            return ts
        }

        return self.installedToolchains.filter { toolchain in
            selector.matches(toolchain: toolchain)
        }
    }

    /// Load the config, pass it to the provided closure, and then
    /// save the modified config to disk.
    public static func update(f: (inout Config) throws -> Void) throws {
        var config = try Config.load()
        try f(&config)
        // only save the updates if the prior closure invocation succeeded
        try config.save()
    }
}

extension ToolchainVersion: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.name)
    }
}

extension ToolchainVersion: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        self = try ToolchainVersion(parsing: str)
    }
}
