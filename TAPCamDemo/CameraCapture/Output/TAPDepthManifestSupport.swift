//
//  TAPDepthManifestSupport.swift
//  TAPCamDemo
//
//  Created by Codex on 2026/4/25.
//

@preconcurrency import AVFoundation
import CoreLocation
import CoreVideo
import Foundation
import ImageIO
import simd

nonisolated enum TAPDepthSourceClassifier {
    static func source(forDeviceType deviceType: String, localizedName: String) -> TAPDepthManifest.DepthSource {
        let classification = classification(forDeviceType: deviceType)
        return TAPDepthManifest.DepthSource(
            captureDeviceType: deviceType,
            captureDeviceName: localizedName,
            sensingMethod: classification.sensingMethod,
            lidarParticipation: classification.lidarParticipation
        )
    }

    static func classification(forDeviceType deviceType: String) -> (sensingMethod: String, lidarParticipation: String) {
        switch deviceType {
        case AVCaptureDevice.DeviceType.builtInLiDARDepthCamera.rawValue:
            ("lidarDepthCamera", "explicit")
        case AVCaptureDevice.DeviceType.builtInTrueDepthCamera.rawValue:
            ("trueDepthCamera", "notApplicable")
        case AVCaptureDevice.DeviceType.builtInTripleCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInDualWideCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInDualCamera.rawValue:
            ("multiCameraStereoOrComputational", "notAsserted")
        case AVCaptureDevice.DeviceType.builtInWideAngleCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInUltraWideCamera.rawValue,
             AVCaptureDevice.DeviceType.builtInTelephotoCamera.rawValue:
            ("singleCameraComputationalOrUnknown", "notAsserted")
        default:
            ("singleCameraComputationalOrUnknown", "notAsserted")
        }
    }
}

nonisolated enum TAPDepthAuxiliaryKind: String {
    case depth
    case disparity

    init(kind: OSType) {
        switch kind {
        case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32:
            self = .depth
        case kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32:
            self = .disparity
        default:
            self = .depth
        }
    }
}

nonisolated enum TAPFourCharCode {
    static func string(from code: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]

        if bytes.allSatisfy({ (32...126).contains($0) }),
           let text = String(bytes: bytes, encoding: .ascii) {
            return text
        }

        return String(format: "0x%08X", code)
    }
}

nonisolated enum TAPDateFormatting {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

extension TAPDepthManifest.Software {
    nonisolated static var current: TAPDepthManifest.Software {
        let bundle = Bundle.main
        return TAPDepthManifest.Software(
            appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TAPCamDemo",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }
}

extension AVCaptureDevice.Format {
    nonisolated var tapCameraFormat: TAPDepthManifest.CameraFormat {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return TAPDepthManifest.CameraFormat(
            mediaSubType: TAPFourCharCode.string(from: CMFormatDescriptionGetMediaSubType(formatDescription)),
            width: dimensions.width,
            height: dimensions.height,
            maxFrameRate: videoSupportedFrameRateRanges.map(\.maxFrameRate).max()
        )
    }
}

extension AVCaptureDevice {
    /// iOS 26 exposes a convenient 35mm-equivalent focal length directly on the
    /// capture device. The app's baseline is iOS 18, so the manifest treats this
    /// as an enhancement: present on iOS 26+, `null` on older systems. Generic
    /// EXIF focal length values from `AVCapturePhoto.metadata` are still preserved
    /// by `TAPPhotoFileMetadataCustomizer`.
    nonisolated var tapNominalFocalLengthIn35mmFilm: Float? {
        guard #available(iOS 26.0, *) else {
            return nil
        }

        return nominalFocalLengthIn35mmFilm > 0 ? nominalFocalLengthIn35mmFilm : nil
    }
}

extension AVCaptureDevice.Position {
    nonisolated var tapDescription: String {
        switch self {
        case .front:
            "front"
        case .back:
            "back"
        case .unspecified:
            "unspecified"
        @unknown default:
            "unknown"
        }
    }
}

extension AVCapturePhotoOutput.QualityPrioritization {
    nonisolated var tapDescription: String {
        switch self {
        case .speed:
            "speed"
        case .balanced:
            "balanced"
        case .quality:
            "quality"
        @unknown default:
            "unknown"
        }
    }
}

extension AVDepthData.Accuracy {
    nonisolated var tapDescription: String {
        switch self {
        case .relative:
            "relative"
        case .absolute:
            "absolute"
        @unknown default:
            "unknown"
        }
    }
}

extension AVDepthData.Quality {
    nonisolated var tapDescription: String {
        switch self {
        case .low:
            "low"
        case .high:
            "high"
        @unknown default:
            "unknown"
        }
    }
}
