//
//  DebugDepthPanelView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

#if DEBUG
import SwiftUI

/// Debug override panel for fixed-order depth-capable device rows.
///
/// Debug selection switches the whole SingleCam pipeline to the chosen
/// depth-capable device; this view only reflects capability-layer state.
struct DebugDepthPanelView: View {
    let options: [DebugDepthDeviceOption]
    let selectedID: String?
    @Binding var isExpanded: Bool
    let select: (DebugDepthDeviceOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(options) { option in
                        Button {
                            select(option)
                        } label: {
                            DebugDepthDeviceChip(
                                option: option,
                                isSelected: option.id == selectedID
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isSelectable)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "arkit")
                    .font(.caption.weight(.bold))
                    .frame(width: 38, height: 38)
                    .background(isExpanded ? .yellow.opacity(0.92) : .yellow.opacity(0.46), in: Circle())
                    .foregroundStyle(isExpanded ? .black : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Depth sources")
        }
    }
}

/// A single depth-capable device row inside `DebugDepthPanelView`.
///
/// Disabled/enabled state comes from `CapabilityMatrix`; the view does not
/// reorder devices or run compatibility checks.
struct DebugDepthDeviceChip: View {
    let option: DebugDepthDeviceOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: option.iconName)
                .font(.caption.weight(.bold))
            Text(option.displayName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 126, height: 34, alignment: .leading)
        .padding(.horizontal, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(foreground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? strokeColor : Color.clear, lineWidth: 1)
        }
    }

    private var background: Color {
        if !option.isSelectable {
            return .yellow.opacity(0.08)
        }
        return isSelected ? .yellow.opacity(0.92) : .yellow.opacity(0.48)
    }

    private var foreground: Color {
        if !option.isSelectable {
            return .white.opacity(0.36)
        }
        return isSelected ? .black : .white
    }

    private var strokeColor: Color {
        .white.opacity(0.34)
    }
}


#endif
