import AppKit
import IsletCore

extension AppActions {
    /// `islet://ask`: open the Ask tab with the question filled in and the field focused.
    /// It never sends: a link or a script must not be able to spend money on the user's key.
    static func openAsk(_ model: AppModel, query: String?, provider: AskProviderKind?) {
        // Filled in first, so the question is waiting in the field whenever an island next
        // opens. Only the opening waits on a display: with no island anywhere, `setExpanded(nil)`
        // returns at once on a closed island and the pin would be left on with nothing on screen.
        model.ask.prefill(query, provider: provider)
        model.select(tab: .ask)
        guard let display = model.expandedScreen ?? model.targetDisplay() else { return }
        model.pinned = true
        model.setExpanded(display)
        model.ask.requestKeyboard()
    }

    /// The island's "Ask with" chip. It changes the setting itself (Settings → Ask & AI → Answer
    /// with), saved and applied like any other, and drops a provider an islet://ask link picked.
    static func chooseAskProvider(_ model: AppModel, _ kind: AskProviderKind) {
        model.ask.sessionProvider = nil
        guard model.settings.ask.provider != kind else { return }
        model.settings.ask.provider = kind
        model.settingsEdited()
    }
}
