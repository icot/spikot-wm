# Code Improvement Suggestions

This document contains suggestions for improving the spikot-wm codebase.

## 1. Fix Force Unwraps (55 instances) - HIGH PRIORITY

The codebase has extensive use of force unwraps (`!`) which can cause crashes at runtime.

### Critical Issues

**state.swift:79-80** - Crash risk when window not found in cache:
```swift
// Current (unsafe):
let window = cachedState!.visibleWindows.first(where: { $0.kCGWindowNumber == windowM.kCGWindowNumber })!

// Suggested:
guard let window = cachedState?.visibleWindows.first(where: {
    $0.kCGWindowNumber == windowM.kCGWindowNumber
}) else {
    logger.warning("Window \(windowM.kCGWindowNumber) not found in cache")
    continue
}
```

**state.swift:164-166** - Known bug with multiple windows per process:
```swift
// Current (unsafe):
let frontWin: Window? = self.visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontPID })
return windowInColumn(window: frontWin!, mode: self.activeMode) ?? -1

// Suggested:
guard let frontWin = self.visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontPID }),
      let column = windowInColumn(window: frontWin, mode: self.activeMode) else {
    return nil  // Change return type to Int?
}
return column
```

**state.swift:177-179** - File operations can fail:
```swift
// Current (unsafe):
let fileH = try? FileHandle.init(forWritingTo: self.cacheURL)
fileH!.write(jData!)

// Suggested:
guard let fileH = try? FileHandle(forWritingTo: self.cacheURL),
      let jData = jData else {
    logger.error("Failed to write state to \(self.cacheURL.path)")
    return
}
do {
    try fileH.write(contentsOf: jData)
} catch {
    logger.error("Write error: \(error)")
}
```

**state.swift:238** - Mode lookup can fail:
```swift
// Current (unsafe):
self.activeMode = self.modes[self.config.activeMode]!

// Suggested:
guard let mode = self.modes[self.config.activeMode] else {
    logger.error("Invalid mode: \(self.config.activeMode)")
    fatalError("Invalid mode configuration")
}
self.activeMode = mode
```

## 2. Fix Window Filtering Bug - HIGH PRIORITY

**state.swift:81** - Bug in closed window removal:
```swift
// Current (wrong - keeps matching windows):
newStacks[id] = stack.filter({$0 == window })

// Should be (removes matching windows):
newStacks[id] = stack.filter({$0 != window })
```

This bug prevents closed windows from being removed from stacks.

## 3. Configuration Management - MEDIUM PRIORITY

Configuration is currently hardcoded in main.swift files:

**State/main.swift:41-44** and **Placer/main.swift:7-10**:
```swift
let state = State(gap: 5,
                  activeMode: "twoColumns",
                  cachePath: ".spikot-wm-state.json",
                  useCache: true)
```

### Suggested Approach

Add configuration file support with defaults:

```swift
// Add to Config struct in types.swift
extension Config {
    static let `default` = Config(
        gap: 5,
        activeMode: "twoColumns",
        cachePath: ".spikot-wm-state.json",
        useCache: true
    )

    static func load(from path: String = "~/.spikot-wm.json") -> Config? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(Config.self, from: data)
    }
}

// Then in main.swift:
let config = Config.load() ?? .default
let state = State(config: config)
```

### Configuration File Format

```json
{
  "gap": 10,
  "activeMode": "threeColumns",
  "cachePath": ".spikot-wm-state.json",
  "useCache": true
}
```

## 4. Fix Multi-Window Bug - MEDIUM PRIORITY

The `currentStack()` method at state.swift:162 has a known bug when multiple windows per process exist (e.g., multiple browser windows).

### Root Cause

It uses `NSWorkspace.shared.frontmostApplication!.processIdentifier` which only gives the process ID, not the specific focused window.

### Suggested Solution

Use the Accessibility API to get the actual focused window:

```swift
public func currentStack() -> Int? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        return nil
    }

    // Get the actual focused window using Accessibility API
    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    var focusedWindowRef: CFTypeRef?

    guard AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &focusedWindowRef
    ) == .success else {
        // Fallback to first window of process
        guard let frontWin = self.visibleWindows.first(where: {
            $0.kCGWindowOwnerPID == frontApp.processIdentifier
        }) else {
            return nil
        }
        return windowInColumn(window: frontWin, mode: self.activeMode)
    }

    // Match the focused window against our visible windows
    // This requires additional work to match AXUIElement to Window
    // ...

    return windowInColumn(window: matchedWindow, mode: self.activeMode)
}
```

Note: This requires additional work to match the AXUIElement window to the CGWindow representation.

## 5. Type Safety for Stack Operations - MEDIUM PRIORITY

Stack indices and directions are passed as strings and converted to Int, which is error-prone.

**State/main.swift:58-59**:
```swift
if arg == "up" || arg == "down" {
    state.rotateStack(direction: arg)
} else {
    state.switchStack(toStack: arg)
}
```

### Suggested Approach

Create type-safe enums:

