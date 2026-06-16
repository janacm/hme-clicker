// HideMyEmailClicker.swift
// macOS Sonoma (15.x) – Clicks the “Hide My Email” tile in System Settings
// Build:  swiftc HideMyEmailClicker.swift -o HideMyEmailClicker
// Usage: ./HideMyEmailClicker [label text]  (after granting Accessibility permission)
//   The optional [label text] is typed into the LABEL field of the new address.

import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - Helper functions

/// Prompt the user for Accessibility permission if not already granted.
func requireAccessibilityPermission() {
    let optPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let allowed = AXIsProcessTrustedWithOptions([optPrompt as String: true] as CFDictionary)
    if !allowed {
        // The app will exit – user must re‑run after granting permission.
        exit(1)
    }
}

/// Adds a explicit wait with a message
func waitWithMessage(_ seconds: UInt32, message: String) {
    print(message)
    sleep(seconds)
}

/// Wait for a specific UI element to appear, with timeout
func waitForElement(in root: AXUIElement, timeout: UInt32 = 5, predicate: @escaping (AXUIElement) -> Bool) -> AXUIElement? {
    print("Waiting for element (timeout: \(timeout)s)...")
    
    for attempt in 1...Int(timeout) {
        if let element = findAXElement(in: root, predicate: predicate) {
            print("✓ Element found after \(attempt) seconds")
            return element
        }
        
        sleep(1)
        print("  Still waiting... (\(attempt)/\(timeout))")
    }
    
    print("✗ Element not found after \(timeout) seconds")
    return nil
}

/// Check if window is fully loaded by looking for key elements
func isWindowFullyLoaded(_ windowElement: AXUIElement) -> Bool {
    var title: AnyObject?
    _ = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)
    
    if let windowTitle = title as? String, 
       (windowTitle == "iCloud" || windowTitle.contains("Apple ID") || windowTitle.contains("Settings")) {
        print("Window appears to be loaded with title: \"\(windowTitle)\"")
        
        // Check for essential UI elements that should be present
        let hasContent = findAXElement(in: windowElement) { elem in
            var role: AnyObject?
            _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
            let roleStr = (role as? String) ?? ""
            
            if roleStr == "AXGroup" || roleStr == "AXScrollArea" {
                return true
            }
            return false
        } != nil
        
        return hasContent
    }
    
    return false
}

/// Recursively walk the accessibility tree, returning the first element that satisfies `predicate`.
func findAXElement(in root: AXUIElement, predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(root) { return root }
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children) == .success,
          let kids = children as? [AXUIElement] else { return nil }
    for child in kids {
        if let found = findAXElement(in: child, predicate: predicate) { return found }
    }
    return nil
}

/// Convenience for reading string attributes
func stringValue(of element: AXUIElement, attr: CFString) -> String? {
    var v: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attr, &v) == .success else { return nil }
    return v as? String
}
/// Get all accessibility attributes for an element
func getAXAttributes(_ element: AXUIElement) -> (role: String, value: String, title: String, desc: String, id: String, help: String) {
    var role: AnyObject?
    var value: AnyObject?
    var identifier: AnyObject?
    var desc: AnyObject?
    var title: AnyObject?
    var help: AnyObject?
    var subrole: AnyObject?
    
    // Get all the attributes that might help identify the element
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    _ = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
    _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
    _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    _ = AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &help)
    _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    
    let roleStr = (role as? String) ?? "unknown"
    let subroleStr = (subrole as? String) ?? ""
    let valueStr = (value as? String) ?? ""
    let idStr = (identifier as? String) ?? ""
    let descStr = (desc as? String) ?? ""
    let titleStr = (title as? String) ?? ""
    let helpStr = (help as? String) ?? ""
    
    // Include subrole in the role if available
    let fullRoleStr = subroleStr.isEmpty ? roleStr : "\(roleStr).\(subroleStr)"
    
    return (fullRoleStr, valueStr, titleStr, descStr, idStr, helpStr)
}

