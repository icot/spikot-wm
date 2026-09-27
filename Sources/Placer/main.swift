import Cocoa
import Foundation
import StateCore

bootstrapLogging()

let config: Config
do {
    config = try Config.load()
} catch {
    FileHandle.standardError.write(Data("spikot-placer: \(error)\n".utf8))
    exit(78)  // EX_CONFIG
}
let state = State(config: config)

state.initialize()

let validArgs = ["0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if arg == "--version" {
        print(spikotVersion)
        exit(0)
    }
    if arg == "--help" || arg == "-h" {
        print("""
            OVERVIEW: Move the frontmost window to a stack

            USAGE: spikot-placer <stack>

            ARGUMENTS:
              <stack>                 Target stack index, one of \(validArgs)

            OPTIONS:
              --version               Show the version.
              -h, --help              Show help information.
            """)
        exit(0)
    }
    if validArgs.contains(arg) {
        let targetStack = Int(arg)!
        let frontmostApp = NSWorkspace.shared.frontmostApplication!
        let pid = frontmostApp.processIdentifier
        if let activeWindow = state.visibleWindows.first(where: { $0.kCGWindowOwnerPID == pid }) {
            // The geometry comes from Geometry.layout, which maps each stack to the display its
            // centre falls on and divides that display's visibleFrame. This used to divide
            // NSScreen.main's full frame by activeMode.count, which was wrong twice over with a
            // second display attached: computeModes prepends an entry for it, so twoColumns
            // reported three stacks and the built-in display was cut into thirds, and the menu
            // bar and Dock were ignored because it used frame rather than visibleFrame.
            guard let placement = state.stackLayout().first(where: { $0.stack == targetStack })
            else {
                print("No placement for stack \(targetStack); \(state.activeMode.count) stacks exist")
                exit(1)
            }

            modifyWindow(
                windowNumber: CGWindowID(activeWindow.kCGWindowNumber),
                newBounds: placement.axFrame)
            if let currentStack = state.stacks.firstIndex(where: { $0.contains(activeWindow) }) {
                state.stacks[currentStack].removeAll(where: { $0 == activeWindow })
                state.stacks[targetStack].insert(activeWindow, at: 0)
                state.flushCurrentState()
                print("Moved \(activeWindow.kCGWindowOwnerName) to stack \(targetStack)")
            }
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    state.flushCurrentState()
    print("Missing argument: must supply one of \(validArgs)")
    print(state.sprintfStacks())
}
