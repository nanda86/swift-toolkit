//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// A `CoverService` which holds a lazily generated cover bitmap in memory.
public final class GeneratedCoverService: CoverService {
    enum Error: Swift.Error {
        case generationFailed
    }

    private var _cover: ReadResult<ReadiumImage>?
    private let makeCover: () async -> ReadResult<ReadiumImage>

    public init(makeCover: @escaping () async -> ReadResult<ReadiumImage>) {
        self.makeCover = makeCover
    }

    public convenience init(cover: ReadiumImage) {
        self.init(makeCover: { .success(cover) })
    }

    private let coverLink = Link(
        href: "~readium/cover",
        mediaType: .png,
        rel: .cover
    )

    private func cachedCover() async -> ReadResult<ReadiumImage> {
        if _cover == nil {
            _cover = await makeCover()
        }
        return _cover!
    }

    public func cover() async -> ReadResult<ReadiumImage?> {
        await cachedCover().map { $0 as ReadiumImage? }
    }

    public var links: [Link] {
        [coverLink]
    }

    public func get<T: URLConvertible>(_ href: T) -> (any Resource)? {
        guard href.anyURL.isEquivalentTo(coverLink.url()) else {
            return nil
        }

        return CoverResource(cover: cachedCover)
    }

    public static func makeFactory(makeCover: @escaping () async -> ReadResult<ReadiumImage>) -> (PublicationServiceContext) -> GeneratedCoverService? {
        { _ in GeneratedCoverService(makeCover: makeCover) }
    }

    public static func makeFactory(cover: ReadiumImage) -> (PublicationServiceContext) -> GeneratedCoverService? {
        { _ in GeneratedCoverService(cover: cover) }
    }

    private class CoverResource: Resource {
        private let cover: () async -> ReadResult<ReadiumImage>

        init(cover: @escaping () async -> ReadResult<ReadiumImage>) {
            self.cover = cover
        }

        let sourceURL: AbsoluteURL? = nil

        func estimatedLength() async -> ReadResult<UInt64?> {
            .success(nil)
        }

        func properties() async -> ReadResult<ResourceProperties> {
            .success(ResourceProperties())
        }

        func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
            await cover().flatMap {
                guard let data = $0.pngData() else {
                    return .failure(.decoding("Failed to convert the cover bitmap to PNG data"))
                }
                consume(data)
                return .success(())
            }
        }
    }
}
