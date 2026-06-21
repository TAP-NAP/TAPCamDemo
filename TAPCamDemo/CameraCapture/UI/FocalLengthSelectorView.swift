//
//  FocalLengthSelectorView.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/27.
//

import SwiftUI

/// Display-only FOV chip state for the preview stage.
///
/// The token is an opaque UI value resolved by `CameraView`; this type does not
/// carry camera profiles, depth profiles, raw device identifiers, or zoom plans.
struct CameraFocalLengthDisplayOption: Identifiable, Equatable, Sendable {
    let selectionToken: String
    let displayName: String
    let numericLabel: String
    let unitLabel: String
    let isSelected: Bool
    let isEnabled: Bool

    var id: String {
        selectionToken
    }
}

/// Compact release FOV selector rendered over the bottom of the preview.
///
/// The view receives display-only options; it does not inspect camera devices,
/// receive raw camera identifiers, or infer depth compatibility on its own.
struct FocalLengthSelectorView: View {
    let options: [CameraFocalLengthDisplayOption]
    let contentRotation: Angle
    let select: (CameraFocalLengthDisplayOption) -> Void

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

    private func background(for option: CameraFocalLengthDisplayOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.08)
        }
        return option.isSelected ? .white.opacity(0.92) : .white.opacity(0.18)
    }

    private func foreground(for option: CameraFocalLengthDisplayOption) -> Color {
        if !option.isEnabled {
            return .white.opacity(0.36)
        }
        return option.isSelected ? .black : .white
    }
}
