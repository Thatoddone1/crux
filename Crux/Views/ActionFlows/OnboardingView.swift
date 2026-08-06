//
//  OnboardingView.swift
//  Crux
//
//  Created by Joshua Kellman on 7/30/26.
//


import SwiftUI

struct OnboardingView: View {
    // Allows the view to dismiss itself
    @Environment(\.dismiss) private var dismiss

    // If true, shows "Next" and "Skip". If false (viewed from Settings), just a "Done" button.
    var showsLoginActions: Bool = true

    @State private var currentPage = 0
    private let totalPages = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                WelcomePage().tag(0)
                MountainPage().tag(1)
                RoomsSpacesPage().tag(2)
                MatrixNetworkPage().tag(3)
                MatrixIDPage().tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom Action Area
            VStack(spacing: 16) {
                if showsLoginActions {
                    Button(action: advance) {
                        Text(isLastPage ? "Let's Go" : "Next")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }

                    Button("Skip") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .opacity(isLastPage ? 0 : 1)
                        .animation(.easeInOut, value: currentPage)
                } else {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 16)
        }
    }

    private var isLastPage: Bool { currentPage == totalPages - 1 }

    private func advance() {
        if isLastPage {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage += 1
            }
        }
    }
}

// MARK: - Page 1: Welcome
private struct WelcomePage: View {
    var body: some View {
        OnboardingPage {
            CruxLogo()

            VStack(spacing: 12) {
                Text("Welcome to Crux")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("A Matrix chat app that sorts your messages by priority, so the ones that matter reach you first.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Page 2: The Mountain (Peak & Slope)
private struct MountainPage: View {
    enum Zone { case peak, slope }
    @State private var highlight: Zone?

    var body: some View {
        OnboardingPage {
            VStack(spacing: 8) {
                Text("Sorted like a mountain")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your unread chats stack up by importance — the top of the pile is always what matters most.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            PriorityMountain(focus: highlight)
                .frame(height: 220)

            VStack(spacing: 12) {
                ZoneRow(title: "The Peak",
                        icon: "mountain.2.fill",
                        tint: .accentColor,
                        detail: "Crux gives each unread conversation a priority score based upon attributes of the room. The highest land here at the peak.",
                        selected: highlight == .peak) {
                    toggle(.peak)
                }
                ZoneRow(title: "The Slope",
                        icon: "arrow.down.forward",
                        tint: .gray,
                        detail: "Lower-scoring chats tuck away below, collapsed and out of the way, ready whenever you want them.",
                        selected: highlight == .slope) {
                    toggle(.slope)
                }
            }
            .padding(.horizontal)
        }
    }

    private func toggle(_ zone: Zone) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            highlight = (highlight == zone) ? nil : zone
        }
    }
}

/// A tappable Peak/Slope row that expands to a fuller explanation when selected.
private struct ZoneRow: View {
    let title: String
    let icon: String
    let tint: Color
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(selected ? 0 : -90))
                    }
                    if selected {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? tint.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page 3: Getting around (Rooms & Spaces)
private struct RoomsSpacesPage: View {
    var body: some View {
        OnboardingPage {
            SpaceRoomsGraphic()
                .frame(height: 120)

            VStack(spacing: 8) {
                Text("Rooms & Spaces")
                    .font(.title)
                    .fontWeight(.bold)

                Text("How Matrix organizes your conversations")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                BenefitRow(icon: "bubble.left.and.bubble.right.fill", tint: .blue,
                           title: "A Room is a conversation",
                           detail: "A direct message or a group chat — this is where you actually talk.")
                BenefitRow(icon: "square.stack.3d.up.fill", tint: .purple,
                           title: "A Space is a group of rooms",
                           detail: "Like a folder or a community: open a Space to find the rooms inside. A Space isn't a chat on its own.")
            }

            Label {
                Text("Find them in the tabs below — **Mountain** for what's urgent, **Rooms** for every conversation, **Spaces** for your communities.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - Page 4: What Matrix is (the open network)
private struct MatrixNetworkPage: View {
    var body: some View {
        OnboardingPage {
            FederationDiagram()
                .frame(height: 150)

            VStack(spacing: 8) {
                Text("An open network")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Crux runs on **Matrix**: a network of independent servers that all pass messages to each other, a bit like how email providers do.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                BenefitRow(icon: "globe", tint: .blue,
                           title: "No single owner",
                           detail: "Anyone can run a server, and no one can lock you out of the network.")
                BenefitRow(icon: "lock.fill", tint: .green,
                           title: "End-to-end encrypted",
                           detail: "Only you and the people you're talking to can read your messages.")
                BenefitRow(icon: "arrow.left.arrow.right", tint: .orange,
                           title: "Everyone can reach everyone",
                           detail: "Pick any server and still message anyone, anywhere on Matrix, using any Matrix app.")
            }
        }
    }
}

// MARK: - Page 5: "breaking apart" MXIDs
private struct MatrixIDPage: View {
    var body: some View {
        OnboardingPage {
            VStack(spacing: 8) {
                Text("Your Matrix address")
                    .font(.title)
                    .fontWeight(.bold)

                Text("On Matrix, your account has an address that looks a lot like an email. Tap each part to see what it means.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            MatrixIDAnatomy()

            Label {
                Text("This address is yours across **all of Matrix** — use it to sign in to any Matrix compatible app, not just Crux. You can find other compatible apps [here](https://matrix.org/ecosystem/clients/)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - Shared page container

/// Centers content when it fits and scrolls it when it doesn't, so pages stay
/// readable at any Dynamic Type size instead of truncating.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) { content() }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}

// MARK: - Reusable pieces

private struct BenefitRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A simple two-peak mountain silhouette
private struct MountainRange: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.38))   // left peak
        p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.66))   // valley
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.08))   // main peak (the crux)
        p.addLine(to: CGPoint(x: w, y: h * 0.55))          // ridge down to the right
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

///used to show peak slope, just a nice graphic
private struct PriorityMountain: View {
    var focus: MountainPage.Zone?

    private var peakUp: Bool { focus != .slope }
    private var slopeUp: Bool { focus != .peak }

    var body: some View {
        ZStack(alignment: .bottom) {
            MountainRange()
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom))

            // Example chats, stacked from summit (important) down the slope (quiet).
            VStack(spacing: 10) {
                ChatChip(initial: "A", tint: .pink, name: "Alex", preview: "Are you free tonight?",
                         emphasized: true)
                    .opacity(peakUp ? 1 : 0.35)
                    .scaleEffect(focus == .peak ? 1.04 : 1, anchor: .center)

                ChatChip(initial: "B", tint: .blue, name: "Book club", preview: "See you Thursday!",
                         emphasized: false)
                    .opacity(slopeUp ? 0.95 : 0.35)

                ChatChip(initial: "J", tint: .orange, name: "Jamie", preview: "haha yeah for sure",
                         emphasized: false)
                    .opacity(slopeUp ? 0.8 : 0.3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focus)
        }
    }
}

/// A compact, realistic conversation row used to populate the mountain chats (in priority mountain)
private struct ChatChip: View {
    let initial: String
    let tint: Color
    let name: String
    let preview: String
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(initial)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(preview).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)

            if emphasized {
                Circle().fill(Color.accentColor).frame(width: 9, height: 9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(emphasized ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}

/// The Crux app logo on the welcome screen.
private struct CruxLogo: View {
    var body: some View {
        Image("crux-icon")
            .resizable()
            .scaledToFit()
            .frame(width: 132, height: 132)
            .shadow(color: Color(red: 0.0, green: 0.851, blue: 0.537).opacity(0.3), radius: 16, x: 0, y: 8)
    }
}


private struct SpaceRoomsGraphic: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    VStack(spacing: 6) {
                        roomChip
                        roomChip
                        roomChip
                    }
                    .padding(12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.purple.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
                .frame(width: 190, height: 110)

            Text("A Space holds Rooms")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var roomChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Two people on two different servers exchanging a message across the network.
private struct FederationDiagram: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midY = geo.size.height * 0.42
            let clientA = CGPoint(x: w * 0.10, y: midY)
            let serverA = CGPoint(x: w * 0.33, y: midY)
            let serverB = CGPoint(x: w * 0.67, y: midY)
            let clientB = CGPoint(x: w * 0.90, y: midY)

            ZStack {
                // Links: client-to-server (short) and server-to-server (the network hop).
                link(clientA, serverA, dashed: false)
                link(serverA, serverB, dashed: true)
                link(serverB, clientB, dashed: false)

                node(icon: "person.fill", tint: .secondary, at: clientA, label: "You")
                node(icon: "server.rack", tint: .blue, at: serverA, label: "matrix.org")
                node(icon: "server.rack", tint: .purple, at: serverB, label: "yourserver.com")
                node(icon: "person.fill", tint: .secondary, at: clientB, label: "A friend")

                // The message travelling from one server to the other.
                Image(systemName: "bubble.left.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.accentColor.gradient)
                    .clipShape(Circle())
                    .shadow(radius: 3)
                    .position(x: animate ? serverB.x : serverA.x, y: midY)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: animate)
            }
            .onAppear { animate = true }
        }
    }

    private func link(_ a: CGPoint, _ b: CGPoint, dashed: Bool) -> some View {
        Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }
        .stroke(Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
    }

    private func node(icon: String, tint: Color, at point: CGPoint, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 3)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .position(x: point.x, y: point.y + 6)
    }
}

/// An interactive `@you:server` breakdown — tap a part to learn what it does.
private struct MatrixIDAnatomy: View {
    private enum Part: CaseIterable {
        case sigil, username, separator, server

        var explanation: String {
            switch self {
            case .sigil: "Every Matrix address starts with @. It simply means \"a person.\""
            case .username: "Your username — chosen when you make your account, and it cannot be changed!"
            case .separator: "The colon separates who you are from where your account lives."
            case .server: "Your homeserver — the community that hosts your account, like the part after @ in an email address."
            }
        }
    }

    @State private var selected: Part?

    var body: some View {
        VStack(spacing: 16) {
            // The address, laid out as tappable parts
            HStack(spacing: 0) {
                segment("@", part: .sigil)
                segment("you", part: .username)
                segment(":", part: .separator)
                segment("matrix.org", part: .server)
            }
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)

            // Explanation for the selected part
            Text(selected?.explanation ?? "Tap each part above to learn what it means.")
                .font(.subheadline)
                .foregroundColor(selected == nil ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 60, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut, value: selected)
        }
    }

    private func segment(_ text: String, part: Part) -> some View {
        Text(text)
            .foregroundColor(selected == part ? .white : color(for: part))
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected == part ? color(for: part) : .clear)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selected = (selected == part) ? nil : part
                }
            }
    }

    private func color(for part: Part) -> Color {
        switch part {
        case .sigil, .separator: .secondary
        case .username: .accentColor
        case .server: .purple
        }
    }
}


#Preview {
    OnboardingView(
        showsLoginActions: true
    )
}
