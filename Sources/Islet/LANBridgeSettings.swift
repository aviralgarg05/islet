import AppKit
import IsletCore
import SwiftUI

/// Settings → Integrations → iPhone bridge: the switch, the bridge's own token, and what it
/// can and can't do.
struct LANBridgeSection: View {
    @Bindable var model: AppModel
    @ViewState private var copied = false
    @ViewState private var confirming = false

    private var enabled: Bool { model.settings.lanBridgeEnabled }

    var body: some View {
        Section("iPhone bridge (local network)") {
            Toggle("Accept events from iPhone Shortcuts on this network", isOn: $model.settings.lanBridgeEnabled)
                .task(id: enabled) {
                    if enabled { model.lan.loadToken() }
                }
            LabeledContent("Status") { Text(model.lan.status).foregroundStyle(.secondary) }
            if enabled, let token = model.lan.token {
                LabeledContent("Token") {
                    Text(token).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                HStack {
                    Button(copied ? "Copied" : "Copy Token") {
                        Self.copy(token)
                        copied = true
                    }
                    Button("New Token…") { confirming = true }
                }
                .alert("Make a new bridge token?", isPresented: $confirming) {
                    Button("New Token") {
                        model.lan.rotateToken()
                        copied = false
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Shortcuts that send the current token stop working until you give them the new one.")
                }
            }
            Text("The bridge is not encrypted, so anyone on this network can read what is sent, token included. It only accepts notifications, timers, Focus and simple activities, without links, buttons or image files, and its token does not work on the local API.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // Verbatim, so the port isn't shown as "47,832".
            Text(verbatim: "In Shortcuts on iPhone, add a Personal Automation (Alarm, Focus, Arrive, Battery Level…) with Get Contents of URL: POST http://\(ProcessInfo.processInfo.hostName):\(model.settings.lanPort)/v1/notify, header Authorization: Bearer <token>, JSON body {\"title\": \"…\"}.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Concealed and transient, so clipboard managers skip it. Unlike the API token it isn't
    /// kept to this Mac: the token is needed on the iPhone.
    static func copy(_ token: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }
}
