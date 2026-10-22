import ReadiumShared
@testable import ReadiumNavigator
import UIKit
import XCTest

@MainActor
final class PaginationSnapshotIsolationTests: XCTestCase {
    func testOutgoingSnapshotDoesNotExposeTheLivePageWhileDestinationLoads() async throws {
        for progression: ReadiumNavigator.ReadingProgression in [.ltr, .rtl] {
            for initialIndex in [0, 1] {
                try await verifySnapshot(initialIndex: initialIndex, progression: progression)
            }
        }
    }

    private func verifySnapshot(initialIndex: Int, progression: ReadiumNavigator.ReadingProgression) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let host = UIViewController()
        window.rootViewController = host
        host.view.backgroundColor = initialIndex == 0 ? .white : .black
        let pages = Pages(outgoingIndex: initialIndex)
        let pagination = PaginationView(frame: window.bounds, preloadPreviousPositionCount: 1,
            preloadNextPositionCount: 1, isScrollEnabled: false)
        pagination.animatesChapterTransitionsVertically = true
        pagination.delegate = pages
        host.view.addSubview(pagination)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        pagination.reloadAtIndex(initialIndex, location: .start, pageCount: 2, readingProgression: progression)
        try await Task.sleep(nanoseconds: 100_000_000)
        pagination.layoutIfNeeded()
        let outgoing = try XCTUnwrap(pages.outgoing)
        pages.blocksDestination = true
        let transition = Task {
            await pagination.goToIndex(1 - initialIndex, location: initialIndex == 0 ? .start : .end, options: .animated)
        }
        for _ in 0..<100 where pages.resumeDestination == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let resume = pages.resumeDestination else {
            XCTFail("Destination must pause with the outgoing snapshot on screen")
            return
        }
        // Native rubber-banding can settle the live WebView while the frozen
        // outgoing image waits for the previous chapter. Its second text
        // position must never show through the snapshot's transparent gaps.
        outgoing.marker.frame.origin.y = 180
        try await Task.sleep(nanoseconds: 50_000_000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "chapter-snapshot-live-page-isolation"
        attachment.lifetime = .keepAlways
        add(attachment)
        let pixel = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 25, y: 185, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        resume.resume()
        _ = await transition.value
        let channel: UInt8 = initialIndex == 0 ? 255 : 0
        XCTAssertEqual(rgba, [channel, channel, channel, 255], "The frozen chapter must cover the second live-page marker")
    }

    private final class Page: UIView, PageView {
        let marker = UIView(frame: CGRect(x: 20, y: 100, width: 30, height: 20))
        var waitForLoad: (() async -> Void)?
        init() {
            super.init(frame: .zero)
            marker.backgroundColor = .red
            addSubview(marker)
        }
        required init?(coder: NSCoder) { fatalError() }
        func go(to location: PageLocation, animated: Bool) async { await waitForLoad?() }
    }

    private final class Pages: PaginationViewDelegate {
        let outgoingIndex: Int
        var outgoing: Page?
        var blocksDestination = false
        var resumeDestination: CheckedContinuation<Void, Never>?
        init(outgoingIndex: Int) { self.outgoingIndex = outgoingIndex }
        func paginationView(_ paginationView: PaginationView, pageViewAtIndex index: Int) -> (UIView & PageView)? {
            MainActor.assumeIsolated {
                let page = Page()
                if index == outgoingIndex { outgoing = page }
                else {
                    page.waitForLoad = {
                        guard self.blocksDestination else { return }
                        await withCheckedContinuation { self.resumeDestination = $0 }
                    }
                }
                return page
            }
        }
        func paginationViewDidUpdateViews(_ paginationView: PaginationView) {}
        func paginationView(_ paginationView: PaginationView, positionCountAtIndex index: Int) -> Int { 1 }
    }
}
