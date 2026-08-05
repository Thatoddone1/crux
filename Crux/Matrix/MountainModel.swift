//
//  MountainModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import FoundationModels


@Observable
final class MountainModel {
    typealias Summary = RoomModel

    /// The handful of values scoring needs, lifted off a room on the main actor so
    /// the scoring itself — which is mostly waiting on an LLM — can run off it.
    private struct ScoringInput {
        let id: String
        let room: Room
        let isMentioned: Bool
        let isFavorite: Bool
        let isDirect: Bool
        let isLowPriority: Bool

        @MainActor init(_ summary: Summary) {
            id = summary.id
            room = summary.room
            isMentioned = summary.unreadMentions > 0
            isFavorite = summary.isFavorite
            isDirect = summary.isDirect
            isLowPriority = summary.isLowPriority
        }
    }

    /// Where a room's score came from, for the tap-to-explain popover.
    struct ScoreBreakdown {
        let mention: Int
        let favorite: Int
        let directness: Int
        let lowPriority: Int
        /// The LLM's read of the most recent message's urgency (0–40).
        let tone: Int
        var total: Int { min(max(mention + favorite + directness + lowPriority + tone, 0), 100) }
    }

    enum Phase { case idle, loading, ready }
    private(set) var phase: Phase = .idle

    private(set) var peak: [Summary] = []
    private(set) var slope: [Summary] = []
    /// Frozen scores, keyed by room id, so the badge and its breakdown never
    /// drift apart.
    private(set) var breakdowns: [String: ScoreBreakdown] = [:]
    func score(for summaryID: String) -> Int { breakdowns[summaryID]?.total ?? 0 }

    /// Rooms already placed, and ones swiped away this session (so a late unread
    /// update can't resurrect a dismissed card).
    private var placed: Set<String> = []
    private var dismissed: Set<String> = []
    private var builtAt = Date.distantPast

    static let peakThreshold = 50
    static let staleAfter: TimeInterval = 3 * 60 * 60   // 3 hours

    // MARK: - Building

    /// Sorts once per launch, and again only if the deck has gone stale from a
    /// long-open session. A normal tab switch does nothing.
    @MainActor
    func loadIfNeeded(unread: [Summary]) async {
        switch phase {
        case .idle:
            await load(unread)
        case .ready where Date().timeIntervalSince(builtAt) > Self.staleAfter:
            await load(unread)
        default:
            break
        }
    }

    /// Forces a full rescore, e.g. from a settings button — same loading screen
    /// as the very first sort.
    @MainActor
    func reload(unread: [Summary]) async {
        await load(unread)
    }

    @MainActor
    private func load(_ unread: [Summary]) async {
        phase = .loading
        dismissed.removeAll()
        let scored = await Self.scoreAll(unread.map(ScoringInput.init))
        let byRoom = Dictionary(uniqueKeysWithValues: unread.map { ($0.id, $0) })
        let sorted = scored.sorted { $0.breakdown.total > $1.breakdown.total }

        for item in sorted { breakdowns[item.id] = item.breakdown }
        peak = sorted.filter { $0.breakdown.total >= Self.peakThreshold }.compactMap { byRoom[$0.id] }
        slope = sorted.filter { $0.breakdown.total < Self.peakThreshold }.compactMap { byRoom[$0.id] }
        placed = Set(sorted.map(\.id))
        builtAt = Date()
        phase = .ready
    }

