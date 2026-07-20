//
//  CaptureOutputProfileSelectionIntent.swift
//  TAPCamDemo
//

import Foundation

/// Future request for choosing an output profile from a reviewed catalog.
///
/// This is not a settings screen and it does not create new output formats. It
/// is a pure value boundary that future UI or product policy can use before
/// Runtime receives a `CaptureOutputProfile`.
nonisolated struct CaptureOutputProfileSelectionIntent: Equatable, Sendable {
    nonisolated enum Request: Equatable, Sendable {
        case releaseDefault
        case profile(id: String)
    }

    let request: Request

    static let releaseDefault = CaptureOutputProfileSelectionIntent(request: .releaseDefault)

    func resolved(
        in catalog: CaptureOutputProfileCatalog = .release
    ) -> CaptureOutputProfileSelectionResolution {
        let requestedProfileID = self.requestedProfileID(in: catalog)
        var violations = catalog.contractViolations.map {
            CaptureOutputProfileSelectionViolation.catalogViolation($0)
        }

        if explicitlyRequestsEmptyProfileID {
            violations.append(.emptyRequestedProfileID)
        }

        let requestedProfile = explicitlyRequestsEmptyProfileID ? nil : catalog.profile(id: requestedProfileID)
        if requestedProfile == nil && !explicitlyRequestsEmptyProfileID {
            violations.append(.requestedProfileMissing(requestedProfileID))
        }

        if let profileViolations = requestedProfile?.contractViolations,
           !profileViolations.isEmpty {
            violations.append(.requestedProfileInvalid(
                id: requestedProfileID,
                violations: profileViolations
            ))
        }

        return CaptureOutputProfileSelectionResolution(
            intent: self,
            requestedProfileID: requestedProfileID,
            selectedProfile: violations.isEmpty ? requestedProfile : nil,
            violations: violations
        )
    }

    private func requestedProfileID(in catalog: CaptureOutputProfileCatalog) -> String {
        switch request {
        case .releaseDefault:
            catalog.defaultProfileID
        case .profile(let id):
            Self.normalizedProfileID(id)
        }
    }

    private var explicitlyRequestsEmptyProfileID: Bool {
        switch request {
        case .releaseDefault:
            false
        case .profile(let id):
            Self.normalizedProfileID(id).isEmpty
        }
    }

    private static func normalizedProfileID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct CaptureOutputProfileSelectionResolution: Equatable, Sendable {
    let intent: CaptureOutputProfileSelectionIntent
    let requestedProfileID: String
    let selectedProfile: CaptureOutputProfile?
    let violations: [CaptureOutputProfileSelectionViolation]

    var isExecutable: Bool {
        selectedProfile != nil && violations.isEmpty
    }
}

/// Public-safe status for future output-format or quality UI.
///
/// `CaptureOutputProfileSelectionViolation.readerDescription` is intentionally
/// developer-facing and can contain catalog/profile identifiers. Future visible
/// UI should use this presentation instead so missing or invalid profile ids do
/// not become user-visible strings.
nonisolated struct CaptureOutputProfileSelectionPresentation: Equatable, Sendable {
    nonisolated enum Status: Equatable, Sendable {
        case ready
        case blocked
    }

    let status: Status
    let title: String
    let detail: String
    let requestedProfileLabel: String
    let selectedProfileLabel: String?
    let issueLabels: [String]

    init(resolution: CaptureOutputProfileSelectionResolution) {
        requestedProfileLabel = Self.requestedProfileLabel(for: resolution.intent)
        selectedProfileLabel = resolution.selectedProfile.map(Self.profileLabel(for:))
        issueLabels = resolution.violations.map(Self.issueLabel(for:))

        if resolution.isExecutable {
            status = .ready
            title = "Output profile ready"
            detail = "The selected output profile matches the reviewed capture contract."
        } else {
            status = .blocked
            title = "Output profile unavailable"
            detail = "The requested output profile is missing, invalid, or outside the reviewed catalog."
        }
    }

    private static func requestedProfileLabel(for intent: CaptureOutputProfileSelectionIntent) -> String {
        switch intent.request {
        case .releaseDefault:
            "Release default"
        case .profile:
            "Explicit output profile"
        }
    }

    private static func profileLabel(for profile: CaptureOutputProfile) -> String {
        switch profile.container {
        case .embeddedPhotoDepthHEIC:
            "Photo-depth HEIC"
        case .embeddedPhotoDepthJPEG:
            "Photo-depth JPG"
        }
    }

    private static func issueLabel(for violation: CaptureOutputProfileSelectionViolation) -> String {
        switch violation {
        case .catalogViolation:
            "Reviewed output catalog is not valid."
        case .emptyRequestedProfileID:
            "Requested output profile is empty."
        case .requestedProfileMissing:
            "Requested output profile is not in the reviewed catalog."
        case .requestedProfileInvalid:
            "Requested output profile violates the current output contract."
        }
    }
}

nonisolated enum CaptureOutputProfileSelectionViolation: Equatable, Sendable {
    case catalogViolation(CaptureOutputProfileCatalogViolation)
    case emptyRequestedProfileID
    case requestedProfileMissing(String)
    case requestedProfileInvalid(id: String, violations: [CaptureOutputContractViolation])

    var readerDescription: String {
        switch self {
        case .catalogViolation(let violation):
            violation.readerDescription
        case .emptyRequestedProfileID:
            "Requested output profile id is empty."
        case .requestedProfileMissing(let id):
            "Requested output profile '\(id)' is not present in the catalog."
        case .requestedProfileInvalid(let id, let violations):
            "Requested output profile '\(id)' violates its contract: \(violations.map(\.readerDescription).joined(separator: " "))"
        }
    }
}
