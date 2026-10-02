import AppKit
import IsletCore
import IsletSystem
import SwiftUI

// The pages of the note tools under "More": To-dos, Note, Converter and Emoji (NoteTools.swift
// holds their state). Each fits the open island's content area at the compact size, a field on
// top and what it holds below; anything longer scrolls.

// MARK: - A field on the island

/// A one-line field in a capsule, like the Ask box's. The island's panel takes the keyboard
/// only once the field is clicked, and gives it back when the page goes or Esc is pressed with
/// the field empty.
struct IslandField: View {
    let model: AppModel
    let placeholder: String
    @Binding var text: String
    var symbol = "magnifyingglass"
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @ViewState private var typing = false
    @Environment(\.snapshotMode) private var snapshotMode

    static let height: CGFloat = 26

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if snapshotMode {
                    Text(text.isEmpty ? placeholder : text)
                        .foregroundStyle(text.isEmpty ? Ink.tertiary : Ink.primary)
                        .lineLimit(1)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Ink.primary)
                        .focused($focused)
                        .onSubmit(onSubmit)
                        .onExitCommand(perform: escape)
                        .accessibilityLabel(placeholder)
                    // The first click hands the keyboard to the island, then the field takes it.
                    if !typing {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: startTyping)
                            .accessibilityElement()
                            .accessibilityLabel(placeholder)
                            .accessibilityValue(text)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Starts typing")
                            .accessibilityAction { startTyping() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textStyle(.body)
        .padding(.horizontal, Space.m)
        .frame(height: Self.height)
        .background(Capsule().fill(Wash.regular))
        .contrastEdge(Capsule())
        .onDisappear {
            guard typing else { return }
            typing = false
            IslandKeyboard.giveBack()
        }
    }

    private func startTyping() {
        typing = true
        IslandKeyboard.take(on: model.expandedScreen)
        DispatchQueue.main.async { focused = true }
    }

    /// Esc clears the field, then gives the keyboard back.
    private func escape() {
        if !text.isEmpty {
            text = ""
        } else {
            typing = false
            focused = false
            IslandKeyboard.giveBack()
        }
    }
}

/// A page whose tool is off: what it does, and a button to turn it on.
private struct TurnOnHint: View {
    let model: AppModel
    let symbol: String
    let text: String
    let key: WritableKeyPath<IsletSettings, Bool>

    var body: some View {
        EmptyHint(symbol: symbol, text: text) {
            Button("Turn on") { model.setTool(key, true) }
                .buttonStyle(CapsuleButtonStyle(tint: .blue, filled: true))
        }
    }
}

// MARK: - To-dos

/// Add a line, star it, tick it off: what is left to do first, starred at the top, then what
/// is done.
struct TodosTab: View {
    let model: AppModel
    let size: CGSize

    var body: some View {
        let c = model.tools.todos
        Group {
            if !model.settings.todosEnabled {
                TurnOnHint(model: model, symbol: "checklist",
                           text: "A to-do list in the island: add a line, star what matters, tick it off. It stays on this Mac.",
                           key: \.todosEnabled)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.m) {
                        IslandField(model: model, placeholder: "Add a to-do", text: Binding(get: { c.draft }, set: { c.draft = $0 }),
                                    symbol: "plus") { c.addDraft() }
                        summary(c.list)
                    }
                    list(c)
                }
            }
        }
        .onAppear { c.load() }
    }

    @ViewBuilder
    private func summary(_ list: TodoList) -> some View {
        if list.hasDone {
            Button("Clear done") { model.tools.todos.clearDone() }
                .buttonStyle(.plain)
                .textStyle(.caption)
                .foregroundStyle(Ink.tertiary)
                .help("Remove everything ticked off")
                .fixedSize()
        } else if list.openCount > 0 {
            Text("\(list.openCount) to do").textStyle(.caption, numeric: true).foregroundStyle(Ink.tertiary).fixedSize()
        }
    }

    @ViewBuilder
    private func list(_ c: TodoController) -> some View {
        let items = c.list.ordered
        if items.isEmpty {
            Text("Type a line and press Return. Star what matters, and tick it off when it's done.")
                .textStyle(.caption)
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Space.xs)
        } else {
            AdaptiveScroll(scrolls: CGFloat(items.count) * TodoRow.height > size.height - IslandField.height - Space.s) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in TodoRow(item: item, model: model) }
                }
            }
            .padding(.horizontal, -Space.xs)
        }
    }
}

struct TodoRow: View {
    let item: TodoItem
    let model: AppModel
    @ViewState private var hovering = false

    static let height: CGFloat = 24

