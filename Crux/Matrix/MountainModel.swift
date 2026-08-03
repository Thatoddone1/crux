//
//  MountainModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK
import FoundationModels


@Observable
final class MountainModel {
    typealias Summary = RoomListModel.Summary

    enum Phase { case idle, loading, ready }
    private(set) var phase: Phase = .idle

    private(set) var peak: [Summary] = []
    private(set) var slope: [Summary] = []
    /// Frozen scores for the badge, keyed by room id.
    private(set) var scores: [String: Int] = [:]

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

    @MainActor
    private func load(_ unread: [Summary]) async {
        phase = .loading
        dismissed.removeAll()
        let sorted = await Self.scoreAll(unread).sorted { $0.score > $1.score }
        scores = Dictionary(sorted.map { ($0.summary.id, $0.score) }, uniquingKeysWith: { a, _ in a })
        peak = sorted.filter { $0.score >= Self.peakThreshold }.map(\.summary)
        slope = sorted.filter { $0.score < Self.peakThreshold }.map(\.summary)
        placed = Set(sorted.map(\.summary.id))
        builtAt = Date()
        phase = .ready
    }

    
    @MainActor
    func syncNewCards(unread: [Summary]) {
        guard phase == .ready else { return }
        let fresh = unread.filter { !placed.contains($0.id) && !dismissed.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { placed.insert($0.id) }   // reserve so churn can't double-add
        Task { @MainActor in
            for item in await Self.scoreAll(fresh) {
                scores[item.summary.id] = item.score
                if item.score >= Self.peakThreshold { peak.append(item.summary) }
                else { slope.append(item.summary) }
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

    private struct Scored { let summary: Summary; let score: Int }

    /// Scores rooms concurrently. `Room` is `Sendable` and `latestEvent()` is a
    /// one-shot read, so this needs no main-actor hops or timeline subscriptions.
    private nonisolated static func scoreAll(_ summaries: [Summary]) async -> [Scored] {
        await withTaskGroup(of: Scored.self) { group in
            for summary in summaries {
                group.addTask { Scored(summary: summary, score: await score(summary)) }
            }
            var out: [Scored] = []
            for await scored in group { out.append(scored) }
            return out
        }
    }

    private nonisolated static func score(_ summary: Summary) async -> Int {
        var score = 0
        if summary.unreadMentions > 0 { score += 40 }   // a direct mention is high priority
        if summary.isFavorite { score += 30 }
        if summary.isDirect { score += 10 } else { score -= 10 }
        if summary.isLowPriority { score -= 60 }

        let session = LanguageModelSession()
        let response = try? await session.respond(to: prompt(for: await latestLine(of: summary.room)),
                                                  generating: Int.self)
        score += response?.content ?? 0
        return min(max(score, 0), 100)
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
