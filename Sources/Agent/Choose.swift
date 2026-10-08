import Foundation
import StateCore

// `choose <list command> | <action command>`: the picker over another program's output. Replaces
// choose-gui for the one script still calling it, choosepass.
extension AgentEngine {

    /// Longest the list command may take before it is stopped and the panel taken down.
    static let chooseListTimeout: TimeInterval = 10

    /// Opens the picker, fills it with the list command's output lines, and runs the action with
    /// the line picked.
    ///
    /// The panel goes up first, empty, and the list fills it when its command finishes. The other
    /// order would be simpler, but the panel only becomes key when it is shown from the hotkey
    /// handler itself; shown from a completion handler later, it is the socket case in
    /// `WindowPicker`'s documentation, which never takes a key. Anything typed while the list is
    /// still coming is kept.
    func chooseResponse(_ request: Request) -> Response {
        guard let line = request.args["command"], !line.isEmpty else {
            return .failure(
                id: request.id, code: "usage",
                message: "choose needs '<list command> | <action command>'")
        }

        let command: ChooseCommand
        do {
            command = try ChooseCommand.parse(line)
            // Both resolved before anything is shown, so a missing action is reported now rather
            // than after someone has picked a line.
            _ = try ExecCommand.resolve(command.action[0], searchPath: settings.execPath)
        } catch {
            logger.error("choose '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "notFound", message: "\(error)")
        }

        let listLine = command.list.joined(separator: " ")
        let session = picker.show([], numberKeys: false) { [weak self] row in
            guard let self else { return }
            let argv = command.action(for: row.label)
            do {
                try spawn(argv, describedAs: argv.joined(separator: " "))
            } catch {
                logger.error("choose action for '\(line)' failed: \(error)")
            }
        }

        let output = Pipe()
        let process: Process
        do {
            process = try spawn(command.list, describedAs: listLine, output: output)
        } catch {
            picker.dismiss(restoringFocus: true)
            logger.error("choose '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "notFound", message: "\(error)")
        }

        fill(session: session, from: output, listedBy: listLine)
        stopIfSlow(process, listedBy: listLine)

        return .success(
            id: request.id, text: "choose from '\(listLine)'",
            data: ["pid": String(process.processIdentifier)])
    }

    /// Reads the list command's output and puts it in the panel `session` opened, or takes the
    /// panel down when there is nothing to choose from.
    ///
    /// Read off the main actor: a list longer than the pipe's buffer would otherwise block the
    /// child, and waiting on the main actor would hold every hotkey and the socket.
    private func fill(session: Int, from output: Pipe, listedBy listLine: String) {
        let reader = output.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = reader.readDataToEndOfFile()
            let text = String(bytes: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                guard let self else { return }
                let found = ChooseCommand.rows(fromOutput: text)
                guard !found.isEmpty else {
                    logger.warning("choose: '\(listLine)' listed nothing")
                    if self.picker.session == session { self.picker.dismiss(restoringFocus: true) }
                    return
                }
                self.picker.replaceRows(
                    found.enumerated().map { WindowPicker.Row(id: $0.offset, label: $0.element) },
                    session: session)
            }
        }
    }

    /// Stops a list command still running after `chooseListTimeout`. Its output then ends, and
    /// `fill` shows whatever it had written or takes the panel down.
    private func stopIfSlow(_ process: Process, listedBy listLine: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chooseListTimeout) {
            MainActor.assumeIsolated {
                guard process.isRunning else { return }
                let seconds = Int(Self.chooseListTimeout)
                logger.warning("choose: '\(listLine)' still running after \(seconds)s; stopping it")
                process.terminate()
            }
        }
    }
}
