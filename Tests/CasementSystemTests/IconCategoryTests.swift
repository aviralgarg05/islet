import AppKit
import CasementCore
import Testing

@Suite struct IconCategoryTests {
    @Test func everyCategoryHasASymbolThatExists() {
        #expect(Set(IconCategory.names).count == IconCategory.names.count)
        for (name, symbol) in IconCategory.all where name != "other" {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(name): \(symbol)")
        }
    }

    @Test func unknownAndOtherGiveNoSymbol() {
        #expect(IconCategory.symbol(for: " Flight ") == "airplane")
        #expect(IconCategory.symbol(for: "other") == nil)
        #expect(IconCategory.symbol(for: "spaceship") == nil)
    }
}
