import Foundation

public let version = SwiftlyVersion(major: 0, minor: 4, patch: 0, suffix: "dev")

/// A separate home directory to use for testing purposes. This overrides swiftly's default
/// home directory location logic.
public var mockedHomeDir: URL?

/// Protocol defining a handler for information swiftly intends to print to stdout.
/// This is currently only used to intercept print statements for testing.
public protocol OutputHandler {
    func handleOutputLine(_ string: String)
}

/// The output handler to use, if any.
public var outputHandler: (any OutputHandler)?

/// Pass the provided string to the set output handler if any.
/// If no output handler has been set, just print to stdout.
public func print(_ string: String = "", terminator: String? = nil) {
    guard let handler = SwiftlyCore.outputHandler else {
        if let terminator {
            Swift.print(string, terminator: terminator)
        } else {
            Swift.print(string)
        }
        return
    }
    handler.handleOutputLine(string + (terminator ?? ""))
}

public protocol InputProvider {
    func readLine() -> String?
}

public var inputProvider: (any InputProvider)?

public func readLine(prompt: String) -> String? {
    print(prompt, terminator: ": ")
    guard let provider = SwiftlyCore.inputProvider else {
        return Swift.readLine(strippingNewline: true)
    }
    return provider.readLine()
}