/// Check if an element might match our target based on text content
func elementContainsText(_ element: AXUIElement, keywords: [String]) -> Bool {
    let attrs = getAXAttributes(element)
    
    // Check all text attributes
    let allText = [attrs.value, attrs.title, attrs.desc, attrs.id, attrs.help]
    
    for text in allText {
        for keyword in keywords {
            if text.contains(keyword) {
                return true
            }
        }
    }
    
    return false
}

/// Click on an element, walking up the hierarchy if needed
func clickElement(_ element: AXUIElement) -> Bool {
    var current: AXUIElement? = element
    var maxAttempts = 10  // Prevent infinite loops
    
    while let elem = current, maxAttempts > 0 {
        maxAttempts -= 1
        
        // Try to get actions for this element
        var actionsCF: CFArray?
        let result = AXUIElementCopyActionNames(elem, &actionsCF)
        
        if result == .success, let actions = actionsCF as NSArray?, let acts = actions as? [String] {
            // Debug: print available actions
            print("Available actions: \(acts.joined(separator: ", "))")
            
            if acts.contains(kAXPressAction as String) {
                // Try to press the element
                print("Attempting to press element...")
                let pressResult = AXUIElementPerformAction(elem, kAXPressAction as CFString)
                
                if pressResult == .success {
                    print("✓ Element pressed successfully")
                    return true
                } else {
                    print("✗ Failed to press element: \(pressResult)")
                }
            }
        }
        
        // Move up to parent
        var parent: AnyObject?
        if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) != .success {
            break
        }
        current = (parent as! AXUIElement)
    }
    
    print("✗ Could not find a pressable element in the hierarchy")
    return false
}

/// Recursively dump the accessibility hierarchy for debugging
func dumpAXHierarchy(element: AXUIElement, indent: String = "", maxDepth: Int = 3, currentDepth: Int = 0) throws {
    // Get all attributes for this element
    let attrs = getAXAttributes(element)
    
    // Print element info with all attributes
    print("\(indent)[\(attrs.role)] Value: \"\(attrs.value)\" Title: \"\(attrs.title)\" ID: \"\(attrs.id)\" Desc: \"\(attrs.desc)\" Help: \"\(attrs.help)\"")
    
    // Depth limit check
    if currentDepth >= maxDepth {
        print("\(indent)... (max depth reached)")
        return
    }
    
    // Get children with error handling
    var children: AnyObject?
    let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
    
    if childrenResult != .success {
        print("\(indent)  [No children or error getting children]")
        return
    }
    
    guard let kids = children as? [AXUIElement] else {
        print("\(indent)  [Invalid children type]")
        return
    }
    
    if kids.isEmpty {
        print("\(indent)  [Empty children array]")
        return
    }
    
    // Process each child
    for (index, child) in kids.enumerated() {
        if index >= 50 && kids.count > 60 {  // Limit output for very large arrays
            print("\(indent)  ... (\(kids.count - index) more children)")
            break
        }
        do {
            try dumpAXHierarchy(element: child, indent: indent + "  ", maxDepth: maxDepth, currentDepth: currentDepth + 1)
        } catch {
            print("\(indent)  [Error processing child: \(error)]")
        }
    }
}

/// Find the modal sheet (e.g. the Hide My Email panel) within a root element.
func findSheet(in root: AXUIElement) -> AXUIElement? {
    return findAXElement(in: root) { elem in
        var role: AnyObject?
        _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
        return (role as? String) == "AXSheet"
    }
}

