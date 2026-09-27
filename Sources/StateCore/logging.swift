import Foundation
import Logging
import Synchronization

/// The level every `logger` call is filtered against.
///
/// Held separately from the handler because `LoggingSystem.bootstrap` may only be called
/// once per process: without this, changing the level would need a restart, and a menu
/// item that silently does nothing until relaunch is worse than no menu item.
///
/// `Mutex` rather than a plain `var`: the handler is copied into every `Logger` and read
/// from whichever thread logs, so the level is shared mutable state.
private let logLevelBox = Mutex<Logger.Level>(.info)

/// Reads `logger` output level. Cheap enough to call per log line.
public var spikotLogLevel: Logger.Level {
    logLevelBox.withLock { $0 }
}

/// Changes the level for every subsequent log line, in this process, immediately.
public func setSpikotLogLevel(_ level: Logger.Level) {
    logLevelBox.withLock { $0 = level }
}

/// Writes to stderr, filtering against `spikotLogLevel` rather than its own stored level.
///
/// swift-log's `StreamLogHandler` captures its level per handler instance, so changing it
/// after bootstrap would not reach the copies already handed out.
struct MutableLevelHandler: LogHandler {
    private var backing: StreamLogHandler
    var metadata: Logger.Metadata = [:]

    init(label: String) {
        self.backing = StreamLogHandler.standardError(label: label)
        // The backing handler must pass everything through; the filtering happens here.
        self.backing.logLevel = .trace
    }

    /// Reads and writes the shared level, so `logger.logLevel = .debug` also works.
    var logLevel: Logger.Level {
        get { spikotLogLevel }
        set { setSpikotLogLevel(newValue) }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= spikotLogLevel else { return }
        backing.log(
            level: level, message: message, metadata: metadata, source: source,
            file: file, function: function, line: line)
    }
}

/// Routes `logger` output to stderr at the requested level.
///
/// Must be called once from an executable's entry point: `LoggingSystem.bootstrap`
/// is a process-wide side effect, and a library's file-scope code never runs, so
/// this cannot live at file scope here.
///
/// stderr rather than stdout on purpose: stdout carries the parsed output of
/// `list`, which external scripts read.
///
/// The level comes from `SPIKOT_LOG` (`trace`, `debug`, `info`, `notice`,
/// `warning`, `error`, `critical`) and falls back to `level`. It can be changed later
/// with `setSpikotLogLevel`.
public func bootstrapLogging(level: Logger.Level = .info) {
    let resolved = ProcessInfo.processInfo.environment["SPIKOT_LOG"]
        .flatMap { Logger.Level(rawValue: $0.lowercased()) } ?? level
    setSpikotLogLevel(resolved)
    LoggingSystem.bootstrap { label in MutableLevelHandler(label: label) }
}
