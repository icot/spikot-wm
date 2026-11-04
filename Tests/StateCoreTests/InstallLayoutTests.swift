import Testing

@testable import StateCore

@Suite("Install layout")
struct InstallLayoutTests {
    @Test("An executable in a Homebrew keg is a Homebrew install, with the prefix before Cellar")
    func homebrewKeg() {
        let layout = InstallLayout.detect(
            executablePath: "/opt/homebrew/Cellar/spikot-wm/0.32.0/bin/spikot-wm")
        #expect(layout == .homebrew(prefix: "/opt/homebrew"))
        #expect(layout.agentLogs == "/opt/homebrew/var/log/spikot-wm/")
        #expect(layout.agentStatus == "brew services info spikot-wm")
    }

    @Test("The agent inside the keg's app bundle is a Homebrew install too")
    func homebrewAgent() {
        let layout = InstallLayout.detect(
            executablePath:
                "/opt/homebrew/Cellar/spikot-wm/0.32.0/SpikotWM.app/Contents/MacOS/spikot-agent")
        #expect(layout == .homebrew(prefix: "/opt/homebrew"))
    }

    @Test("Anything else is a build from source", arguments: [
        "/Users/someone/.local/bin/spikot-wm",
        "/Users/someone/Applications/SpikotWM.app/Contents/MacOS/spikot-agent",
        "/Users/someone/src/spikot-win/.build/debug/spikot-wm",
        // Another formula's keg is not this one.
        "/opt/homebrew/Cellar/other/1.0/bin/spikot-wm",
        "",
    ])
    func source(path: String) {
        #expect(InstallLayout.detect(executablePath: path) == .source)
    }
}