/// Predicate that identifies the "+" / add button used to create a new address.
/// Standard macOS add buttons (NSAddTemplate) expose an accessibility
/// description of "add"; we also accept a literal "+" title to be safe.
/// Exact matches are used to avoid false positives like the
/// "Deactivate email address" button (which contains the substring "add").
func isAddButton(_ elem: AXUIElement) -> Bool {
    var role: AnyObject?
    _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
    guard (role as? String) == "AXButton" else { return false }

    let attrs = getAXAttributes(elem)
    let title = attrs.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titleLower = title.lowercased()
    let desc = attrs.desc.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let id = attrs.id.lowercased()

    // The Hide My Email sheet is a WebKit view; its add control is an
    // AXButton labelled "Create New Address" rather than a native "+" button.
    if titleLower.contains("create new address") || titleLower.contains("new address") { return true }
    if desc.contains("create new address") || desc.contains("new address") { return true }

    // Native macOS add buttons (NSAddTemplate) expose a "+" title or an
    // accessibility description of "add".
    if title == "+" { return true }
    if desc == "add" || desc == "add item" || desc == "new" { return true }
    if id == "add" || id.hasSuffix(":add") || id.hasSuffix("addbutton") { return true }
    return false
}

/// Locate the "+" (add) button inside the Hide My Email sheet and press it.
/// Retries for a few seconds because the sheet may still be rendering.
func pressAddButton(in appRoot: AXUIElement) -> Bool {
    for attempt in 1...5 {
        // Prefer searching within the sheet to reduce false positives.
        let searchRoot = findSheet(in: appRoot) ?? appRoot

        if let addButton = findAXElement(in: searchRoot, predicate: isAddButton) {
            print("Found '+' add button (attempt \(attempt)), pressing...")
            if AXUIElementPerformAction(addButton, kAXPressAction as CFString) == .success {
                return true
            }
            print("\u{2717} Press failed, will retry...")
        } else {
            print("  '+' button not found yet (\(attempt)/5)...")
        }
        sleep(1)
    }

    // Debug aid: dump the sheet so we can see the actual button attributes.
    if let sheet = findSheet(in: appRoot) {
        print("\nDumping Hide My Email sheet hierarchy for debugging...")
        try? dumpAXHierarchy(element: sheet, maxDepth: 6)
    }
    return false
}

/// Read a single string attribute, returning "" when absent.
func stringAttr(_ elem: AXUIElement, _ attr: CFString) -> String {
    var v: AnyObject?
    _ = AXUIElementCopyAttributeValue(elem, attr, &v)
    return (v as? String) ?? ""
}

/// Predicate that identifies the LABEL text field in the "new address" dialog.
/// That field's placeholder is "Label Your Email"; the NOTE field's placeholder
/// is "Make a Note (Optional)", so matching on "label" is unambiguous.
func isLabelField(_ elem: AXUIElement) -> Bool {
    var role: AnyObject?
    _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
    let roleStr = (role as? String) ?? ""
    guard roleStr == "AXTextField" || roleStr == "AXTextArea" else { return false }

    let haystacks = [
        stringAttr(elem, kAXPlaceholderValueAttribute as CFString),
        stringAttr(elem, kAXTitleAttribute as CFString),
        stringAttr(elem, kAXDescriptionAttribute as CFString),
        stringAttr(elem, kAXIdentifierAttribute as CFString),
        stringAttr(elem, kAXHelpAttribute as CFString),
    ].map { $0.lowercased() }

    return haystacks.contains { $0.contains("label") }
}

/// Type a string into the currently focused field using synthesized key events.
/// Used as a fallback when setting AXValue directly does not take effect (common
/// for WebKit-backed fields).
func typeString(_ text: String) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    for char in text {
        var units = Array(String(char).utf16)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.post(tap: .cghidEventTap)
        }
        usleep(8000)
    }
}

