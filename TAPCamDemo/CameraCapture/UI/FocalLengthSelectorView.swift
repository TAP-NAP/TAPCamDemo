//
//  FocalLengthSelectorView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI

/// Compact release FOV selector rendered over the bottom of the preview.
///
/// The view receives already-planned `FocalLengthOption` values; it does not
/// inspect camera devices or infer depth compatibility on its own.
struct FocalLengthSelectorView: View {
    let options: [FocalLengthOption]
    let selectedID: String?
    let contentRotation: Angle
    let select: (FocalLengthOption) -> Void

    var body: some View {
        let selectorWidth = min(contentWidth, maximumVisibleWidth)

        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            select(option)
                        } label: {
                            ZStack {
                                VStack(spacing: 0) {
                                    Text(option.numericLabel)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                    Text(option.unitLabel)
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .textCase(.lowercase)
                                }
                                .rotationEffect(contentRotation)
                            }
                            .frame(width: 48, height: 42)
                            .background(background(for: option), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .foregroundStyle(foreground(for: option))
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isEnabled)
                        .accessibilityLabel("Use \(option.displayName) field of view")
                    }
                }
                /*
                 A horizontal ScrollView lays out its content from the leading
                 edge. Giving the chip row at least the visible container width
                 keeps small option sets centered, while still allowing larger
                 sets to scroll naturally.
                 */
                .padding(.horizontal, 6)
                .frame(minWidth: proxy.size.width, minHeight: 52, alignment: .center)
            }
        }
        .frame(width: selectorWidth)
        .frame(height: 52)
        .background(.black.opacity(0.44), in: Capsule())
    }

    private var contentWidth: CGFloat {
        let count = CGFloat(options.count)
        let gaps = CGFloat(max(options.count - 1, 0))
        return count * 48 + gaps * 8 + 12
    }

    private var maximumVisibleWidth: CGFloat {
        232
    }

    private func background(for option: FocalLengthOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.08)
        }
        return option.id == selectedID ? .white.opacity(0.92) : .white.opacity(0.18)
    }

    private func foreground(for option: FocalLengthOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.36)
        }
        return option.id == selectedID ? .black : .white
    }
}
