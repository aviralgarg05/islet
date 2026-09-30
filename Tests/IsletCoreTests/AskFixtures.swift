// Recorded-style sample streams for the Ask providers. Shapes follow the vendors' documented
// wire formats; ids, text and token counts are made up.

enum AskFixtures {
    /// Anthropic Messages stream for claude-opus-5-5: an (omitted) thinking block with a
    /// signature, then two text deltas, keep-alive pings and a comment line.
    static let anthropicStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_01XFDUDYJgAACzvnptvVoYEL","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":42,"output_tokens":1}}}

    event: ping
    data: {"type": "ping"}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    : keep-alive

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"A monad is a type that wraps values"}}

    event: ping
    data: {"type": "ping"}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" and lets you chain steps — like Optional’s flatMap."}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":87}}

    event: message_stop
    data: {"type":"message_stop"}


    """

    /// A classifier decline after some output: the partial must be thrown away.
    static let anthropicRefusal = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_02","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":30,"output_tokens":1}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Here is how to"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null,"stop_details":{"type":"refusal","category":"cyber","explanation":"This request was declined."}},"usage":{"output_tokens":4}}

    event: message_stop
    data: {"type":"message_stop"}


    """

    /// `fallbacks: "default"` re-ran a declined request mid-stream: the partial text stays, a
    /// `fallback` block marks the switch, and the fallback model continues the answer.
    static let anthropicFallback = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_03","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":25,"output_tokens":1}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Port scanners probe "}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: content_block_start
    data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"which ports answer."}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":2}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}

    event: message_stop
    data: {"type":"message_stop"}


    """

    static let anthropicOverloaded = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_04","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}

    event: error
    data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}


    """

    static let anthropicMaxTokens = """
    event: message_start
    data: {"type":"message_start","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":9,"output_tokens":1}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Once upon"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":4096}}

    event: message_stop
    data: {"type":"message_stop"}


    """

    /// OpenAI Responses stream (store: false).
    static let openAIStream = """
    event: response.created
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_67c9","object":"response","status":"in_progress","model":"gpt-6-astra","output":[],"store":false,"usage":null}}

    event: response.in_progress
    data: {"type":"response.in_progress","sequence_number":1,"response":{"id":"resp_67c9","status":"in_progress"}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[]}}

    event: response.output_item.done
    data: {"type":"response.output_item.done","sequence_number":3,"output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[]}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","sequence_number":4,"output_index":1,"item":{"id":"msg_1","type":"message","status":"in_progress","role":"assistant","content":[]}}

    event: response.content_part.added
    data: {"type":"response.content_part.added","sequence_number":5,"item_id":"msg_1","output_index":1,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","sequence_number":6,"item_id":"msg_1","output_index":1,"content_index":0,"delta":"Tokyo is"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","sequence_number":7,"item_id":"msg_1","output_index":1,"content_index":0,"delta":" 8 hours ahead of London."}

    event: response.output_text.done
    data: {"type":"response.output_text.done","sequence_number":8,"item_id":"msg_1","output_index":1,"content_index":0,"text":"Tokyo is 8 hours ahead of London."}

    event: response.completed
    data: {"type":"response.completed","sequence_number":9,"response":{"id":"resp_67c9","status":"completed","model":"gpt-6-astra","usage":{"input_tokens":51,"input_tokens_details":{"cached_tokens":0},"output_tokens":19,"output_tokens_details":{"reasoning_tokens":8},"total_tokens":70}}}


    """

    static let openAIRefusal = """
    event: response.created
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_2","status":"in_progress","model":"gpt-6-astra"}}

    event: response.refusal.delta
    data: {"type":"response.refusal.delta","sequence_number":1,"item_id":"msg_2","output_index":0,"content_index":0,"delta":"I can't help"}

    event: response.refusal.delta
    data: {"type":"response.refusal.delta","sequence_number":2,"item_id":"msg_2","output_index":0,"content_index":0,"delta":" with that."}

    event: response.refusal.done
    data: {"type":"response.refusal.done","sequence_number":3,"item_id":"msg_2","output_index":0,"content_index":0,"refusal":"I can't help with that."}

    event: response.completed
    data: {"type":"response.completed","sequence_number":4,"response":{"id":"resp_2","status":"completed","model":"gpt-6-astra","usage":{"input_tokens":20,"output_tokens":7}}}


    """

    static let openAIIncomplete = """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","sequence_number":1,"item_id":"m","output_index":0,"content_index":0,"delta":"Chapter one"}

    event: response.incomplete
    data: {"type":"response.incomplete","sequence_number":2,"response":{"id":"resp_3","status":"incomplete","model":"gpt-6-luna","incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":12,"output_tokens":2048}}}


    """

    static let openAIFailed = """
    event: response.failed
    data: {"type":"response.failed","sequence_number":3,"response":{"id":"resp_4","status":"failed","error":{"code":"server_error","message":"The server had an error processing your request."}}}


    """

    /// `claude -p … --output-format stream-json --verbose --include-partial-messages`.
    static let claudeCLI = """
    {"type":"system","subtype":"init","cwd":"/Users/me/Library/Application Support/Islet/ask","session_id":"5f0c","tools":[],"mcp_servers":[],"model":"claude-opus-5-5","permissionMode":"default","apiKeySource":"none"}
    {"type":"stream_event","event":{"type":"message_start","message":{"id":"msg_9","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":3,"output_tokens":1}}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a1"}
    {"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a2"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a3"}
    {"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a4"}
    {"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a5"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Use `git switch -c`"}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a6"}
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" to create a branch."}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a7"}
    {"type":"assistant","message":{"id":"msg_9","type":"message","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"Use `git switch -c` to create a branch."}],"stop_reason":null},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a8"}
    {"type":"stream_event","event":{"type":"content_block_stop","index":1},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"a9"}
    {"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":14}},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"b1"}
    {"type":"stream_event","event":{"type":"message_stop"},"session_id":"5f0c","parent_tool_use_id":null,"uuid":"b2"}
    {"type":"result","subtype":"success","is_error":false,"duration_ms":2310,"duration_api_ms":2204,"num_turns":1,"result":"Use `git switch -c` to create a branch.","session_id":"5f0c","total_cost_usd":0.0041,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":11800,"output_tokens":14}}

    """

    /// An older CLI without partial messages: the text only arrives in the `assistant` line.
    static let claudeCLINoPartials = """
    {"type":"system","subtype":"init","session_id":"s","tools":[],"model":"claude-sonnet-5-5"}
    {"type":"assistant","message":{"id":"m","type":"message","role":"assistant","content":[{"type":"thinking","thinking":""},{"type":"text","text":"Forty-two."}]},"session_id":"s"}
    {"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"Forty-two.","session_id":"s","total_cost_usd":0.002,"usage":{"input_tokens":5,"output_tokens":4}}

    """

    static let claudeCLINotLoggedIn = """
    {"type":"system","subtype":"init","session_id":"s","tools":[],"model":"claude-opus-5-5","apiKeySource":"none"}
    {"type":"assistant","message":{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"Invalid API key · Please run /login"}]},"session_id":"s"}
    {"type":"result","subtype":"success","is_error":true,"num_turns":1,"result":"Invalid API key · Please run /login","session_id":"s","total_cost_usd":0}

    """

    /// `codex exec --json --ephemeral …`.
    static let codex = """
    {"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}
    {"type":"turn.started"}
    {"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Answering a date question**"}}
    {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"`date -u` prints the time in UTC."}}
    {"type":"turn.completed","usage":{"input_tokens":2604,"cached_input_tokens":2048,"output_tokens":27}}

    """

    /// A dropped connection Codex recovered from, then two messages.
    static let codexRetried = """
    {"type":"thread.started","thread_id":"t"}
    {"type":"turn.started"}
    {"type":"error","message":"stream disconnected before completion: retrying 1/5 in 212ms…"}
    {"type":"item.started","item":{"id":"item_1","type":"agent_message","text":"First"}}
    {"type":"item.updated","item":{"id":"item_1","type":"agent_message","text":"First part."}}
    {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"First part."}}
    {"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Second part."}}
    {"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":9}}

    """

    static let codexFailed = """
    {"type":"thread.started","thread_id":"t"}
    {"type":"turn.started"}
    {"type":"error","message":"unexpected status 401 Unauthorized"}
    {"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Please run codex login"}}

    """

    static let anthropicModels = """
    {"data":[{"type":"model","id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5","created_at":"2026-08-12T00:00:00Z"},{"type":"model","id":"claude-fable-5-1","display_name":"Claude Fable 5.1","created_at":"2026-08-01T00:00:00Z"},{"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","created_at":"2026-07-20T00:00:00Z"},{"type":"model","id":"claude-haiku-4-5-20251001","display_name":"Claude Haiku 4.5","created_at":"2025-10-01T00:00:00Z"}],"has_more":false,"first_id":"claude-sonnet-5-5","last_id":"claude-haiku-4-5-20251001"}
    """

    static let openAIModels = """
    {"object":"list","data":[{"id":"gpt-6-luna","object":"model","created":1786000000,"owned_by":"system"},{"id":"text-embedding-3-large","object":"model","created":1705953180,"owned_by":"system"},{"id":"gpt-6-astra","object":"model","created":1786000001,"owned_by":"system"},{"id":"whisper-1","object":"model","created":1677532384,"owned_by":"openai-internal"},{"id":"o4-mini","object":"model","created":1744225351,"owned_by":"system"},{"id":"gpt-4o-mini-tts","object":"model","created":1742403959,"owned_by":"system"},{"id":"gpt-6.1-sol","object":"model","created":1788000000,"owned_by":"system"},{"id":"dall-e-3","object":"model","created":1698785189,"owned_by":"system"}]}
    """
}