/// Locate the LABEL field in the "new address" dialog and fill it with `text`.
/// Tries to set the value via accessibility first, then falls back to typing.
func fillLabelField(in appRoot: AXUIElement, with text: String) -> Bool {
    for attempt in 1...5 {
        if let field = findAXElement(in: appRoot, predicate: isLabelField) {
            print("Found LABEL field (attempt \(attempt)), filling it...")

            // Focus the field so the app registers the edit.
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            usleep(200_000)

            // Attempt 1: set the value directly.
            let setResult = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFTypeRef)
            if setResult == .success, stringAttr(field, kAXValueAttribute as CFString) == text {
                return true
            }

            // Attempt 2: type the text into the focused field.
            print("Direct set didn't take; typing the text instead...")
            typeString(text)
            usleep(200_000)
            let now = stringAttr(field, kAXValueAttribute as CFString)
            if now == text || now.contains(text) {
                return true
            }
            print("\u{2717} LABEL field still reads \"\(now)\" after typing; will retry...")
        } else {
            print("  LABEL field not found yet (\(attempt)/5)...")
        }
        sleep(1)
    }

    if let sheet = findSheet(in: appRoot) {
        print("\nDumping new-address dialog hierarchy for debugging...")
        try? dumpAXHierarchy(element: sheet, maxDepth: 8)
    }
    return false
}

// MARK: - Main logic

print("Starting HideMyEmailClicker...")
requireAccessibilityPermission()
print("Accessibility permission confirmed")

// Optional CLI argument: text used to fill the LABEL field of the new address.
// All arguments are joined so the label can be passed with or without quoting.
let labelText = CommandLine.arguments.dropFirst().joined(separator: " ")
if labelText.isEmpty {
    print("No LABEL argument provided; the LABEL field will be left empty.")
} else {
    print("LABEL argument: \"\(labelText)\"")
}

// Define retry parameters
let maxRetries = 3
var retryCount = 0
var success = false

while retryCount < maxRetries && !success {
    if retryCount > 0 {
        print("\n--------- RETRY ATTEMPT \(retryCount) of \(maxRetries) ---------\n")
    }
    
    // 1) Open System Settings directly on the iCloud screen (URL scheme works on Sonoma 14+/15+)
    print("Opening System Settings...")
    if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud") {
        NSWorkspace.shared.open(url)
        print("Opened System Settings with URL scheme")
    } else {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        print("Opened System Settings with file path")
    }
    
    // 2) Give the UI a moment to appear
    waitWithMessage(3, message: "Waiting for UI to load (3 seconds)...")
    
    // 3) Obtain the AXUIElement for System Settings
    print("Looking for System Settings app...")
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
    
    guard let settingsApp = runningApps.first else {
        print("ERROR: System Settings app not found in running applications")
        retryCount += 1
        continue
    }
    
    // Verify the app is active and frontmost
    print("System Settings found with PID: \(settingsApp.processIdentifier)")
    if !settingsApp.isActive {
        print("WARNING: System Settings is not the active application")
        print("Attempting to activate System Settings...")
        _ = settingsApp.activate(options: .activateIgnoringOtherApps)
        waitWithMessage(2, message: "Waiting for app to activate (2 seconds)...")
    }
    
    // Create the accessibility element for the app
    print("Creating accessibility element for System Settings...")
    let settingsAX = AXUIElementCreateApplication(settingsApp.processIdentifier)
    
    // Verify we have a main window
var windowValue: AnyObject?
print("Checking for main window...")
let windowResult = AXUIElementCopyAttributeValue(settingsAX, kAXMainWindowAttribute as CFString, &windowValue)
if windowResult != .success || windowValue == nil {
    print("WARNING: Could not find main window. System Settings might not be fully loaded.")
    waitWithMessage(2, message: "Waiting for window to appear (2 seconds)...")
    
    // Check again after waiting
    let secondWindowResult = AXUIElementCopyAttributeValue(settingsAX, kAXMainWindowAttribute as CFString, &windowValue)
    if secondWindowResult != .success || windowValue == nil {
        print("ERROR: Still could not find main window after waiting")
        retryCount += 1
        continue
    }
}

// Print the UI hierarchy for debugging
print("Dumping top-level UI hierarchy for System Settings...")
do {
    try dumpAXHierarchy(element: settingsAX, maxDepth: 4)
    print("UI hierarchy dump completed")
} catch {
    print("ERROR: Failed to dump UI hierarchy: \(error)")
}

// 4) First, find and click on "iCloud+ Features" to expand that section
print("\nSearching for 'iCloud+ Features' section...")

