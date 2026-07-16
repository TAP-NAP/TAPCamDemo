//
//  TAPVideoDepthOverlay.swift
//  TAPCamDemo
//

import CoreImage
import ImageIO
import MetalKit
import UIKit

@MainActor
struct TAPVideoRegisteredDepthOverlay {
    let image: UIImage
    let registrationDescriptor: TAPVideoDepthRegistrationDescriptor
}

@MainActor
protocol TAPVideoDepthOverlaySink: AnyObject {
    func setRegisteredDepthOverlay(_ overlay: TAPVideoRegisteredDepthOverlay?)
}

@MainActor
final class TAPVideoDepthOverlayStore {
    private weak var sink: (any TAPVideoDepthOverlaySink)?
    private(set) var overlay: TAPVideoRegisteredDepthOverlay?

    func attach(_ sink: any TAPVideoDepthOverlaySink) {
        self.sink = sink
        sink.setRegisteredDepthOverlay(overlay)
    }

    func detach(_ sink: any TAPVideoDepthOverlaySink) {
        guard self.sink === sink else {
            return
        }
        self.sink = nil
    }

    func present(
        _ image: UIImage,
        registrationDescriptor: TAPVideoDepthRegistrationDescriptor
    ) {
        let overlay = TAPVideoRegisteredDepthOverlay(
            image: image,
            registrationDescriptor: registrationDescriptor
        )
        self.overlay = overlay
        sink?.setRegisteredDepthOverlay(overlay)
    }

    func clear() {
        overlay = nil
        sink?.setRegisteredDepthOverlay(nil)
    }
}

private extension TAPVideoDepthRegistrationDescriptor {
    func registeredCIImage(from image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let source = CIImage(cgImage: cgImage)
        switch mapping {
        case .preRegisteredRGBPresentation:
            return source.oriented(
                forExifOrientation: image.imageOrientation.exifOrientation
            )
        case .avDepthDataWarpedToSynchronizedRGB:
            guard let projection,
                  cgImage.width == projection.depthWidth,
                  cgImage.height == projection.depthHeight,
                  let encodedImage = encodedCIImage(
                      source,
                      projection: projection
                  ),
                  let cropRect = cleanApertureCropRect(
                      in: encodedImage.extent,
                      projection: projection
                  ) else {
                return nil
            }
            return encodedImage
                .cropped(to: cropRect)
                .transformed(by: CGAffineTransform(
                    translationX: -cropRect.minX,
                    y: -cropRect.minY
                ))
        }
    }

    private func encodedCIImage(
        _ source: CIImage,
        projection: TAPVideoRegistrationProjection
    ) -> CIImage? {
        guard let orientation = Self.connectionOrientation(
            degrees: projection.connectionRotationDegrees
        ) else {
            return nil
        }
        let oriented = source.oriented(
            forExifOrientation: Int32(orientation.rawValue)
        )
        guard projection.isEncodedHorizontallyMirrored else {
            return oriented
        }
        return oriented.transformed(by: CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: oriented.extent.minX + oriented.extent.maxX,
            ty: 0
        ))
    }

    private static func connectionOrientation(
        degrees: Int
    ) -> CGImagePropertyOrientation? {
        switch degrees {
        case 0:
            return .up
        case 90:
            return .right
        case 180:
            return .down
        case 270:
            return .left
        default:
            return nil
        }
    }

    private func cleanApertureCropRect(
        in extent: CGRect,
        projection: TAPVideoRegistrationProjection
    ) -> CGRect? {
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }
        let aperture = projection.rgbCleanAperture
        let cropRect = CGRect(
            x: extent.minX
                + aperture.x / Double(projection.encodedRGBWidth) * extent.width,
            y: extent.minY
                + (1 - (aperture.y + aperture.height)
                    / Double(projection.encodedRGBHeight)) * extent.height,
            width: aperture.width
                / Double(projection.encodedRGBWidth) * extent.width,
            height: aperture.height
                / Double(projection.encodedRGBHeight) * extent.height
        ).intersection(extent)
        guard !cropRect.isNull,
              cropRect.width > 0,
              cropRect.height > 0 else {
            return nil
        }
        return cropRect
    }
}

