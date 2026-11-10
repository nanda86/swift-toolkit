//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit

    /// The platform image type used by Readium APIs: `UIImage` on iOS.
    public typealias ReadiumImage = UIImage

    extension UIImage {
        /// Creates an image from a Core Graphics image at scale 1.
        static func readium(cgImage: CGImage) -> UIImage {
            UIImage(cgImage: cgImage)
        }
    }

#elseif canImport(AppKit)
    import AppKit

    /// The platform image type used by Readium APIs: `NSImage` on macOS.
    public typealias ReadiumImage = NSImage

    extension NSImage {
        /// Creates an image from a Core Graphics image, sized in pixels.
        static func readium(cgImage: CGImage) -> NSImage {
            NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        }

        /// PNG representation, matching `UIImage.pngData()` on iOS.
        func pngData() -> Data? {
            guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }
    }
#endif
