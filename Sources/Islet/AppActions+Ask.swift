import AppKit
import IsletCore

extension AppActions {
    /// `islet://ask`: open the Ask tab with the question filled in and the field focused.
    /// It never sends: a link or a script must not be able to spend money on the user's key.
    static func openAsk(_ model: AppModel, query: String?, provider: AskProviderKind?) {
        model.ask.prefill(query, provider: provider)
        model.select(tab: .ask)
        model.pinned = true
        model.setExpanded(model.expandedScreen ?? model.targetDisplay())
        model.ask.requestKeyboard()
    }
}
