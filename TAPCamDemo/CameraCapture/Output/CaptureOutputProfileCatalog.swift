//
//  CaptureOutputProfileCatalog.swift
//  TAPCamDemo
//

import Foundation

/// Reviewable list of output profiles the app is willing to execute.
///
/// This is intentionally not a settings screen or feature flag. It is the
/// catalog future format/quality UI must go through before it can request a
/// different JPEG, RAW, video, or HEIC-depth path.
nonisolated struct CaptureOutputProfileCatalog: Equatable, Sendable {
    static let releaseDefaultProfile = CaptureOutputProfile.releasePhotoDepthHEIC
    static let release = CaptureOutputProfileCatalog(
        defaultProfileID: releaseDefaultProfile.id,
        profiles: [
            releaseDefaultProfile,
            .releasePhotoDepthJPEG
        ]
    )

    let defaultProfileID: String
    let profiles: [CaptureOutputProfile]

    var profileIDs: [String] {
        profiles.map(\.id)
    }

    var defaultProfile: CaptureOutputProfile? {
        profile(id: defaultProfileID)
    }

    var executableProfiles: [CaptureOutputProfile] {
        profiles.filter(\.contractViolations.isEmpty)
    }

    var contractViolations: [CaptureOutputProfileCatalogViolation] {
        var violations: [CaptureOutputProfileCatalogViolation] = []

        let normalizedIDs = profiles.map { Self.normalizedProfileID($0.id) }
        let groupedIDs = Dictionary(grouping: normalizedIDs, by: { $0 })
        for id in groupedIDs.keys.sorted() where groupedIDs[id, default: []].count > 1 {
            violations.append(.duplicateProfileID(id))
        }

        if profile(id: defaultProfileID) == nil {
            violations.append(.missingDefaultProfile(Self.normalizedProfileID(defaultProfileID)))
        }

        for profile in profiles {
            let profileViolations = profile.contractViolations
            if !profileViolations.isEmpty {
                violations.append(.invalidProfile(
                    id: Self.normalizedProfileID(profile.id),
                    violations: profileViolations
                ))
            }
        }

        return violations
    }

    func profile(id: String) -> CaptureOutputProfile? {
        let normalizedID = Self.normalizedProfileID(id)
        return profiles.first { Self.normalizedProfileID($0.id) == normalizedID }
    }

    private static func normalizedProfileID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum CaptureOutputProfileCatalogViolation: Equatable, Sendable {
    case duplicateProfileID(String)
    case missingDefaultProfile(String)
    case invalidProfile(id: String, violations: [CaptureOutputContractViolation])

    var readerDescription: String {
        switch self {
        case .duplicateProfileID(let id):
            "Output profile catalog contains duplicate profile id '\(id)'."
        case .missingDefaultProfile(let id):
            "Output profile catalog default id '\(id)' does not match a profile."
        case .invalidProfile(let id, let violations):
            "Output profile '\(id)' violates its contract: \(violations.map(\.readerDescription).joined(separator: " "))"
        }
    }
}