```swift
// Add to types.swift
enum StackDirection {
    case up, down, left, right

    init?(_ string: String) {
        switch string {
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        default: return nil
        }
    }
}

enum StackTarget {
    case direction(StackDirection)
    case index(Int)

    init?(_ string: String) {
        if let direction = StackDirection(string) {
            self = .direction(direction)
        } else if let index = Int(string) {
            self = .index(index)
        } else {
            return nil
        }
    }
}

// Update State methods
public func rotateStack(direction: StackDirection) { ... }
public func switchStack(target: StackTarget) { ... }
```

## 6. Add Result Types for Operations - MEDIUM PRIORITY

Methods like `rotateStack` and `switchStack` don't return success/failure, making error handling impossible.

### Suggested Approach

```swift
public enum StackOperationError: Error {
    case invalidStack
    case noWindows
    case emptyStack
    case activationFailed
}

public func rotateStack(direction: StackDirection) -> Result<Void, StackOperationError> {
    guard let current = currentStack(), current >= 0 else {
        return .failure(.invalidStack)
    }

    guard stacks[current].count > 1 else {
        return .failure(.emptyStack)
    }

    // Perform rotation...

    return .success(())
}

public func switchStack(target: StackTarget) -> Result<Void, StackOperationError> {
    // Implementation...
}
```

Then in main.swift:
```swift
let result = state.rotateStack(direction: .up)
switch result {
case .success:
    print("Stack rotated successfully")
case .failure(let error):
    print("Error: \(error)")
    exit(1)
}
```

## 7. Separate Concerns in State Class - LOW PRIORITY

The `State` class handles too many responsibilities:
- Window management
- Stack computation
- State caching/persistence
- Display formatting (listWindows, sprintfStacks)
- File I/O

### Suggested Refactoring

```swift
// StateManager.swift - Core window/stack logic
public class StateManager {
    var visibleWindows: [Window] = []
    var stacks: [[Window]] = []
    var activeMode: [Int] = []

    func computeStacks() { ... }
    func rotateStack(...) { ... }
    func switchStack(...) { ... }
}

// StateCache.swift - Persistence logic
public class StateCache {
    let cacheURL: URL

    func save(_ state: StateManager) throws { ... }
    func load() throws -> StateManager? { ... }
}

// StateFormatter.swift - Display formatting
public struct StateFormatter {
    static func listWindows(_ windows: [Window]) -> String { ... }
    static func sprintfStacks(_ stacks: [[Window]]) -> String { ... }
}

// State.swift - Coordinator
public class State {
    let manager: StateManager
    let cache: StateCache
    let config: Config

    public func initialize() {
        manager.computeStacks()
        if let cached = try? cache.load() {
            manager.merge(with: cached)
        }
    }
}
```

## 8. Remove Debug Code - LOW PRIORITY

**state.swift:181** - Remove stray debug dump:
```swift
public func flushCurrentState() {
    // ... existing code ...

    dump(NSApplication.shared.windows)  // DELETE THIS LINE
}
```

## 9. Improve Rotation Bug - MEDIUM PRIORITY

**state.swift:279** - Comment mentions rotation down might be buggy:
```swift
// TODO Buggy somehow?. It might me mismatch during state merging causing the wrong stack order
self.stacks[self.currentStack()].append(self.stacks[self.currentStack()].removeFirst())
```

### Investigation Needed

The bug might be related to state merging logic. Need to:
1. Add logging to track stack order before/after rotation
2. Verify the cached state is being properly updated
3. Test with multiple rotations in sequence

## 10. Add Command-Line Argument Parsing

Currently uses basic `CommandLine.arguments` checking. Consider using a proper argument parser for better UX.

### Suggested Libraries

- Swift Argument Parser (Apple's official library)
- Or keep it simple with better manual parsing

Example with Swift Argument Parser:
```swift
import ArgumentParser

@main
struct SpikotWM: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "A tiling window manager for macOS"
    )

    @Option(name: .shortAndLong, help: "Active mode (twoColumns, threeColumns)")
    var mode: String = "twoColumns"

    @Option(name: .shortAndLong, help: "Gap size between windows")
    var gap: Int = 5

    @Flag(name: .long, help: "Disable cache")
    var noCache: Bool = false

    @Argument(help: "Command to execute")
    var command: Command

    enum Command: String, ExpressibleByArgument {
        case state, list, move, focus
    }

    func run() throws {
        let config = Config(gap: gap, activeMode: mode,
                           cachePath: ".spikot-wm-state.json",
                           useCache: !noCache)
        let state = State(config: config)
        state.initialize()

        // Execute command...
    }
}
```

## Priority Summary

### High Priority (Crash Risk)
1. Fix force unwraps throughout codebase
2. Fix window filtering bug (state.swift:81)

### Medium Priority (Functionality Issues)
3. Add configuration file support
4. Fix multi-window bug with Accessibility API
5. Add Result types for error handling
6. Type safety for stack operations
7. Investigate and fix rotation down bug

### Low Priority (Code Quality)
8. Separate concerns in State class
9. Remove debug code
10. Add proper command-line argument parsing

## Testing Recommendations

Once the above changes are made, consider adding:
- Unit tests for window matching logic
- Unit tests for stack computation
- Integration tests for state merging
- Tests for configuration loading
- Tests for error cases (missing windows, invalid stacks, etc.)
