import Foundation

// Pure logic, kept apart from the UI so Tests/main.swift can exercise it without Xcode.

enum Attention: Int {
    case needsYou = 0
    case yourTurn = 1
    case background = 2
    case working = 3
}

struct RegistryEntry: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let nameSource: String?
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

// A background shell keeps the status at "shell" after the turn ends, while the session waits on it (a CodeRabbit review, CI).
func getAttention(_ status: String, turnEnded: Bool) -> Attention {
    switch status {
    case "waiting": return .needsYou
    case "idle": return .yourTurn
    case "shell" where turnEnded: return .background
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

// The name given in Claude Code, else the Warp tab title, else the AI title. Claude Code marks its own names "derived".
func getDisplayName(_ entry: RegistryEntry, warpTab: String?, aiTitle: String) -> String {
    if entry.nameSource != "derived", let name = entry.name, !name.isEmpty { return name }
    if let warpTab, !warpTab.isEmpty { return warpTab }
    if !aiTitle.isEmpty { return aiTitle }
    return entry.name ?? String(entry.sessionId.prefix(8))
}

// KERN_PROCARGS2 holds argc, the exec path, argv and then the environment, all NUL-separated.
func findWarpSessionId(_ procargs: Data) -> String? {
    let prefix = "WARP_TERMINAL_SESSION_UUID="
    return procargs.split(separator: 0)
        .map { String(decoding: $0, as: UTF8.self) }
        .first { $0.hasPrefix(prefix) }
        .map { String($0.dropFirst(prefix.count)).lowercased() }
}

// Walks up the process tree from a session to the first process that passes the check, such as Warp or the Claude app.
func findAncestor(_ pid: Int32, parent: (Int32) -> Int32?, matches: (Int32) -> Bool) -> Int32? {
    var current = pid
    var seen: Set<Int32> = []
    while current > 1, seen.insert(current).inserted {
        if matches(current) { return current }
        guard let next = parent(current) else { return nil }
        current = next
    }
    return nil
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