let featuresLabel = findAXElement(in: settingsAX) { elem in
    var role: AnyObject?
    _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
    let roleStr = (role as? String) ?? ""
    
    // Check for text roles
    if roleStr == "AXStaticText" || roleStr == "AXButton" || roleStr == "AXGroup" || roleStr == "AXLink" {
        // Check value attribute
        if let s = stringValue(of: elem, attr: kAXValueAttribute as CFString) {
            if s == "iCloud+ Features" {
                print("Found iCloud+ Features text: \"\(s)\" with role: \(roleStr)")
                return true
            }
        }
        
        // Check title attribute
        if let s = stringValue(of: elem, attr: kAXTitleAttribute as CFString) {
            if s == "iCloud+ Features" {
                print("Found iCloud+ Features title: \"\(s)\" with role: \(roleStr)")
                return true
            }
        }
    }
    return false
}

// Click on the iCloud+ Features element or its parent to expand the section
if let featuresElem = featuresLabel {
    print("Found iCloud+ Features element, looking for clickable parent...")
    
    // Find a clickable parent
    var clickable: AXUIElement? = featuresElem
    var foundClickable = false
    
    while let elem = clickable {
        var actionsCF: CFArray?
        if AXUIElementCopyActionNames(elem, &actionsCF) == .success,
           let actions = actionsCF as NSArray?,
           let acts = actions as? [String], 
           acts.contains(kAXPressAction as String) {
            
            print("Found clickable parent for iCloud+ Features, clicking it...")
            AXUIElementPerformAction(elem, kAXPressAction as CFString)
            foundClickable = true
            
            
            // Wait for UI to update after clicking
            print("Waiting for section to expand (2 seconds)...")
            sleep(2)
            // Break out of the loop once we've clicked
            break
        }
        
        var parent: AnyObject?
        if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) != .success {
            break // hit the root – give up
        }
        clickable = (parent as! AXUIElement)
    }
    
    if !foundClickable {
        print("WARNING: Could not find a clickable parent for iCloud+ Features")
    }
    
    // Re-dump UI hierarchy after clicking to see the expanded state
    print("\nDumping updated UI hierarchy after clicking iCloud+ Features...")
    do {
        try dumpAXHierarchy(element: settingsAX, maxDepth: 5)
        print("Updated UI hierarchy dump completed")
    } catch {
        print("ERROR: Failed to dump updated UI hierarchy: \(error)")
    }
} else {
    print("WARNING: Could not find iCloud+ Features section")
    retryCount += 1
    continue
}
// 5) Now, find any element that contains "Hide My Email" text
print("\nSearching for 'Hide My Email' label or similar text...")

// Define possible variations of the label
let possibleLabels = ["Hide My Email", "Hide My E-mail", "iCloud+ Hide My Email", "Hide My Email+", "HideMy Email"]

