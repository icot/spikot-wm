// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import StateCore

@Suite("Launch cycling")
struct LaunchCycleTests {
    // Front to back, as CGWindowList reports them.
    let emacsA = Fixtures.window(number: 1, owner: "Emacs", pid: 10, coordX: 0, width: 756)
    let emacsB = Fixtures.window(number: 2, owner: "Emacs", pid: 10, coordX: 756, width: 756)
    let emacsC = Fixtures.window(number: 3, owner: "Emacs", pid: 10, coordX: 0, width: 756)
    let ghostty = Fixtures.window(number: 4, owner: "Ghostty", pid: 20, coordX: 756, width: 756)

    @Test("With two windows and the application frontmost, the other one is next")
    func alternates() {
        let next = LaunchCycle.next(in: [emacsA, emacsB], frontmostPID: 10)
        #expect(next?.kCGWindowNumber == 2)
    }

    @Test("Raising the backmost visits every window in as many presses as there are windows")
    func visitsAll() {
        var order = [emacsA, emacsB, emacsC]
        var visited: [Int] = []
        for _ in order.indices {
            guard let next = LaunchCycle.next(in: order, frontmostPID: 10) else { break }
            visited.append(next.kCGWindowNumber)
            // What the window server does on a raise: the window moves to the front.
            order.removeAll { $0.kCGWindowNumber == next.kCGWindowNumber }
            order.insert(next, at: 0)
        }
        #expect(visited == [3, 2, 1])
    }

    @Test("No cycle when the application is not frontmost")
    func notFrontmost() {
        #expect(LaunchCycle.next(in: [emacsA, emacsB], frontmostPID: 20) == nil)
        #expect(LaunchCycle.next(in: [emacsA, emacsB], frontmostPID: nil) == nil)
    }

    @Test("No cycle with a single window")
    func single() {
        #expect(LaunchCycle.next(in: [emacsA], frontmostPID: 10) == nil)
    }

    @Test("Stays within the frontmost process when the name matched two applications")
    func ownProcessOnly() {
        let next = LaunchCycle.next(in: [emacsA, emacsB, ghostty], frontmostPID: 10)
        #expect(next?.kCGWindowNumber == 2)
    }
}
