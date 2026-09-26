import Cocoa

// https://stackoverflow.com/questions/58675555/how-to-grant-accessibilty-access-in-xcode
func checkAccess() -> Bool {
    // AXUIElement.h declares kAXTrustedCheckOptionPrompt as a non-const `extern
    // CFStringRef`, so Swift 6 imports it as a mutable global and rejects reading it
    // from concurrency-checked code. Its documented value is used directly instead.
    let checkOptPrompt = "AXTrustedCheckOptionPrompt" as NSString
    // set the options: false means it wont ask
    // true means it will popup and ask
    let options = [checkOptPrompt: true]
    // translate into boolean value
    let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary?)

    if accessEnabled == true {
        print("Access Granted")
    } else {
        print("Access not allowed")
    }
    return accessEnabled
}