let hideLabel = findAXElement(in: settingsAX) { elem in
    var role: AnyObject?
    _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
    let roleStr = (role as? String) ?? ""
    
    // Check all interactive and text elements
    if roleStr == "AXStaticText" || roleStr == "AXButton" || roleStr == "AXLink" || 
       roleStr == "AXGroup" || roleStr == "AXImage" || roleStr == "AXTextField" {
        
        // Check all possible attributes that might contain our text
        let attributes = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
        
        for attribute in attributes {
            if let s = stringValue(of: elem, attr: attribute as CFString), !s.isEmpty {
                // Check against all possible variations of the label
                for label in possibleLabels {
                    if s.contains(label) {
                        print("Found matching text: \"\(s)\" with role: \(roleStr), attribute: \(attribute)")
                        return true
                    }
                }
            }
        }
    }
    return false
}
guard let label = hideLabel else {
    // Try to find what text elements actually exist
    print("\nFailed to find 'Hide My Email'. Listing relevant text elements:")
    var textElements = [(role: String, value: String, title: String, desc: String)]()
    
    // Search with more detailed information
    _ = findAXElement(in: settingsAX) { elem in
        var role: AnyObject?
        var value: AnyObject?
        var title: AnyObject?
        var desc: AnyObject?
        
        _ = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
        _ = AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &value)
        _ = AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &title)
        _ = AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &desc)
        
        let roleStr = (role as? String) ?? "unknown"
        let valueStr = (value as? String) ?? ""
        let titleStr = (title as? String) ?? ""
        let descStr = (desc as? String) ?? ""
        
        // Look for any interactive elements or elements with text
        let isInteractive = (roleStr == "AXStaticText" || roleStr == "AXButton" || roleStr == "AXLink" || 
                            roleStr == "AXGroup" || roleStr == "AXImage" || roleStr == "AXMenuItem")
        let hasText = !valueStr.isEmpty || !titleStr.isEmpty || !descStr.isEmpty
        
        if isInteractive && hasText {
            textElements.append((roleStr, valueStr, titleStr, descStr))
        }
        
        return false // Keep searching through all elements
    }
    
    // Print found text elements
    print("\nFound text elements that might be relevant:")
    for (i, elem) in textElements.sorted(by: { $0.value < $1.value }).enumerated() {
        print("\(i+1). [\(elem.role)] Value: \"\(elem.value)\" Title: \"\(elem.title)\" Desc: \"\(elem.desc)\"")
    }
    
    // Look for elements that might be similar to what we want
    print("\nElements containing 'email', 'iCloud', 'privacy', or '+':")
    let keywords = ["email", "Email", "iCloud", "Privacy", "private", "+"]
    let filtered = textElements.filter { elem in
        for keyword in keywords {
            if elem.value.contains(keyword) || elem.title.contains(keyword) || elem.desc.contains(keyword) {
                return true
            }
        }
        return false
    }
    
    for (i, elem) in filtered.enumerated() {
        print("\(i+1). [\(elem.role)] Value: \"\(elem.value)\" Title: \"\(elem.title)\" Desc: \"\(elem.desc)\"")
    }
    
    print("Failed to find Hide My Email label – Retrying...")
    retryCount += 1
    continue
}

// We found what we were looking for
success = true

// 5) Walk up to a parent that supports AXPress and click it
var clickable: AXUIElement? = label
while let elem = clickable {
    var actionsCF: CFArray?
    if AXUIElementCopyActionNames(elem, &actionsCF) == .success,
       let actions = actionsCF as NSArray?,
       let acts = actions as? [String], 
       acts.contains(kAXPressAction as String) {
        AXUIElementPerformAction(elem, kAXPressAction as CFString)
        print("✔︎ Hide My Email clicked")

        // The click opens the "Hide My Email" sheet. Now press the "+" (add)
        // button in that sheet to start creating a new address.
        print("Waiting for Hide My Email sheet to appear (2 seconds)...")
        sleep(2)

        if pressAddButton(in: settingsAX) {
            print("✔︎ 'Create New Address' button pressed")

            if labelText.isEmpty {
                exit(0)
            }

            // The add button opens the "new address" dialog with a LABEL field.
            print("Waiting for the new-address dialog to appear (2 seconds)...")
            sleep(2)

            if fillLabelField(in: settingsAX, with: labelText) {
                print("✔︎ LABEL field set to \"\(labelText)\"")
                exit(0)
            } else {
                print("✘ Could not fill the LABEL field – UI may have changed.")
                exit(1)
            }
        } else {
            print("✘ Could not find or press the 'Create New Address' button – UI may have changed.")
            exit(1)
        }
    }
    var parent: AnyObject?
    if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) != .success {
        break // hit the root – give up
    }
    clickable = (parent as! AXUIElement)
}

print("✘ Could not find a clickable parent for Hide My Email – UI may have changed.")
retryCount += 1
}

// If we get here, we've exhausted all retry attempts
if !success {
    fatalError("Failed to find and click Hide My Email after \(maxRetries) attempts – UI layout may have changed.")
}