@MainActor
private final class TAPVideoDepthMetalOverlayView: MTKView, MTKViewDelegate {
    private let imageContext: CIContext
    private let commandQueue: any MTLCommandQueue
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
    private var image: CIImage?

    static func makeIfSupported() -> TAPVideoDepthMetalOverlayView? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        return TAPVideoDepthMetalOverlayView(
            device: device,
            commandQueue: commandQueue
        )
    }

    private init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue
    ) {
        imageContext = CIContext(mtlDevice: device)
        self.commandQueue = commandQueue
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        backgroundColor = .clear
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        image = overlay.flatMap {
            $0.registrationDescriptor.registeredCIImage(from: $0.image)
        }
        setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let image,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        let targetBounds = CGRect(origin: .zero, size: drawableSize)
        guard targetBounds.width > 0,
              targetBounds.height > 0,
              image.extent.width > 0,
              image.extent.height > 0 else {
            return
        }
        let normalizedImage = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
        let presentationImage = normalizedImage.transformed(
            by: CGAffineTransform(
                scaleX: targetBounds.width / normalizedImage.extent.width,
                y: targetBounds.height / normalizedImage.extent.height
            )
        )
        imageContext.render(
            presentationImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetBounds,
            colorSpace: outputColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = view
        _ = size
    }
}

private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up:
            Int32(CGImagePropertyOrientation.up.rawValue)
        case .upMirrored:
            Int32(CGImagePropertyOrientation.upMirrored.rawValue)
        case .down:
            Int32(CGImagePropertyOrientation.down.rawValue)
        case .downMirrored:
            Int32(CGImagePropertyOrientation.downMirrored.rawValue)
        case .left:
            Int32(CGImagePropertyOrientation.left.rawValue)
        case .leftMirrored:
            Int32(CGImagePropertyOrientation.leftMirrored.rawValue)
        case .right:
            Int32(CGImagePropertyOrientation.right.rawValue)
        case .rightMirrored:
            Int32(CGImagePropertyOrientation.rightMirrored.rawValue)
        @unknown default:
            Int32(CGImagePropertyOrientation.up.rawValue)
        }
    }
}

@MainActor
final class TAPVideoDepthOverlaySurfaceView: UIView {
    private let metalView: TAPVideoDepthMetalOverlayView?
    private let fallbackImageView: UIImageView?
    private let fallbackImageContext = CIContext(
        options: [.cacheIntermediates: false]
    )
    private(set) var hasImage = false

    override init(frame: CGRect) {
        let metalView = TAPVideoDepthMetalOverlayView.makeIfSupported()
        self.metalView = metalView
        if metalView == nil {
            let imageView = UIImageView()
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            fallbackImageView = imageView
        } else {
            fallbackImageView = nil
        }
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        if let metalView {
            addSubview(metalView)
        } else if let fallbackImageView {
            addSubview(fallbackImageView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds
        fallbackImageView?.frame = bounds
        if hasImage {
            metalView?.setNeedsDisplay()
        }
    }

    func present(_ overlay: TAPVideoRegisteredDepthOverlay?) {
        metalView?.present(overlay)
        if let fallbackImageView {
            let registeredImage = overlay.flatMap {
                $0.registrationDescriptor.registeredCIImage(from: $0.image)
            }
            if let registeredImage,
               let cgImage = fallbackImageContext.createCGImage(
                registeredImage,
                from: registeredImage.extent
               ) {
                fallbackImageView.image = UIImage(cgImage: cgImage)
                hasImage = true
            } else {
                fallbackImageView.image = nil
                hasImage = false
            }
        } else {
            hasImage = overlay != nil
        }
    }
}