    var body: some View {
        let c = model.tools.todos
        HStack(spacing: Space.s) {
            Button { c.toggleDone(item) } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(item.isDone ? Ink.tertiary : Ink.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Put back to do" : "Tick off")
            .accessibilityHidden(true)
            Text(item.text)
                .textStyle(.body)
                .strikethrough(item.isDone, color: Ink.tertiary)
                .foregroundStyle(item.isDone ? Ink.tertiary : Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if (hovering || item.starred) && !item.isDone {
                Button { c.toggleStar(item) } label: {
                    Image(systemName: item.starred ? "star.fill" : "star").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.starred ? Color.yellow.readableOnBlack : Ink.tertiary)
                .help(item.starred ? "Unstar" : "Star")
                .accessibilityHidden(true)
            }
            if hovering {
                Button { c.remove(item) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.tertiary)
                    .help("Remove")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.xs)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(item.isDone ? "Put back to do" : "Tick off") { c.toggleDone(item) }
            if !item.isDone { Button(item.starred ? "Unstar" : "Star") { c.toggleStar(item) } }
            Button("Copy") { model.clipboardMonitor.copy(item.text) }
            Divider()
            Button("Remove") { c.remove(item) }
        }
        .spokenButton(item.text, value: item.isDone ? "done" : item.starred ? "starred" : nil,
                      hint: item.isDone ? "Puts it back to do" : "Ticks it off") { c.toggleDone(item) }
        .accessibilityAction(named: item.starred ? "Unstar" : "Star") { c.toggleStar(item) }
        .accessibilityAction(named: "Remove") { c.remove(item) }
    }
}

// MARK: - Note

/// A scratch pad that keeps its text: on this Mac, saved as you type.
struct NoteTab: View {
    let model: AppModel
    @FocusState private var focused: Bool
    @ViewState private var typing = false
    @ViewState private var hovering = false
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let c = model.tools.note
        Group {
            if !model.settings.noteEnabled {
                TurnOnHint(model: model, symbol: "note.text",
                           text: "A note that keeps its text: jot something down and it's still here next time. It stays on this Mac.",
                           key: \.noteEnabled)
            } else {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Wash.subtle)
                    if c.text.isEmpty {
                        Text("Jot something down. It stays here until you clear it.")
                            .textStyle(.body)
                            .foregroundStyle(Ink.tertiary)
                            .padding(.horizontal, Space.s + 5)
                            .padding(.vertical, Space.s)
                            .allowsHitTesting(false)
                    }
                    if snapshotMode {
                        Text(c.text)
                            .textStyle(.body)
                            .foregroundStyle(Ink.primary)
                            .padding(.horizontal, Space.s + 5)
                            .padding(.vertical, Space.s)
                    } else {
                        TextEditor(text: Binding(get: { c.text }, set: { c.setText($0) }))
                            .font(TextStyle.body.font())
                            .foregroundStyle(Ink.primary)
                            .scrollContentBackground(.hidden)
                            .scrollIndicators(.never)
                            .focused($focused)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.s)
                            .accessibilityLabel("Note")
                        if !typing {
                            // While typing, the text's own menu (cut, copy, paste) is the one shown.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: startTyping)
                                .contextMenu {
                                    Button("Copy the note") { model.clipboardMonitor.copy(c.text) }.disabled(c.text.isEmpty)
                                    Button("Clear the note") { c.setText(""); c.saveNow() }.disabled(c.text.isEmpty)
                                }
                                .accessibilityElement()
                                .accessibilityLabel("Note")
                                .accessibilityValue(c.text)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Starts typing")
                                .accessibilityAction { startTyping() }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering && !c.text.isEmpty {
                        Text(QuickNoteFile.summary(c.text))
                            .textStyle(.caption, numeric: true)
                            .foregroundStyle(Ink.tertiary)
                            .padding(Space.s)
                            .allowsHitTesting(false)
                    }
                }
                .onHover { hovering = $0 }
                .onExitCommand(perform: stopTyping)
            }
        }
        .onAppear { c.load() }
        .onDisappear {
            c.saveNow()
            if typing { stopTyping() }
        }
    }

    private func startTyping() {
        typing = true
        IslandKeyboard.take(on: model.expandedScreen)
        DispatchQueue.main.async { focused = true }
    }

    private func stopTyping() {
        typing = false
        focused = false
        model.tools.note.saveNow()
        IslandKeyboard.giveBack()
    }
}

// MARK: - Converter

/// Type "5 ft in cm" and read the answer; click it to copy the number.
struct ConverterTab: View {
    let model: AppModel

