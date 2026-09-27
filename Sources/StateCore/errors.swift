import Foundation

/// Why a focus or rotation request could not be carried out.
///
/// These used to be force-unwraps: `stacks[targetStack].first!` trapped on an
/// out-of-range or empty stack, and `moves[toStack]!` trapped on an unrecognised
/// direction. The CLI maps them to exit codes.
public enum StackError: Error, CustomStringConvertible, Equatable {
    case noStacks
    case noCurrentStack
    case stackOutOfRange(Int, count: Int)
    case emptyStack(Int)
    case unknownTarget(String)
    case unknownWindow(Int)
    case unknownProcess(Int32)

    public var description: String {
        switch self {
        case .noStacks:
            return "no stacks are configured for the current display layout"
        case .noCurrentStack:
            return "the frontmost window is not in a managed stack"
        case .stackOutOfRange(let index, let count):
            return "stack \(index) does not exist; the current layout has \(count)"
        case .emptyStack(let index):
            return "stack \(index) has no windows"
        case .unknownTarget(let target):
            return "unrecognised target '\(target)'"
        case .unknownWindow(let number):
            return "no visible window with number \(number)"
        case .unknownProcess(let pid):
            return "no running application with pid \(pid)"
        }
    }
}

extension StackError {
    /// The `Response.Failure.code` this error travels as.
    ///
    /// Lives here rather than in the agent so the mapping and the error cases cannot drift
    /// apart, and so it can be tested. `ExitStatus(errorCode:)` turns these back into exit
    /// codes on the client side.
    public var ipcCode: String {
        switch self {
        case .noStacks: return "noStacks"
        case .noCurrentStack: return "noCurrentStack"
        case .stackOutOfRange: return "stackOutOfRange"
        case .emptyStack: return "emptyStack"
        case .unknownTarget: return "usage"
        case .unknownWindow: return "unknownWindow"
        case .unknownProcess: return "unknownProcess"
        }
    }
}
