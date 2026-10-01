import AppKit
import IsletCore
import SwiftUI

/// Settings → Advanced → iPhone bridge: the switch, its port, the bridge's own token, and
/// what it can and can't do.
struct LANBridgeSection: View {
    @Bindable var model: AppModel
    @ViewState private var copied = false
    @ViewState private var confirming = false

    private var enabled: Bool { model.settings.lanBridgeEnabled }

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.lanBridgeEnabled) {
                Text("Accept requests from this network")
                Text("Lets Shortcuts on your iPhone, Home Assistant and other devices on this network show things in the island.")
            }
            .task(id: enabled) {
                if enabled { model.lan.loadToken() }
            }
            .settingsAnchor("advanced.bridge")
            LabeledContent("Status") { Text(model.lan.status).foregroundStyle(.secondary) }
            LabeledContent("Port") { PortField(port: $model.settings.lanPort, other: model.settings.apiPort) }
                .settingsAnchor("advanced.bridgePort")
            LabeledContent("Token") {
                HStack(spacing: 8) {
                    if enabled, let token = model.lan.token {
                        Text("Ends in \(String(token.suffix(4)))").foregroundStyle(.secondary).monospacedDigit()
                        Button(copied ? "Copied" : "Copy") {
                            Self.copy(token)
                            copied = true
                        }
                        Button("New token…") { confirming = true }
                    } else {
                        Text("Made when the bridge is on").foregroundStyle(.secondary)
                    }
                }
            }
            .settingsAnchor("advanced.bridgeToken")
            .alert("Make a new bridge token?", isPresented: $confirming) {
                Button("New token") {
                    model.lan.rotateToken()
                    copied = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shortcuts that send the current token stop working until you give them the new one.")
            }
            if enabled {
                // Verbatim, so the port isn't shown as "47,832".
                CodeBlock(title: "In Shortcuts on iPhone, add Get Contents of URL",
                          code: "POST http://\(ProcessInfo.processInfo.hostName):\(model.settings.lanPort)/v1/notify\nAuthorization: Bearer <token>\n{\"title\": \"…\"}")
            }
        } header: {
            Text("iPhone bridge")
        } footer: {
            SettingsFooter("The bridge is not encrypted, so anyone on this network can read what is sent, token included. It only takes notifications, timers, Focus and simple activities, without links, buttons or image files, and its token doesn't work on the local API.")
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

/// Text to copy into a terminal, a file or another app, with a Copy button.
struct CodeBlock: View {
    let title: String
    let code: String
    /// Long blocks scroll inside this height.
    var maxHeight: CGFloat = 150
    @ViewState private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                }
                .controlSize(.small)
            }
            Group {
                if code.contains("\n") {
                    // Several lines keep their layout and scroll.
                    ScrollView([.horizontal, .vertical]) {
                        text.fixedSize().padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: min(maxHeight, CGFloat(code.split(separator: "\n", omittingEmptySubsequences: false).count) * 14 + 22))
                } else {
                    // One command wraps, so none of it is out of sight.
                    text.fixedSize(horizontal: false, vertical: true).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(.vertical, 2)
    }

    private var text: some View {
        Text(verbatim: code)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
    }
}
