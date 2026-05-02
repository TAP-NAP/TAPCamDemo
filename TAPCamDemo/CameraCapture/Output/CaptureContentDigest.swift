//
//  CaptureContentDigest.swift
//  TAPCamDemo
//

@preconcurrency import AVFoundation
import AppAttestKit
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO

/// Canonical digest package bound into the App Attest assertion for one capture.
nonisolated struct CaptureContentDigest: Codable, Equatable, Sendable {
    static let schemaIdentifier = "urn:tapnap:tapcam:capture-content-digest:v1"

    let schemaID: String
    let manifestSchemaID: String
    let captureID: String
    let capturedAt: String
    let rgb: Component
    let depth: Component
    let metadata: Component

    nonisolated init(
        schemaID: String = CaptureContentDigest.schemaIdentifier,
        manifestSchemaID: String = TAPDepthManifest.schemaIdentifier,
        captureID: String,
        capturedAt: String,
        rgb: Component,
        depth: Component,
        metadata: Component
    ) {
        self.schemaID = schemaID
        self.manifestSchemaID = manifestSchemaID
        self.captureID = captureID
        self.capturedAt = capturedAt
        self.rgb = rgb
        self.depth = depth
        self.metadata = metadata
    }

    static func make(
        manifest: TAPDepthManifest,
        baseHEICData: Data,
        depthData: AVDepthData,
        capturedAt: Date
    ) throws -> CaptureContentDigest {
        CaptureContentDigest(
            captureID: manifest.payload.id,
            capturedAt: TAPDateFormatting.iso8601.string(from: capturedAt),
            rgb: try rgbComponent(from: baseHEICData),
            depth: try depthComponent(from: depthData),
            metadata: try metadataComponent(from: manifest.payload)
        )
    }

    func canonicalJSONData() throws -> Data {
        try JSONEncoder.tapCaptureCanonical.encode(self)
    }

    nonisolated struct Component: Codable, Equatable, Sendable {
        let mediaType: String
        let width: Int?
        let height: Int?
        let algorithm: String
        let value: String

        nonisolated init(
            mediaType: String,
            width: Int?,
            height: Int?,
            algorithm: String = "SHA-256",
            value: String
        ) {
            self.mediaType = mediaType
            self.width = width
            self.height = height
            self.algorithm = algorithm
            self.value = value
        }
    }

    private static func rgbComponent(from heicData: Data) throws -> Component {
        guard let source = CGImageSourceCreateWithData(heicData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TAPDepthCaptureError.imageSourceCreationFailed
        }

        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw TAPDepthCaptureError.imageDestinationCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return Component(
            mediaType: "image/heic-primary-rgba8",
            width: width,
            height: height,
            value: sha256Base64URL(Data(pixels))
        )
    }

    private static func depthComponent(from depthData: AVDepthData) throws -> Component {
        let metricDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let pixelBuffer = metricDepthData.depthDataMap
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TAPDepthCaptureError.missingDepthData
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var canonicalDepth = Data()
        canonicalDepth.reserveCapacity(width * height * MemoryLayout<UInt32>.size)

        for y in 0..<height {
            let row = baseAddress
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)

            for x in 0..<width {
                var bitPattern = row[x].bitPattern.littleEndian
                withUnsafeBytes(of: &bitPattern) { bytes in
                    canonicalDepth.append(contentsOf: bytes)
                }
            }
        }

        return Component(
            mediaType: "application/vnd.tapnap.depth-float32",
            width: width,
            height: height,
            value: sha256Base64URL(canonicalDepth)
        )
    }

    private static func metadataComponent(from payload: TAPDepthManifest.Payload) throws -> Component {
        let payloadData = try TAPDepthManifestEncoder.payloadDataExcludingProofs(payload)
        return Component(
            mediaType: "application/vnd.tapnap.depth-manifest.payload+json;version=1",
            width: nil,
            height: nil,
            value: sha256Base64URL(payloadData)
        )
    }

    private static func sha256Base64URL(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).appAttestBase64URL
    }
}

nonisolated extension JSONEncoder {
    static var tapCaptureCanonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
