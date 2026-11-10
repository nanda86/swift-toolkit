//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import func AVFoundation.AVMakeRect
import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit

extension UIImage {
    /// Creates a `UIImage` by rendering an SVG document from the given data,
    /// scaled down to fit `maxSize` pixels with `scale = 1` while preserving
    /// the aspect ratio.
    ///
    /// If the SVG canvas is smaller than `maxSize`, it is rendered at its
    /// native size to avoid upscaling embedded bitmaps.
    ///
    /// Returns `nil` if the data is not a valid SVG or if SVG rendering is
    /// unavailable on the current platform.
    static func fromSVG(_ data: Data, maxSize: CGSize) -> UIImage? {
        guard
            let createFromData = CoreSVG.createFromData,
            let getCanvasSize = CoreSVG.getCanvasSize,
            let drawInContext = CoreSVG.drawInContext,
            let releaseDocument = CoreSVG.releaseDocument,
            let document = createFromData(data as CFData, nil)
        else {
            return nil
        }
        let svgDocument = document.takeUnretainedValue()
        defer { releaseDocument(svgDocument) }

        let canvasSize = getCanvasSize(svgDocument)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        // Render at the smaller of the canvas size and the requested max
        // size, preserving the SVG aspect ratio.
        let renderSize: CGSize
        if canvasSize.width <= maxSize.width, canvasSize.height <= maxSize.height {
            renderSize = canvasSize
        } else {
            let targetRect = AVMakeRect(
                aspectRatio: canvasSize,
                insideRect: CGRect(origin: .zero, size: maxSize)
            )
            renderSize = targetRect.size
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { ctx in
            let cgContext = ctx.cgContext
            let scaleX = renderSize.width / canvasSize.width
            let scaleY = renderSize.height / canvasSize.height
            cgContext.translateBy(x: 0, y: renderSize.height)
            cgContext.scaleBy(x: scaleX, y: -scaleY)
            drawInContext(cgContext, svgDocument)
        }
    }

    /// Returns the image scaled down to fit within `maxSize` pixels, preserving
    /// the aspect ratio without upscaling.
    ///
    /// The returned image always has `scale = 1`.
    func scaleToFit(maxSize: CGSize) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderSize: CGSize
        if pixelSize.width <= maxSize.width, pixelSize.height <= maxSize.height {
            if scale == 1 { return self }
            renderSize = pixelSize
        } else {
            renderSize = AVMakeRect(aspectRatio: pixelSize, insideRect: CGRect(origin: .zero, size: maxSize)).size
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: renderSize))
        }
    }
}

#elseif canImport(AppKit)
    import AppKit

extension NSImage {
    /// Creates an `NSImage` by rendering an SVG document from the given data,
    /// scaled down to fit `maxSize` pixels while preserving the aspect ratio.
    static func fromSVG(_ data: Data, maxSize: CGSize) -> NSImage? {
        guard
            let createFromData = CoreSVG.createFromData,
            let getCanvasSize = CoreSVG.getCanvasSize,
            let drawInContext = CoreSVG.drawInContext,
            let releaseDocument = CoreSVG.releaseDocument,
            let document = createFromData(data as CFData, nil)
        else {
            return nil
        }
        let svgDocument = document.takeUnretainedValue()
        defer { releaseDocument(svgDocument) }

        let canvasSize = getCanvasSize(svgDocument)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }
        let renderSize = fittedSize(canvasSize, in: maxSize)
        guard let context = bitmapContext(size: renderSize) else {
            return nil
        }
        // A bitmap context already has a bottom-left origin, as the SVG renderer expects.
        context.scaleBy(x: renderSize.width / canvasSize.width, y: renderSize.height / canvasSize.height)
        drawInContext(context, svgDocument)
        return context.makeImage().map(NSImage.readium(cgImage:))
    }

    /// Returns the image scaled down to fit within `maxSize` pixels, preserving
    /// the aspect ratio without upscaling.
    func scaleToFit(maxSize: CGSize) -> NSImage {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let renderSize = Self.fittedSize(pixelSize, in: maxSize)
        if renderSize == pixelSize {
            return .readium(cgImage: cgImage)
        }
        guard let context = Self.bitmapContext(size: renderSize) else {
            return self
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: renderSize))
        return context.makeImage().map(NSImage.readium(cgImage:)) ?? self
    }

    private static func fittedSize(_ size: CGSize, in maxSize: CGSize) -> CGSize {
        if size.width <= maxSize.width, size.height <= maxSize.height {
            return size
        }
        return AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: .zero, size: maxSize)).size
    }

    private static func bitmapContext(size: CGSize) -> CGContext? {
        CGContext(
            data: nil,
            width: max(1, Int(size.width.rounded())),
            height: max(1, Int(size.height.rounded())),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
#endif

private enum CoreSVG {
    typealias CreateFromData = @convention(c) (CFData, CFDictionary?) -> Unmanaged<CFTypeRef>?
    typealias GetCanvasSize = @convention(c) (CFTypeRef) -> CGSize
    typealias DrawInContext = @convention(c) (CGContext, CFTypeRef) -> Void
    typealias ReleaseDocument = @convention(c) (CFTypeRef) -> Void

    static let createFromData: CreateFromData? = load("CGSVGDocumentCreateFromData")
    static let getCanvasSize: GetCanvasSize? = load("CGSVGDocumentGetCanvasSize")
    static let drawInContext: DrawInContext? = load("CGContextDrawSVGDocument")
    static let releaseDocument: ReleaseDocument? = load("CGSVGDocumentRelease")

    private static func load<T>(_ name: String) -> T? {
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
