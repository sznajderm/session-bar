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
check("should flag a background shell after the turn as waiting in the background", getAttention("shell", turnEnded: true) == .background)

let entry = parseRegistry(Data("""
{"pid":1,"sessionId":"TEST_ID","cwd":"/a","name":"TEST_NAME","status":"waiting","waitingFor":"input needed","kind":"interactive"}
""".utf8))
check("should read the waitingFor reason from a registry file", entry.map { getReason($0, turnEnded: false) } == "input needed")
check("should reject a registry file that is not JSON", parseRegistry(Data("nope".utf8)) == nil)

func registry(name: String, source: String) -> RegistryEntry {
    parseRegistry(Data(#"{"pid":1,"sessionId":"TEST_ID","cwd":"/a","name":"\#(name)","nameSource":"\#(source)"}"#.utf8))!
}
check(
    "should prefer a name the user gave the session over the Warp tab",
    getDisplayName(registry(name: "TEST_NAME", source: "user"), warpTab: "TEST_TAB", aiTitle: "TEST_TITLE") == "TEST_NAME"
)
check(
    "should use the Warp tab over the AI title",
    getDisplayName(registry(name: "TEST_NAME", source: "derived"), warpTab: "TEST_TAB", aiTitle: "TEST_TITLE") == "TEST_TAB"
)
check(
    "should use the AI title outside a titled Warp tab",
    getDisplayName(registry(name: "TEST_NAME", source: "derived"), warpTab: nil, aiTitle: "TEST_TITLE") == "TEST_TITLE"
)
check(
    "should fall back to the derived name before the AI title exists",
    getDisplayName(registry(name: "TEST_NAME", source: "derived"), warpTab: nil, aiTitle: "") == "TEST_NAME"
)

let procargs = Data([1, 0, 0, 0] + Array("/bin/claude\0\0claude\0WARP_TERMINAL_SESSION_UUID=0B3EE32E\0HOME=/h\0".utf8))
check("should find the Warp session id in a process environment", findWarpSessionId(procargs) == "0b3ee32e")
check("should find no Warp session id outside Warp", findWarpSessionId(Data("claude\0HOME=/h\0".utf8)) == nil)

let parents: [Int32: Int32] = [30: 20, 20: 10, 10: 1]
check("should find the first ancestor that is an app", findAncestor(30, parent: { parents[$0] }, matches: { $0 == 10 || $0 == 20 }) == 20)
check("should find no ancestor when none is an app", findAncestor(30, parent: { parents[$0] }, matches: { _ in false }) == nil)
check("should stop on a process tree loop", findAncestor(5, parent: { _ in 5 }, matches: { _ in false }) == nil)

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

exit(failures == 0 ? 0 : 1)
