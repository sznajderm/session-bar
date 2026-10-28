import Foundation

// Minimal runner: Command Line Tools ship no XCTest, so each check is a plain assertion.
var failures = 0
func check(_ name: String, _ condition: Bool) {
    print(condition ? "pass  \(name)" : "FAIL  \(name)")
    if !condition { failures += 1 }
}

check("should flag a waiting session as needing the user", getAttention("waiting", turnEnded: false) == .needsYou)
check("should flag an idle session as the user's turn", getAttention("idle", turnEnded: false) == .yourTurn)
check("should treat any other status as working", getAttention("busy", turnEnded: false) == .working)
check("should treat a shell mid-turn as working", getAttention("shell", turnEnded: false) == .working)
check("should flag a background shell after the turn as the user's turn", getAttention("shell", turnEnded: true) == .yourTurn)

let entry = parseRegistry(Data("""
{"pid":1,"sessionId":"TEST_ID","cwd":"/a","name":"TEST_NAME","status":"waiting","waitingFor":"input needed","kind":"interactive"}
""".utf8))
check("should read the waitingFor reason from a registry file", entry.map { getReason($0, turnEnded: false) } == "input needed")
check("should reject a registry file that is not JSON", parseRegistry(Data("nope".utf8)) == nil)

check(
    "should build the transcript path from the cwd slug",
    getTranscriptPath(home: "/h", cwd: "/Users/x/my.proj", sessionId: "TEST_ID") == "/h/.claude/projects/-Users-x-my-proj/TEST_ID.jsonl"
)

let digest = digestTranscript([
    "half a line",
    #"{"type":"ai-title","aiTitle":"TEST_TITLE"}"#,
    #"{"type":"last-prompt","lastPrompt":"TEST_PROMPT"}"#,
    #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#,
    #"{"type":"assistant","message":{"content":[{"type":"text","text":"TEST_REPLY"}]}}"#,
].joined(separator: "\n"))
check("should digest the title from a cut transcript tail", digest.title == "TEST_TITLE")
check("should digest the last prompt", digest.lastPrompt == "TEST_PROMPT")
check(
    "should digest recent tool calls and replies in order",
    digest.recent == [#"tool Bash: {"command":"ls"}"#, "assistant: TEST_REPLY"]
)

let reply = #"{"type":"assistant","message":{"content":[{"type":"text","text":"TEST_REPLY"}]}}"#
let turnEnd = #"{"type":"system","subtype":"turn_duration"}"#
let prompt = #"{"type":"user","message":{"content":"TEST_PROMPT"}}"#
check("should see the turn end after the last reply", digestTranscript([reply, turnEnd].joined(separator: "\n")).turnEnded)
check("should not see a turn end mid-turn", !digestTranscript(reply).turnEnded)
check("should clear the turn end on a new prompt", !digestTranscript([reply, turnEnd, prompt].joined(separator: "\n")).turnEnded)

func toolUse(_ input: String) -> String {
    #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"\#(input)"}}]}}"#
}

check(
    "should find the ticket the session's tool calls name most",
    findTicket([toolUse("EMR-1"), toolUse("EMR-2 and EMR-2"), toolUse("EMR-2")].joined(separator: "\n")) == "EMR-2"
)
check(
    "should ignore ticket keys that only appear in tool output",
    findTicket(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"\"tool_use\" EMR-9"}]}}"#) == nil
)
check(
    "should prefer the latest ticket on a tie",
    findTicket([toolUse("EMR-1"), toolUse("EMR-2")].joined(separator: "\n")) == "EMR-2"
)

check(
    "should find a ticket from any project key",
    findTicket(toolUse("WWW-42")) == "WWW-42"
)
check(
    "should skip encodings and regex text that look like keys",
    findTicket(toolUse("UTF-8 and [A-Z0-9]")) == nil
)

exit(failures == 0 ? 0 : 1)
