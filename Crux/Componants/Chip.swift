//
//  Chip.swift
//  Crux
//
//  Created by Joshua Kellman on 8/5/26.
//

import SwiftUI

///
struct Chip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule)
    }
    
    enum Presets {
        static let muted = Chip(icon: "bell.slash.fill", label: "Muted", color: .secondary)
        static let lowPriority = Chip(icon: "arrow.down.circle.fill", label: "Low Priority", color: .gray)
        static let group = Chip(icon: "person.2.fill", label: "Group", color: .purple)
        static let direct = Chip(icon: "person.fill", label: "Direct", color: .blue)
        static let favorite = Chip(icon: "star.fill", label: "Favorite", color: .yellow)
        static let mentioned = Chip(icon: "at", label: "Mentioned", color: .red)
    }
    
}