    @MainActor
    func syncNewCards(unread: [Summary]) {
        guard phase == .ready else { return }
        let fresh = unread.filter { !placed.contains($0.id) && !dismissed.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { placed.insert($0.id) }   // reserve so churn can't double-add
        let byRoom = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        Task { @MainActor in
            for item in await Self.scoreAll(fresh.map(ScoringInput.init)) {
                guard let room = byRoom[item.id] else { continue }
                breakdowns[item.id] = item.breakdown
                if item.breakdown.total >= Self.peakThreshold { peak.append(room) }
                else { slope.append(room) }
            }
        }
    }

    /// Drops a swiped card from its pile. Marking the room read is the caller's
    /// job — the deck only owns membership.
    @MainActor
    func dismiss(_ summary: Summary) {
        peak.removeAll { $0.id == summary.id }
        slope.removeAll { $0.id == summary.id }
        placed.remove(summary.id)
        dismissed.insert(summary.id)
    }

    // MARK: - Scoring

    private struct Scored { let id: String; let breakdown: ScoreBreakdown }

    /// Scores rooms concurrently. `Room` is `Sendable` and `latestEvent()` is a
    /// one-shot read, so this needs no main-actor hops or timeline subscriptions.
    private nonisolated static func scoreAll(_ inputs: [ScoringInput]) async -> [Scored] {
        await withTaskGroup(of: Scored.self) { group in
            for input in inputs {
                group.addTask { Scored(id: input.id, breakdown: await scoreBreakdown(input)) }
            }
            var out: [Scored] = []
            for await scored in group { out.append(scored) }
            return out
        }
    }

    private nonisolated static func scoreBreakdown(_ input: ScoringInput) async -> ScoreBreakdown {
        let session = LanguageModelSession()
        let response = try? await session.respond(to: prompt(for: await latestLine(of: input.room)),
                                                  generating: Int.self)
        return ScoreBreakdown(
            mention: input.isMentioned ? 40 : 0,   // a direct mention is high priority
            favorite: input.isFavorite ? 30 : 0,
            directness: input.isDirect ? 10 : -10,
            lowPriority: input.isLowPriority ? -60 : 0,
            tone: response?.content ?? 0
        )
    }

    /// The room's newest message as one transcript line, or empty if there isn't
    /// a displayable one. Read via `latestEvent()` — no timeline needed.
    private nonisolated static func latestLine(of room: Room) async -> String {
        guard case .remote(let timestamp, let sender, _, let profile, let content) = await room.latestEvent(),
              let body = messageBody(of: content) else { return "" }
        let name = displayName(of: profile) ?? sender
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        return "\(name) (\(date.formatted(date: .abbreviated, time: .shortened))): \(body)"
    }

    private static func messageBody(of content: TimelineItemContent) -> String? {
        guard case .msgLike(let msg) = content else { return nil }
        switch msg.kind {
        case .message(let content): return content.body
        case .sticker(let body, _, _): return body
        default: return nil
        }
    }

    private static func displayName(of profile: ProfileDetails) -> String? {
        if case .ready(let name, _, _) = profile { return name }
        return nil
    }

    private nonisolated static func prompt(for transcript: String) -> String {
        """
        You are an expert inbox triage assistant for a messaging client. Your job is to read a chat log (which includes timestamps) and assign a Priority Score from 0 to 40 based ONLY on the urgency of the MOST RECENT unread state.

        You will receive up to the last 10 messages. The older messages are strictly provided for context to help you understand the newest ones.

        STEP 1: TIME & CONTEXT ANALYSIS
        Before scoring, mentally evaluate:
        - Recency Bias: Focus your score on the last 1 to 3 messages. If there was a crisis three days ago but the latest message is "All good now," the current priority is low.
        - Contextual Meaning: A single word like "Okay" or "Done" is usually low priority. However, if the prior message was "I'm outside, come down now!", an "Okay" means an event is actively happening.
        - Actionability: Does the *most recent* message require the user to drop what they are doing and reply or act today?

        STEP 2: FIND THE CLOSEST ANCHOR SCORE
        Match the current state of the conversation to one of these strict anchor points. Adjust slightly up or down, but stay close to these baselines:

        Anchor 0: Resolved or Pure Noise
        - The conversation is resolved (e.g., "Thanks!", "Done", "See ya").
        - Emojis, reactions, or automated alerts.

        Anchor 10: Casual Banter / FYI
        - Greetings ("Hey", "Morning!").
        - Statements sharing info without needing a reply.
        - Memes or casual links.

        Anchor 20: Standard Conversation (Non-Urgent)
        - Normal chit-chat.
        - Long-term planning ("Let's get lunch next week").
        - Questions that are not time-sensitive.

        Anchor 30: Important & Actionable
        - Direct questions directed at the user that need a response today.
        - Work-related updates or project questions.
        - Short-term logistics ("Where are we meeting tonight?", "Are you on your way?").

        Anchor 40: Urgent / Emergency
        - Time-sensitive crises or emergencies happening right now.
        - Explicit demands for immediate attention ("Call me NOW", "Server is down").
        - Critical, last-minute cancellations or schedule changes.

        STEP 3: ASSIGN THE SCORE
        Based on the MOST RECENT context, provide the final integer score (0-40).

        CONVERSATION TRANSCRIPT:
        \(transcript)
        """
    }
}