    var body: some View {
        let c = model.tools.converter
        if !model.settings.converterEnabled {
            TurnOnHint(model: model, symbol: "arrow.left.arrow.right",
                       text: "Convert lengths, weights, temperatures, volumes and speeds: type something like 5 ft in cm.",
                       key: \.converterEnabled)
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                IslandField(model: model, placeholder: "Type an amount and a unit, like 5 ft in cm",
                            text: Binding(get: { c.query }, set: { c.query = $0; c.queryChanged() }), symbol: "arrow.left.arrow.right") {
                    if let first = c.conversion?.results.first { c.copy(first, model: model) }
                }
                answer(c)
            }
        }
    }

    @ViewBuilder
    private func answer(_ c: ConverterController) -> some View {
        if c.query.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: Space.s) {
                ForEach(UnitConverter.examples.prefix(3), id: \.self) { example in
                    Button(example) {
                        c.query = example
                        c.queryChanged()
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
        } else if let conversion = c.conversion {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text("\(conversion.source) =")
                    .textStyle(.headline)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                ForEach(conversion.results) { result in
                    ConverterAnswer(result: result, copied: c.copied == result.text) { c.copy(result, model: model) }
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("Try an amount and a unit, like 70 kg in lb or 100 °F in °C.")
                .textStyle(.caption)
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Space.xs)
        }
    }
}

/// One answer, large; a click copies its number.
private struct ConverterAnswer: View {
    let result: ConverterResult
    let copied: Bool
    let copy: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(result.text)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(copied ? "Copied" : hovering ? "Click to copy" : " ")
                    .textStyle(.caption)
                    .foregroundStyle(copied ? Color.green.readableOnBlack : Ink.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy \(result.plainNumber)")
        .accessibilityLabel(result.text)
        .accessibilityHint("Copies the number")
    }
}

/// The Ask box answers a conversion as it is typed, while the converter is on: one quiet row,
/// clicked to copy the number.
struct AskConversion: View {
    let model: AppModel
    let conversion: Conversion
    @ViewState private var hovering = false

    static func match(_ model: AppModel) -> Conversion? {
        guard model.settings.converterEnabled else { return nil }
        return ConverterController.convert(model.ask.draft)
    }

    var body: some View {
        let c = model.tools.converter
        let first = conversion.results.first
        Button {
            if let first { c.copy(first, model: model) }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                    .frame(width: 14)
                Text(conversion.sentence)
                    .textStyle(.body, emphasized: true)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(first.map { c.copied == $0.text } == true ? "Copied" : "Copy")
                    .textStyle(.caption)
                    .foregroundStyle(hovering ? Ink.secondary : Ink.tertiary)
            }
            .padding(.horizontal, Space.s)
            .frame(height: ShortcutsTab.rowHeight)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.subtle : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -Space.xs)
        .accessibilityLabel(conversion.sentence)
        .accessibilityHint("Copies the answer")
    }
}

// MARK: - Emoji

/// Search every emoji; a click copies one (or types it where you were typing, when that's on).
struct EmojiTab: View {
    let model: AppModel
    let size: CGSize

    static let cell: CGFloat = 30

    var body: some View {
        let c = model.tools.emoji
        Group {
            if !model.settings.emojiEnabled {
                TurnOnHint(model: model, symbol: "face.smiling",
                           text: "Find any emoji by name or by the words people use, then click to copy it.",
                           key: \.emojiEnabled)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.m) {
                        IslandField(model: model, placeholder: "Search emoji",
                                    text: Binding(get: { c.query }, set: { c.query = $0; c.queryChanged() })) {
                            if let first = c.results.first { c.pick(first, model: model) }
                        }
                        .id(c.fieldGeneration)
                        if let picked = c.picked {
                            Text("\(picked.emoji) \(picked.typed ? "typed" : "copied")")
                                .textStyle(.caption)
                                .foregroundStyle(Ink.tertiary)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    grid(c)
                }
            }
        }
        .onAppear { c.load() }
    }

    @ViewBuilder
    private func grid(_ c: EmojiController) -> some View {
        let results = c.results
        if results.isEmpty {
            Text("No emoji for “\(c.query)”").textStyle(.body).foregroundStyle(Ink.tertiary).lineLimit(1)
                .padding(.horizontal, Space.xs)
        } else {
            let perRow = max(1, Int((size.width + 2) / (Self.cell + 2)))
            let rows = (results.count + perRow - 1) / perRow
            AdaptiveScroll(scrolls: CGFloat(rows) * (Self.cell + 2) > size.height - IslandField.height - Space.s) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 2), count: perRow),
                          alignment: .leading, spacing: 2) {
                    ForEach(results) { item in EmojiCell(item: item) { c.pick(item, model: model) } }
                }
            }
        }
    }
}

private struct EmojiCell: View {
    let item: EmojiItem
    let pick: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: pick) {
            Text(item.emoji)
                .font(.system(size: 20))
                .frame(width: EmojiTab.cell, height: EmojiTab.cell)
                .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(hovering ? Wash.strong : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}
