/// The project version, and the only place it is written down.
///
/// Both executables report this via `--version`, and `make version-check` asserts it
/// equals the newest git tag with the leading `v` stripped. Anything else that needs
/// the version reads it from here rather than repeating the literal.
///
/// Bump it in the same commit as the change it describes, then tag that commit
/// `v<spikotVersion>`. See the Versioning section of AGENTS.md for which component to
/// move.
public let spikotVersion = "0.27.4"
