#!/usr/bin/env swift
//
// What macOS actually exposes for a Live Activity pill, and what Casement can make of it.
//
//     swift scripts/live-activity-probe.swift
//
// Run it while a Live Activity is in the menu bar. It needs Accessibility for whatever runs it,
// which is usually Terminal.
//
// Why this exists. Casement mirrors an iPhone Live Activity by reading the pill macOS draws in the
// menu bar through Accessibility. Whether that works is not a yes or no: it depends on how much the
// activity's app exposes, and some expose almost nothing. On 6 October 2026, macOS 27, a cricket
// score showing two teams, a state and a running score exposed exactly three strings: "Live
// Activity", "7:00 pm" and "Expanded". None of them names the app, the teams or the score. Casement
// filters the first and the last as generic labels, is left with a bare time, and declines to mirror
// it rather than cover Apple's correct pill with a worse version of it.
//
// That is the right behaviour and it is invisible, which is the problem this script solves: it
// prints the whole subtree, so "it is not working" and "there is nothing there to read" stop looking
// the same.
import ApplicationServices
import AppKit

func attributeNames(_ e: AXUIElement) -> [String] {
    var n: CFArray?
    guard AXUIElementCopyAttributeNames(e, &n) == .success, let a = n as? [String] else { return [] }
    return a
}

func value(_ e: AXUIElement, _ attribute: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success, let v else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let s = v as? NSAttributedString { return s.string.isEmpty ? nil : s.string }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
    return (v as? [AXUIElement]) ?? []
}

func frame(_ e: AXUIElement) -> CGRect {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, "AXFrame" as CFString, &v) == .success, let v else { return .zero }
    var r = CGRect.zero
    AXValueGetValue(v as! AXValue, .cgRect, &r)
    return r
}

/// Attributes that say where something is rather than what it says.
let geometry: Set<String> = ["AXChildren", "AXParent", "AXFrame", "AXPosition", "AXSize",
                             "AXTopLevelUIElement", "AXWindow", "AXEnabled", "AXFocused"]

var readable: [String] = []

func walk(_ e: AXUIElement, _ depth: Int) {
    let pad = String(repeating: "  ", count: depth)
    let role = value(e, kAXRoleAttribute) ?? "(no role)"
    var said: [String] = []
    for a in attributeNames(e) where !geometry.contains(a) {
        guard let s = value(e, a), s.count < 80 else { continue }
        said.append("\(a.replacingOccurrences(of: "AX", with: "")) = \(s)")
        if ["AXValue", "AXTitle", "AXDescription", "AXAttributedDescription", "AXHelp"].contains(a),
           !readable.contains(s) { readable.append(s) }
    }
    print("\(pad)\(role)\(said.isEmpty ? "" : "  " + said.joined(separator: "  "))")
    if depth < 8 { for c in children(e) { walk(c, depth + 1) } }
}

guard AXIsProcessTrusted() else {
    print("No Accessibility permission for whatever is running this (usually Terminal).")
    print("System Settings > Privacy & Security > Accessibility.")
    exit(1)
}
guard let agent = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")
        .first?.processIdentifier else {
    print("MenuBarAgent is not running, so there is no menu bar to read.")
    exit(1)
}

let app = AXUIElementCreateApplication(agent)
// Generous on purpose: the app uses 0.2 s, and the point here is to separate "slow" from "silent".
AXUIElementSetMessagingTimeout(app, 3.0)

var v: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
guard let windows = v as? [AXUIElement],
      let bar = windows.first(where: { let f = frame($0); return f.height > 0 && f.height <= 40 }) else {
    print("No menu bar window on MenuBarAgent.")
    exit(1)
}

let pills = children(bar).filter { (value($0, kAXIdentifierAttribute) ?? "").contains("live-activity") }
guard !pills.isEmpty else {
    print("No Live Activity in the menu bar right now.")
    print("Start one on the iPhone (a timer, a delivery, a match) and run this again.")
    exit(0)
}

for (i, pill) in pills.enumerated() {
    print("Live Activity \(i + 1) of \(pills.count), everything Accessibility exposes:\n")
    readable = []
    walk(pill, 0)
    print("\nStrings Casement has to work with: \(readable)")
    // Casement drops these as generic before trying to name an app or a detail.
    let generic = ["Live Activity", "Expanded", "Collapsed", "Live"]
    let useful = readable.filter { !generic.contains($0) }
    print("After dropping generic labels: \(useful)")
    if useful.isEmpty {
        print("\nNothing usable. Casement will leave this pill alone rather than cover it with a")
        print("worse version, which is the intended behaviour, not a failure.")
    } else if useful.count == 1 {
        print("\nOne string only, so the island can show a detail but cannot name the app.")
    } else {
        print("\nEnough to name an app and a detail; this one should mirror.")
    }
}
