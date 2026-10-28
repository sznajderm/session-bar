import Foundation

// Pure logic, kept apart from the UI so Tests/main.swift can exercise it without Xcode.

enum Attention: Int {
    case needsYou = 0
    case yourTurn = 1
    case working = 2
}

struct RegistryEntry: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let status: String?
    let waitingFor: String?
    let updatedAt: Double?
    let kind: String?
}

struct Digest {
    var title = ""
    var lastPrompt = ""
    var recent: [String] = []
    var turnEnded = false
}

func parseRegistry(_ data: Data) -> RegistryEntry? {
    try? JSONDecoder().decode(RegistryEntry.self, from: data)
}

// A background shell keeps the status at "shell" after the turn ends, while the session waits for the user.
func getAttention(_ status: String, turnEnded: Bool) -> Attention {
    switch status {
    case "waiting": return .needsYou
    case "idle": return .yourTurn
    case "shell" where turnEnded: return .yourTurn
    default: return .working
    }
}

func getReason(_ entry: RegistryEntry, turnEnded: Bool) -> String {
    switch entry.status ?? "unknown" {
    case "waiting": return entry.waitingFor ?? "waiting for you"
    case "idle": return "finished, ready for the next prompt"
    case "shell" where turnEnded: return "finished, background shell still running"
    case "shell": return "running a shell command"
    case "busy": return "working"
    case let other: return other
    }
}

// Claude Code names a project folder by its cwd with every non-alphanumeric character as '-'.
func getTranscriptPath(home: String, cwd: String, sessionId: String) -> String {
    let slug = String(cwd.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    return "\(home)/.claude/projects/\(slug)/\(sessionId).jsonl"
}

func clip(_ text: String, _ max: Int) -> String {
    let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return flat.count > max ? String(flat.prefix(max)) + "…" : flat
}

// Reads the tail of a transcript (its first line may be cut) into a short digest for the summarizer.
func digestTranscript(_ tail: String) -> Digest {
    var digest = Digest()
    for line in tail.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = o["type"] as? String else { continue }
        if type == "ai-title", let title = o["aiTitle"] as? String { digest.title = title }
        if type == "last-prompt", let prompt = o["lastPrompt"] as? String { digest.lastPrompt = clip(prompt, 300) }
        if type == "system", o["subtype"] as? String == "turn_duration" { digest.turnEnded = true }
        guard type == "assistant" || type == "user" else { continue }
        digest.turnEnded = false
        let content = (o["message"] as? [String: Any])?["content"]
        if let text = content as? String {
            if type == "user" && !text.hasPrefix("<") { digest.recent.append("user: \(clip(text, 200))") }
            continue
        }
        guard let blocks = content as? [[String: Any]] else { continue }
        for block in blocks {
            if block["type"] as? String == "text", let text = block["text"] as? String {
                digest.recent.append("\(type): \(clip(text, 300))")
            }
            if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                let input = (try? JSONSerialization.data(withJSONObject: block["input"] ?? [:], options: [.sortedKeys]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                digest.recent.append("tool \(name): \(clip(input, 160))")
            }
        }
    }
    digest.recent = Array(digest.recent.suffix(15))
    return digest
}

func getFallbackSentence(_ digest: Digest) -> String {
    digest.recent.last.map { clip($0, 120) } ?? "No activity yet."
}

// Only the assistant's own tool calls (Jira lookups, `/ship EMR-…`, commits) name the session's
// ticket reliably; prompts and tool output echo `git log` and skill text full of other keys.
// Any Jira-shaped key counts (EMR, WWW, MOBT, …); a letters-only prefix skips regex text like `Z0-9`.
let ticketPattern = try! NSRegularExpression(pattern: #"\b[A-Z]{2,10}-\d+\b"#)
// Standards and encodings that share the key shape but are never tickets.
let nonTicketPrefixes: Set<String> = ["UTF", "ISO", "SHA", "RFC", "CVE", "TLS", "AES", "RSA", "HTTP", "GPT"]
let ticketWindow = 30

// The most mentioned ticket among the last mentions, so a session that moves on to a new ticket follows it.
func findTicket(_ transcript: String) -> String? {
    var mentions: [String] = []
    for line in transcript.split(separator: "\n") where line.contains("\"tool_use\"") {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              o["type"] as? String == "assistant",
              let blocks = (o["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
        for block in blocks where block["type"] as? String == "tool_use" {
            guard let input = try? JSONSerialization.data(withJSONObject: block["input"] ?? [:]),
                  let text = String(data: input, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let keys = Set(ticketPattern.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
                .filter { !nonTicketPrefixes.contains(String($0.prefix { $0 != "-" })) }
            mentions.append(contentsOf: keys.sorted())
        }
    }
    let recent = mentions.suffix(ticketWindow)
    let counts = Dictionary(recent.map { ($0, 1) }, uniquingKeysWith: +)
    // Ties go to the ticket mentioned last.
    return counts.max { a, b in a.value != b.value ? a.value < b.value : recent.lastIndex(of: a.key)! < recent.lastIndex(of: b.key)! }?.key
}
