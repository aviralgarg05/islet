import Foundation
@testable import CasementSystem
import Testing

/// Casement builds with the macOS 26 SDK (Xcode 26, Swift 6.3) as well as the macOS 27 one. The
/// macOS 27-only parts are compiled out there; with the macOS 27 SDK they must still be in.
@Suite struct SDKCompatibilityTests {
    @Test func macOS27ErrorsAreReadWithTheMacOS27SDK() {
        // FoundationModels is version 2 in the macOS 27 SDK and 1.5 in the macOS 26.5 one.
        #if canImport(FoundationModels, _version: 2.0)
        #expect(OnDeviceAsk.readsLanguageModelError)
        #else
        #expect(!OnDeviceAsk.readsLanguageModelError)
        #endif
    }

    /// Swift 6.4 comes with the macOS 27 SDK (the Command Line Tools this is developed with), so
    /// there the version check must find FoundationModels 2 rather than quietly leave it out.
    @Test func theVersionCheckFindsTheMacOS27SDK() {
        #if compiler(>=6.4)
        #expect(OnDeviceAsk.readsLanguageModelError)
        #endif
    }
}
