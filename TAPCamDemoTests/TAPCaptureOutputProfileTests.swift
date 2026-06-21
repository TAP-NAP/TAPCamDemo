//
//  TAPCaptureOutputProfileTests.swift
//  TAPCamDemoTests
//

import AVFoundation
import Foundation
import Testing
@testable import TAPCamDemo

struct TAPCaptureOutputProfileTests {
    @Test func releaseOutputProfileNamesCurrentHEICDepthPolicy() throws {
        let profile = CaptureOutputProfile.releasePhotoDepthHEIC

        #expect(profile.id == "release.photo-depth.heic")
        #expect(profile.container == .embeddedPhotoDepthHEIC)
        #expect(profile.codecPreference == [.hevc])
        #expect(profile.depthDataDeliveryEnabled)
        #expect(profile.embedsDepthDataInPhoto)
        #expect(profile.depthDataFiltered)
        #expect(profile.requiresDepthData)
        #expect(profile.photoQualityPolicy == .releaseQuality)
        #expect(profile.photoQualityPrioritization == .quality)
        #expect(profile.maxPhotoQualityPrioritization == .quality)
        #expect(profile.contractViolations.isEmpty)
    }

    @Test func capturePhotoQualityPolicyNamesAppLevelQualityBeforeAVFoundation() throws {
        let policy = CapturePhotoQualityPolicy.releaseQuality

        #expect(policy.requested == .quality)
        #expect(policy.maximum == .quality)
        #expect(!policy.exceedsConfiguredMaximum)
        #expect(policy.requested.manifestDescription == "quality")
        #expect(policy.assurances == [
            .avFoundationPrioritizationOnly,
            .noFileSizeGuarantee,
            .noCompressionRatioGuarantee,
            .preservesReviewedDepthContract
        ])
        #expect(policy.avFoundationRequestedPrioritization == .quality)
        #expect(policy.avFoundationMaximumPrioritization == .quality)
        #expect(CapturePhotoQualityPolicy(requested: .quality, maximum: .balanced).exceedsConfiguredMaximum)
        #expect(!CapturePhotoQualityPolicy(requested: .balanced, maximum: .quality).exceedsConfiguredMaximum)
    }

    @Test func tapDepthManifestUsesPhotoQualityPolicyManifestDescription() throws {
        let releaseProfile = CaptureOutputProfile.releasePhotoDepthHEIC
        let samplePayload = TAPCamDemoTestFixtures.samplePayload(location: nil)

        #expect(releaseProfile.photoQualityPolicy.requested.manifestDescription == "quality")
        #expect(samplePayload.capture.photoQualityPrioritization == "quality")
        #expect(samplePayload.capture.photoQualityPrioritization == releaseProfile.photoQualityPolicy.requested.manifestDescription)
    }

    @Test func releaseOutputProfileCatalogNamesSingleExecutableDefault() throws {
        let catalog = CaptureOutputProfileCatalog.release

        #expect(catalog.defaultProfile == .releasePhotoDepthHEIC)
        #expect(catalog.profileIDs == ["release.photo-depth.heic"])
        #expect(catalog.executableProfiles == [.releasePhotoDepthHEIC])
        #expect(catalog.contractViolations.isEmpty)
    }

    @Test func outputProfileCatalogSurfacesInvalidProfileSets() throws {
        let invalidProfile = CaptureOutputProfile(
            id: "release.photo-depth.heic",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc, .jpeg],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: CapturePhotoQualityPolicy(requested: .quality, maximum: .balanced)
        )
        let catalog = CaptureOutputProfileCatalog(
            defaultProfileID: "missing.default",
            profiles: [.releasePhotoDepthHEIC, invalidProfile]
        )

        #expect(catalog.defaultProfile == nil)
        #expect(catalog.contractViolations.contains(.duplicateProfileID("release.photo-depth.heic")))
        #expect(catalog.contractViolations.contains(.missingDefaultProfile("missing.default")))
        #expect(catalog.contractViolations.contains(.invalidProfile(
            id: "release.photo-depth.heic",
            violations: [
                .heicContainerAllowsNonHEVCCodec,
                .requestedQualityExceedsConfiguredMaximum
            ]
        )))
    }

    @Test func releaseOutputProfileRequiresHEVCAndDoesNotFallbackToJPEG() throws {
        let profile = CaptureOutputProfile.releasePhotoDepthHEIC

        #expect(profile.preferredCodec(availablePhotoCodecTypes: [.jpeg, .hevc]) == .hevc)
        #expect(profile.preferredCodec(availablePhotoCodecTypes: [.jpeg]) == nil)
        #expect(try profile.requiredCodec(availablePhotoCodecTypes: []) == .hevc)

        do {
            _ = try profile.requiredCodec(availablePhotoCodecTypes: [.jpeg])
            Issue.record("Expected release output profile to reject JPEG-only codec availability.")
        } catch TAPDepthCaptureError.captureOutputCodecUnsupported(let reason) {
            #expect(reason.contains("release.photo-depth.heic"))
        } catch {
            Issue.record("Unexpected output profile error: \(error)")
        }
    }

    @Test func outputProfileRejectsDepthAndQualityContractDrift() throws {
        let noDepthDelivery = CaptureOutputProfile(
            id: "bad.no-depth",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc],
            depthDataDeliveryEnabled: false,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: .releaseQuality
        )
        let noRequiredDepth = CaptureOutputProfile(
            id: "bad.no-required-depth",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: false,
            photoQualityPolicy: .releaseQuality
        )
        let qualityMismatch = CaptureOutputProfile(
            id: "bad.quality",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: CapturePhotoQualityPolicy(requested: .quality, maximum: .balanced)
        )
        let jpegFallback = CaptureOutputProfile(
            id: "bad.jpeg-fallback",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc, .jpeg],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: .releaseQuality
        )

        #expect(noDepthDelivery.contractViolations.contains(.requiredDepthWithoutDepthDelivery))
        #expect(noRequiredDepth.contractViolations.contains(.photoDepthContainerWithoutRequiredDepth))
        #expect(qualityMismatch.contractViolations.contains(.requestedQualityExceedsConfiguredMaximum))
        #expect(jpegFallback.contractViolations.contains(.heicContainerAllowsNonHEVCCodec))
    }

    @Test func outputProfileResolutionProducesSingleRuntimeRequest() throws {
        let resolved = try CaptureOutputProfile.releasePhotoDepthHEIC.resolvedPhotoOutput(
            availablePhotoCodecTypes: [.jpeg, .hevc]
        )

        #expect(resolved.profileID == "release.photo-depth.heic")
        #expect(resolved.container == .embeddedPhotoDepthHEIC)
        #expect(resolved.codec == .hevc)
        #expect(resolved.depthDataDeliveryEnabled)
        #expect(resolved.embedsDepthDataInPhoto)
        #expect(resolved.depthDataFiltered)
        #expect(resolved.requiresDepthData)
        #expect(resolved.photoQualityPolicy == .releaseQuality)
        #expect(resolved.photoQualityPrioritization == .quality)
        #expect(resolved.maxPhotoQualityPrioritization == .quality)
    }

    @Test func resolvedOutputValidatesPhotoOutputCapabilities() throws {
        let resolved = try CaptureOutputProfile.releasePhotoDepthHEIC.resolvedPhotoOutput(
            availablePhotoCodecTypes: [.hevc]
        )
        let matchingCapabilities = CapturePhotoOutputCapabilitySnapshot(
            availablePhotoCodecTypes: [.jpeg, .hevc],
            isDepthDataDeliverySupported: true,
            isDepthDataDeliveryEnabled: true,
            maxPhotoQualityPrioritization: .quality
        )

        try resolved.validatePhotoOutputCapabilities(matchingCapabilities)
        try resolved.validatePhotoOutputCapabilities(CapturePhotoOutputCapabilitySnapshot(
            availablePhotoCodecTypes: [],
            isDepthDataDeliverySupported: true,
            isDepthDataDeliveryEnabled: true,
            maxPhotoQualityPrioritization: .quality
        ))
        try resolved.validatePhotoOutputCapabilities(
            CapturePhotoOutputCapabilitySnapshot(
                availablePhotoCodecTypes: [.hevc],
                isDepthDataDeliverySupported: true,
                isDepthDataDeliveryEnabled: false,
                maxPhotoQualityPrioritization: .balanced
            )
        )

        do {
            try resolved.validatePhotoOutputCapabilities(CapturePhotoOutputCapabilitySnapshot(
                availablePhotoCodecTypes: [.jpeg],
                isDepthDataDeliverySupported: true,
                isDepthDataDeliveryEnabled: true,
                maxPhotoQualityPrioritization: .quality
            ))
            Issue.record("Resolved output must reject missing HEVC capability.")
        } catch TAPDepthCaptureError.captureOutputCodecUnsupported(let reason) {
            #expect(reason.contains("release.photo-depth.heic"))
            #expect(reason.contains("hvc1"))
        } catch {
            Issue.record("Unexpected codec capability error: \(error)")
        }

        do {
            try resolved.validatePhotoOutputCapabilities(CapturePhotoOutputCapabilitySnapshot(
                availablePhotoCodecTypes: [.hevc],
                isDepthDataDeliverySupported: false,
                isDepthDataDeliveryEnabled: false,
                maxPhotoQualityPrioritization: .quality
            ))
            Issue.record("Resolved output must reject missing depth capability.")
        } catch TAPDepthCaptureError.depthDeliveryUnsupported {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected depth capability error: \(error)")
        }

        do {
            try resolved.validatePhotoOutputCapabilities(
                CapturePhotoOutputCapabilitySnapshot(
                    availablePhotoCodecTypes: [.hevc],
                    isDepthDataDeliverySupported: true,
                    isDepthDataDeliveryEnabled: false,
                    maxPhotoQualityPrioritization: .balanced
                ),
                requireConfiguredState: true
            )
            Issue.record("Resolved output must reject an unconfigured depth state.")
        } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
            #expect(reason.contains("depth delivery state"))
        } catch {
            Issue.record("Unexpected depth state error: \(error)")
        }

        do {
            try resolved.validatePhotoOutputCapabilities(
                CapturePhotoOutputCapabilitySnapshot(
                    availablePhotoCodecTypes: [.hevc],
                    isDepthDataDeliverySupported: true,
                    isDepthDataDeliveryEnabled: true,
                    maxPhotoQualityPrioritization: .balanced
                ),
                requireConfiguredState: true
            )
            Issue.record("Resolved output must reject an unconfigured maximum quality state.")
        } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
            #expect(reason.contains("maximum quality"))
        } catch {
            Issue.record("Unexpected quality capability error: \(error)")
        }
    }

    @Test func outputResourcePlanNamesCurrentSignedHEICResources() throws {
        let resolved = try CaptureOutputProfile.releasePhotoDepthHEIC.resolvedPhotoOutput(
            availablePhotoCodecTypes: [.hevc]
        )
        let plan = try resolved.resourcePlan

        #expect(plan.container == .embeddedPhotoDepthHEIC)
        #expect(plan.resources.map(\.kind) == [
            .primaryPhoto,
            .appleAuxiliaryDepth,
            .tapManifest,
            .appAttestCaptureProof
        ])
        #expect(plan.requiresPrimaryPhoto)
        #expect(plan.requiresEmbeddedDepth)
        #expect(plan.requiresTAPManifest)
        #expect(plan.requiresAppAttestProofBeforeExport)
        #expect(plan.contentDigestResourceKinds == [
            .primaryPhoto,
            .appleAuxiliaryDepth,
            .tapManifest
        ])
        #expect(plan.resources.first { $0.kind == .appAttestCaptureProof }?.coveredByAppAttestContentDigest == false)
    }

    @Test func outputResourcePlanReusesResolvedPackagingValidation() throws {
        let resourcePlanSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureOutputResourcePlan.swift"
        )

        #expect(resourcePlanSource.contains("nonisolated var resourcePlan: CaptureOutputResourcePlan"))
        #expect(resourcePlanSource.contains("get throws"))
        #expect(resourcePlanSource.contains("try validateForEmbeddedPhotoDepthPackaging()"))
        #expect(resourcePlanSource.contains("case .embeddedPhotoDepthHEIC"))
    }

    @Test func outputResourcePlanStaysPurePolicyModel() throws {
        let resourcePlanSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureOutputResourcePlan.swift"
        )

        #expect(!resourcePlanSource.contains("import AVFoundation"))
        #expect(!resourcePlanSource.contains("import Photos"))
        #expect(!resourcePlanSource.contains("import UniformTypeIdentifiers"))
        #expect(!resourcePlanSource.contains("import AppAttestKit"))
        #expect(!resourcePlanSource.contains(": Data"))
        #expect(!resourcePlanSource.contains("Data("))
        #expect(!resourcePlanSource.contains(": URL"))
        #expect(!resourcePlanSource.contains("URL("))
        #expect(!resourcePlanSource.contains("AVCapture"))
        #expect(!resourcePlanSource.contains("PHAsset"))
        #expect(!resourcePlanSource.contains("TAPDepthManifest"))
        #expect(!resourcePlanSource.contains("keyID"))
        #expect(!resourcePlanSource.contains("captureID"))
        #expect(resourcePlanSource.contains("extension ResolvedCaptureOutputProfile"))
    }

    @Test func currentPhotosExportSurfaceStaysSingleValidatedHEICResource() throws {
        let photoLibrarySource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Output/PhotoLibraryWriter.swift")
        let createAssetSource = try #require(Self.substring(
            in: photoLibrarySource,
            from: "private static func createAsset",
            to: "private static func fetchAlbum"
        ))

        #expect(photoLibrarySource.contains("static func saveDepthHEIC(\n        _ validatedHEIC: ValidatedTAPDepthHEIC"))
        #expect(createAssetSource.components(separatedBy: "addResource(").count - 1 == 1)
        #expect(createAssetSource.contains("addResource(with: .photo"))
        #expect(!createAssetSource.contains(".pairedVideo"))
        #expect(!createAssetSource.contains(".alternatePhoto"))
        #expect(!createAssetSource.contains(".fullSizePhoto"))
    }

    @Test func resolvedOutputValidatesCapturePlanDepthContract() throws {
        let resolved = try CaptureOutputProfile.releasePhotoDepthHEIC.resolvedPhotoOutput(
            availablePhotoCodecTypes: [.hevc]
        )

        try resolved.validateForEmbeddedPhotoDepthPackaging()
        try resolved.validateCapturePlanDepthConfiguration(
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true
        )

        do {
            try resolved.validateCapturePlanDepthConfiguration(
                depthDataDeliveryEnabled: false,
                embedsDepthDataInPhoto: true
            )
            Issue.record("Resolved output must reject capture plans that disable required depth delivery.")
        } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
            #expect(reason.contains("depth delivery"))
        } catch {
            Issue.record("Unexpected resolved output validation error: \(error)")
        }

        do {
            try resolved.validateCapturePlanDepthConfiguration(
                depthDataDeliveryEnabled: true,
                embedsDepthDataInPhoto: false
            )
            Issue.record("Resolved output must reject capture plans that disable required depth embedding.")
        } catch TAPDepthCaptureError.invalidCaptureOutputProfile(let reason) {
            #expect(reason.contains("depth embedding"))
        } catch {
            Issue.record("Unexpected resolved output validation error: \(error)")
        }
    }

    @Test func outputProfileSelectionIntentResolvesReleaseDefaultProfile() throws {
        let resolution = CaptureOutputProfileSelectionIntent.releaseDefault.resolved()

        #expect(resolution.isExecutable)
        #expect(resolution.requestedProfileID == "release.photo-depth.heic")
        #expect(resolution.selectedProfile?.id == CaptureOutputProfile.releasePhotoDepthHEIC.id)
        #expect(resolution.violations.isEmpty)
    }

    @Test func outputProfileSelectionIntentResolvesExplicitProfileID() throws {
        let intent = CaptureOutputProfileSelectionIntent(request: .profile(id: " release.photo-depth.heic "))
        let resolution = intent.resolved()

        #expect(resolution.isExecutable)
        #expect(resolution.requestedProfileID == "release.photo-depth.heic")
        #expect(resolution.selectedProfile?.id == CaptureOutputProfile.releasePhotoDepthHEIC.id)
    }

    @Test func outputProfileSelectionPresentationNamesValidSelectionWithoutRawProfileID() throws {
        let resolution = CaptureOutputProfileSelectionIntent(request: .profile(id: " release.photo-depth.heic "))
            .resolved()
        let presentation = CaptureOutputProfileSelectionPresentation(resolution: resolution)
        let publicText = [
            presentation.title,
            presentation.detail,
            presentation.requestedProfileLabel,
            presentation.selectedProfileLabel ?? ""
        ].joined(separator: " ")

        #expect(presentation.status == .ready)
        #expect(presentation.requestedProfileLabel == "Explicit output profile")
        #expect(presentation.selectedProfileLabel == "Photo-depth HEIC")
        #expect(!publicText.contains("release.photo-depth.heic"))
    }

    @Test func outputProfileSelectionIntentRejectsEmptyProfileIDWithoutFallback() throws {
        let intent = CaptureOutputProfileSelectionIntent(request: .profile(id: "   "))
        let resolution = intent.resolved()

        #expect(!resolution.isExecutable)
        #expect(resolution.selectedProfile == nil)
        #expect(resolution.violations == [.emptyRequestedProfileID])
    }

    @Test func outputProfileSelectionIntentRejectsMissingProfile() throws {
        let intent = CaptureOutputProfileSelectionIntent(request: .profile(id: "future.raw"))
        let resolution = intent.resolved()

        #expect(!resolution.isExecutable)
        #expect(resolution.selectedProfile == nil)
        #expect(resolution.violations == [.requestedProfileMissing("future.raw")])
        #expect(resolution.violations.first?.readerDescription.contains("future.raw") == true)
    }

    @Test func outputProfileSelectionPresentationRedactsMissingProfileID() throws {
        let requestedID = "future.raw file:///private/profile https://example.invalid proof keyID"
        let resolution = CaptureOutputProfileSelectionIntent(request: .profile(id: requestedID))
            .resolved()
        let readerDescription = try #require(resolution.violations.first?.readerDescription)
        let presentation = CaptureOutputProfileSelectionPresentation(resolution: resolution)
        let publicText = ([presentation.title, presentation.detail, presentation.requestedProfileLabel]
            + presentation.issueLabels)
            .joined(separator: " ")

        #expect(readerDescription.contains(requestedID))
        #expect(presentation.status == .blocked)
        #expect(presentation.selectedProfileLabel == nil)
        #expect(presentation.issueLabels == ["Requested output profile is not in the reviewed catalog."])
        for forbidden in ["future.raw", "file://", "/private/", "https://", "proof", "keyID"] {
            #expect(!publicText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func outputProfileSelectionIntentFailsClosedForInvalidCatalog() throws {
        let invalidProfile = CaptureOutputProfile(
            id: "bad.jpeg-fallback",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc, .jpeg],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: .releaseQuality
        )
        let catalog = CaptureOutputProfileCatalog(
            defaultProfileID: invalidProfile.id,
            profiles: [invalidProfile]
        )
        let resolution = CaptureOutputProfileSelectionIntent.releaseDefault.resolved(in: catalog)

        #expect(!resolution.isExecutable)
        #expect(resolution.selectedProfile == nil)
        #expect(resolution.violations.contains(.catalogViolation(.invalidProfile(
            id: invalidProfile.id,
            violations: [.heicContainerAllowsNonHEVCCodec]
        ))))
        #expect(resolution.violations.contains(.requestedProfileInvalid(
            id: invalidProfile.id,
            violations: [.heicContainerAllowsNonHEVCCodec]
        )))
    }

    @Test func outputProfileSelectionPresentationRedactsCatalogProfileIDs() throws {
        let hostileProfile = CaptureOutputProfile(
            id: "secret.profile file:///private/catalog https://example.invalid proof keyID",
            container: .embeddedPhotoDepthHEIC,
            codecPreference: [.hevc],
            depthDataDeliveryEnabled: true,
            embedsDepthDataInPhoto: true,
            depthDataFiltered: true,
            requiresDepthData: true,
            photoQualityPolicy: .releaseQuality
        )
        let catalog = CaptureOutputProfileCatalog(
            defaultProfileID: hostileProfile.id,
            profiles: [hostileProfile, hostileProfile]
        )
        let resolution = CaptureOutputProfileSelectionIntent.releaseDefault.resolved(in: catalog)
        let readerText = resolution.violations.map(\.readerDescription).joined(separator: " ")
        let presentation = CaptureOutputProfileSelectionPresentation(resolution: resolution)
        let publicText = ([presentation.title, presentation.detail, presentation.requestedProfileLabel]
            + presentation.issueLabels)
            .joined(separator: " ")

        #expect(readerText.contains(hostileProfile.id))
        #expect(presentation.status == .blocked)
        #expect(presentation.issueLabels == ["Reviewed output catalog is not valid."])
        for forbidden in ["secret.profile", "file://", "/private/", "https://", "proof", "keyID"] {
            #expect(!publicText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func photoSettingsFactoryUsesReleaseOutputProfileDefaults() throws {
        let photoOutput = AVCapturePhotoOutput()
        let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput(photoOutput: photoOutput)
        let settings = SingleCamPhotoSettingsFactory.make(
            photoOutput: photoOutput,
            resolvedOutput: resolvedOutput
        )

        #expect(resolvedOutput.profileID == CaptureOutputProfileCatalog.releaseDefaultProfile.id)
        #expect(resolvedOutput.codec == .hevc)
        #expect(settings.isDepthDataDeliveryEnabled)
        #expect(settings.embedsDepthDataInPhoto)
        #expect(settings.isDepthDataFiltered)
        #expect(settings.photoQualityPrioritization == .quality)
    }

    @Test func runtimeResolvesAndReusesOutputThroughCapabilitySnapshot() throws {
        let sessionControllerSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let providerSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift"
        )
        let profileResolutionSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Output/CaptureOutputProfileResolution.swift"
        )

        #expect(profileResolutionSource.contains("struct CapturePhotoOutputCapabilitySnapshot"))
        #expect(profileResolutionSource.contains("init(photoOutput: AVCapturePhotoOutput)"))
        #expect(profileResolutionSource.contains("func validatePhotoOutputCapabilities"))
        #expect(providerSource.contains("availablePhotoCodecTypes: photoOutput.availablePhotoCodecTypes"))
        #expect(providerSource.contains("switch resolvedOutput.codec"))
        #expect(providerSource.contains("case .hevc:"))
        #expect(providerSource.contains("case .jpeg:"))
        #expect(!providerSource.contains("else {\n            settings = AVCapturePhotoSettings()"))
        #expect(sessionControllerSource.contains("validatePhotoOutputCapabilities"))
        #expect(sessionControllerSource.components(separatedBy: "requireConfiguredState: true").count - 1 == 2)
        #expect(!sessionControllerSource.contains("resolvedOutput.depthDataDeliveryEnabled && !photoOutput.isDepthDataDeliverySupported"))
    }

    @Test func runtimePackageAndManifestUseResolvedOutputAsExecutionToken() throws {
        let sessionControllerSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/CaptureSessionController.swift"
        )
        let providerSource = try Self.source(
            relativePath: "TAPCamDemo/CameraCapture/Runtime/AVFoundationSingleCamPhotoProvider.swift"
        )
        let captureMethod = try #require(Self.substring(
            in: providerSource,
            from: "func capturePhotoDepth",
            to: "@MainActor"
        ))
        let packageSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Output/CapturePackage.swift")
        let packagerSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Output/EmbeddedPhotoPackager.swift")
        let manifestSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Output/TAPDepthManifestBuilder.swift")
        let resultModelSource = try Self.source(relativePath: "TAPCamDemo/CameraCapture/Planning/CapturePlan.swift")

        #expect(resultModelSource.contains("let resolvedOutput: ResolvedCaptureOutputProfile"))
        #expect(sessionControllerSource.contains("let resolvedOutput = try SingleCamPhotoSettingsFactory.resolvedOutput"))
        #expect(sessionControllerSource.contains("Self.prewarmPhotoOutput(photoOutput, resolvedOutput: result.resolvedOutput)"))
        #expect(captureMethod.contains("let resolvedOutput = context.sessionConfiguration.resolvedOutput"))
        #expect(!captureMethod.contains("SingleCamPhotoSettingsFactory.resolvedOutput"))
        #expect(!captureMethod.contains("context.sessionConfiguration.outputProfile"))
        #expect(packageSource.contains("let resolvedOutput = context.sessionConfiguration.resolvedOutput"))
        #expect(!packageSource.contains("let outputProfile: CaptureOutputProfile"))
        #expect(!packageSource.contains("context.sessionConfiguration.outputProfile"))
        #expect(!packageSource.contains("captureResult.requestedCodec"))
        #expect(!packageSource.contains("validateResolvedCodec"))
        #expect(!packageSource.contains("let requestedCodec: AVVideoCodecType"))
        #expect(packagerSource.contains("capturePackage.resolvedOutput.validateForEmbeddedPhotoDepthPackaging()"))
        #expect(!packagerSource.contains("capturePackage.outputProfile.validate"))
        #expect(manifestSource.contains("let resolvedOutput = capturePackage.resolvedOutput"))
        #expect(!manifestSource.contains("let outputProfile = capturePackage.outputProfile"))
    }

    private static func source(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func substring(in source: String, from start: String, to end: String) -> String? {
        guard let startRange = source.range(of: start),
              let endRange = source[startRange.lowerBound...].range(of: end) else {
            return nil
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
