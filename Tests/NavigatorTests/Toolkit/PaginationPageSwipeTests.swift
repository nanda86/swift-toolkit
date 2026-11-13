// Copyright 2026 Readium Foundation. All rights reserved.
// Use of this source code is governed by the BSD-style license in LICENSE.

@testable import ReadiumNavigator
import UIKit
import XCTest

/// Setting `UIScrollView.isScrollEnabled` also re-enables its pan gesture. An
/// app that draws its own page turns turns the native swipe off, and every
/// slide between resources must restore that state rather than re-enable it.
@MainActor
final class PaginationPageSwipeTests: XCTestCase {
    func testSlidesBetweenResourcesKeepTheConfiguredPageSwipe() async throws {
        for enabled in [false, true] {
            let delegate = Pages()
            let pagination = PaginationView(frame: CGRect(x: 0, y: 0, width: 390, height: 700),
                                            preloadPreviousPositionCount: 1, preloadNextPositionCount: 1,
                                            isScrollEnabled: enabled)
            pagination.delegate = delegate
            pagination.reloadAtIndex(0, location: .start, pageCount: 3, readingProgression: .ltr)
            let scroll = try XCTUnwrap(pagination.subviews.compactMap { $0 as? UIScrollView }.first)
            XCTAssertEqual(scroll.panGestureRecognizer.isEnabled, enabled)

            for (index, location) in [(1, PageLocation.start), (0, .end), (1, .start)] {
                let moved = await pagination.goToIndex(index, location: location, options: .none)
                XCTAssertTrue(moved)
                XCTAssertEqual(scroll.isScrollEnabled, enabled, "Slide to \(index)")
                XCTAssertEqual(scroll.panGestureRecognizer.isEnabled, enabled, "Slide to \(index)")
            }
        }
    }

    private final class Page: UIView, PageView {
        func go(to location: PageLocation, animated: Bool) async {}
    }

    private final class Pages: PaginationViewDelegate {
        func paginationView(_ paginationView: PaginationView, pageViewAtIndex index: Int) -> (UIView & PageView)? {
            MainActor.assumeIsolated { Page() }
        }
        func paginationViewDidUpdateViews(_ paginationView: PaginationView) {}
        func paginationView(_ paginationView: PaginationView, positionCountAtIndex index: Int) -> Int { 1 }
    }
}
