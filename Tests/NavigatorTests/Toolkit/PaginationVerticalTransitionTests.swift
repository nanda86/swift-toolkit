// Copyright 2026 Readium Foundation. All rights reserved.
// Use of this source code is governed by the BSD-style license in LICENSE.

@testable import ReadiumNavigator
import ReadiumShared
import UIKit
import XCTest

@MainActor
final class PaginationVerticalTransitionTests: XCTestCase {
    func testVerticalTransitionsRetainLogicalChapterOrderAndNativePageSize() async {
        for progression: ReadingProgression in [.ltr, .rtl] {
            let delegate = Pages()
            let pagination = PaginationView(frame: CGRect(x: 0, y: 0, width: 390, height: 700),
                preloadPreviousPositionCount: 2, preloadNextPositionCount: 2, isScrollEnabled: false)
            pagination.delegate = delegate
            pagination.animatesChapterTransitionsVertically = true
            pagination.reloadAtIndex(0, location: .start, pageCount: 3, readingProgression: progression)
            let moved = await pagination.goToIndex(1, location: .start, options: .none)
            pagination.layoutIfNeeded()
            XCTAssertTrue(moved)
            XCTAssertEqual(pagination.currentIndex, 1)
            XCTAssertEqual(pagination.currentView?.bounds.size, pagination.bounds.size)
            XCTAssertEqual(pagination.currentView?.transform, .identity)
            let back = await pagination.goToIndex(0, location: .end, options: .none)
            XCTAssertTrue(back)
            XCTAssertEqual(pagination.currentIndex, 0)
            XCTAssertEqual(pagination.currentView?.transform, .identity)
            let outside = await pagination.goToIndex(-1, location: .end, options: .none)
            XCTAssertFalse(outside)
            XCTAssertEqual(pagination.currentIndex, 0)
        }
    }

    private final class Page: UIView, PageView {
        func go(to location: PageLocation, animated: Bool) async {}
    }

    private final class Pages: PaginationViewDelegate {
        func paginationView(_ paginationView: PaginationView, pageViewAtIndex index: Int) -> (UIView & PageView)? {
            Page()
        }
        func paginationViewDidUpdateViews(_ paginationView: PaginationView) {}
        func paginationView(_ paginationView: PaginationView, positionCountAtIndex index: Int) -> Int { 1 }
    }
}
