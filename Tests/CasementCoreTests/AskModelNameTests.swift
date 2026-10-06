import Testing
@testable import CasementCore

/// Settings → Ask & AI names models as people say them; the id stays in config.json.
@Suite struct AskModelNameTests {
    @Test func claudeModelsReadAsNames() {
        #expect(AskModelName.title("claude-opus-5-5") == "Claude Opus 5.5")
        #expect(AskModelName.title("claude-sonnet-5-5") == "Claude Sonnet 5.5")
        #expect(AskModelName.title("claude-haiku-4-5") == "Claude Haiku 4.5")
        #expect(AskModelName.title("claude-3-5-sonnet-20241022") == "Claude 3.5 Sonnet (20241022)")
    }

    @Test func openAIModelsKeepTheirVersionInTheName() {
        #expect(AskModelName.title("gpt-6-astra") == "GPT-6 Astra")
        #expect(AskModelName.title("gpt-6.1-sol") == "GPT-6.1 Sol")
        #expect(AskModelName.title("gpt-4o-mini") == "GPT-4o Mini")
        #expect(AskModelName.title("gpt-4o-2024-08-06") == "GPT-4o (2024-08-06)")
        #expect(AskModelName.title("chatgpt-4o-latest") == "ChatGPT-4o Latest")
        #expect(AskModelName.title("o3-mini") == "o3 Mini")
    }

    /// Anything that isn't shaped like an id is shown as it is.
    @Test func oddIdsStayAsTheyAre() {
        #expect(AskModelName.title("gpt") == "gpt")
        #expect(AskModelName.title("my_model") == "my_model")
        #expect(AskModelName.title("a--b") == "a--b")
        #expect(AskModelName.title("") == "")
    }

    /// Every model Casement suggests has a name, never the bare id.
    @Test func suggestedModelsAllHaveNames() {
        for kind in [AskProviderKind.anthropic, .openai] {
            for id in kind.suggestedModels {
                #expect(AskModelName.title(id) != id, "\(id)")
            }
        }
    }

    /// Effort is greyed out for the providers that ignore it.
    @Test func onlyClaudeAndChatGPTTakeAnEffort() {
        #expect(AskProviderKind.allCases.filter(\.takesEffort) == [.anthropic, .openai])
    }

    @Test func aSavedKeySaysHowItEnds() {
        #expect(AskKeys.savedLabel(AskKeys.masked("sample-key-0000")) == "Saved, ends in 0000")
    }
}
