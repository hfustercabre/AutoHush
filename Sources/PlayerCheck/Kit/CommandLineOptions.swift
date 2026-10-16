/// playercheck's command line, read without the app it names.
package enum CommandLineOptions {
    /// --developer: the report also says, for whoever adds a player to
    /// AutoHush's code, how a built-in player of the app's kind would be made
    /// (AutoHush's own types). The Player Check app passes it; Add an App…
    /// doesn't, so its report ends with what the check found.
    package static let developer = "--developer"

    /// The options followed by a value of their own.
    package static let withValues: Set<String> = ["--via", "--result", "--logs", "--caches"]

    /// The value after `option` in `arguments`, if it's given.
    package static func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The arguments that are neither an option nor an option's value, in
    /// order, wherever they come: the app, or a query's apps
    /// (`--now-playing-reasons <path>…`) and numbers (`--now-playing-list 24`).
    package static func operands(in arguments: [String]) -> [String] {
        arguments.indices.filter { index in
            !arguments[index].hasPrefix("--") && (index == 0 || !withValues.contains(arguments[index - 1]))
        }.map { arguments[$0] }
    }

    /// The app a check or a press is for.
    package static func app(in arguments: [String]) -> String? { operands(in: arguments).first }
}
