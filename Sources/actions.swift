import Cocoa
import Foundation

func switchStack(stacks:[[Window]], currentStack: Int, toStack: String) {
    
    var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
    // boundary safety
    targetStack = (targetStack < 0) ? (activeMode.count - 1) : targetStack
    targetStack = (targetStack > (activeMode.count - 1)) ? 0 : targetStack
    
    NSLog("Switch stack to %d", targetStack)
    
    let targetWindow = stacks[targetStack].first!
    let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
    app?.activate(options: .activateIgnoringOtherApps)
}

func rotateStack(stacks: [[Window]], currentStack: Int, direction: String) {
    // 1. Get stack for frontmostApplication
    // 2. Filter out list of windows in stack
    // 3. Set window active based on direction offset
    let windowsInStack = stacks[currentStack]
    if ((currentStack > -1) && (windowsInStack.count > 1)) {
        // Only operate on managed stacks with more than one window
        // TODO Without stack management it may only switch topmost two windows in stack? (three with
        //      negative offset?. Need to how OSX "stacks" the windows on its own
        let offset = moves[direction]!.offset
        NSLog("Rotating stack %d with offset %d", currentStack, offset)
        let targetWindow: Window = (offset < 0) ?
          windowsInStack[windowsInStack.count + offset] :
          windowsInStack[offset]
        let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
        app?.activate(options: .activateIgnoringOtherApps)

        // up -> stack.insert(a.removeLast(), at:0)
        // down -> stack.append(a.removeFirst())
        
    }
}
