import _StringProcessing
import Foundation

/// Struct modeling a version of swiftly itself.
public struct SwiftlyVersion: Equatable, Comparable, CustomStringConvertible {
    /// Regex matching versions like "a.b.c", "a.b.c-alpha", and "a.b.c-alpha.2".
    static let regex: Regex<(Substring, Substring, Substring, Substring, Substring?)> =
        try! Regex("^(\\d+)\\.(\\d+)\\.(\\d+)(?:-([a-zA-Z0-9\\.]+))?$")

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let suffix: String?

    public init(major: Int, minor: Int, patch: Int, suffix: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.suffix = suffix
    }

    public init(parsing tag: String) throws {
        guard let match = try Self.regex.wholeMatch(in: tag) else {
            throw Error(message: "unable to parse release tag: \"\(tag)\"")
        }

        self.major = Int(match.output.1)!
        self.minor = Int(match.output.2)!
        self.patch = Int(match.output.3)!
        self.suffix = match.output.4.flatMap(String.init)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        } else if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        } else if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        } else {
            switch (lhs.suffix, rhs.suffix) {
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            case let (.some(lhsSuffix), .some(rhsSuffix)):
                return lhsSuffix < rhsSuffix
            case (.none, .none):
                return false
            }
        }
    }

    public var description: String {
        var base = "\(self.major).\(self.minor).\(self.patch)"
        if let suffix = self.suffix {
            base += "-\(suffix)"
        }
        return base
    }
}
