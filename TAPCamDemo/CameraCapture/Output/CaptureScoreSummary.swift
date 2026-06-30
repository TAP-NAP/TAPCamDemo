//
//  CaptureScoreSummary.swift
//  TAPCamDemo
//

import Foundation

nonisolated struct CaptureScoreSummary: Codable, Equatable, Sendable {
    let value: Int
    let grade: String
    let detail: String
    let accessibilityText: String

    var scoreText: String {
        "\(value)/100"
    }

    static func make(
        depthAvailability: CaptureDepthAvailability,
        fileContainer: CapturePhotoFileContainer,
        photoQualityLevel: CapturePhotoQualityLevel,
        signatureStatus: CaptureSignatureStatus
    ) -> CaptureScoreSummary {
        let depthPoints: Int
        let depthText: String
        switch depthAvailability {
        case .available:
            depthPoints = 35
            depthText = "Depth available"
        case .unavailable:
            depthPoints = 5
            depthText = "Depth unavailable"
        }

        let formatPoints: Int
        let formatText: String
        switch fileContainer {
        case .heic:
            formatPoints = 15
            formatText = "HEIC"
        case .jpeg:
            formatPoints = 12
            formatText = "JPG"
        }

        let qualityPoints: Int
        switch photoQualityLevel {
        case .speed:
            qualityPoints = 9
        case .balanced:
            qualityPoints = 12
        case .quality:
            qualityPoints = 15
        }

        let signaturePoints: Int
        let signatureText: String
        switch signatureStatus {
        case .signed:
            signaturePoints = 25
            signatureText = "Capture signed"
        case .pending:
            signaturePoints = 18
            signatureText = "Signing pending"
        case .unsigned:
            signaturePoints = 8
            signatureText = "Capture unsigned"
        }

        let analysisPoints = depthAvailability == .available ? 10 : 5
        let analysisText = depthAvailability == .available ? "Analysis ready" : "No Depth analysis ready"
        let value = min(max(depthPoints + formatPoints + qualityPoints + signaturePoints + analysisPoints, 0), 100)
        let grade = Self.grade(for: value)
        let detail = [
            depthText,
            formatText,
            photoQualityLevel.manifestDescription.capitalized,
            signatureText,
            analysisText
        ].joined(separator: " · ")

        return CaptureScoreSummary(
            value: value,
            grade: grade,
            detail: detail,
            accessibilityText: "Capture score \(value) out of 100. \(grade). \(detail)."
        )
    }

    static let unknown = CaptureScoreSummary(
        value: 0,
        grade: "Unknown",
        detail: "Capture score unavailable",
        accessibilityText: "Capture score unavailable."
    )

    private static func grade(for value: Int) -> String {
        switch value {
        case 85...:
            "Strong"
        case 70..<85:
            "Usable"
        case 40..<70:
            "Limited"
        default:
            "Unavailable"
        }
    }
}
