// Copyright 2026 Readium Foundation. All rights reserved.
// Use of this source code is governed by the BSD-style license in LICENSE.

import UIKit

extension PaginationView {
    /// The transparent EPUB surface can expose its live text underneath the
    /// frozen outgoing page while rubber-banding settles or a neighbor loads.
    /// Carry the navigator's reading background along with the snapshot.
    func opaqueChapterSnapshot() -> UIView? {
        guard let captured = snapshotView(afterScreenUpdates: false) else { return nil }
        var ancestor: UIView? = self
        var background: UIColor?
        while let view = ancestor {
            if let color = view.backgroundColor?.resolvedColor(with: traitCollection), color.cgColor.alpha == 1 {
                background = color
                break
            }
            ancestor = view.superview
        }
        let snapshot = UIView(frame: bounds)
        snapshot.backgroundColor = background ?? UIColor.systemBackground.resolvedColor(with: traitCollection)
        snapshot.isOpaque = true
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        snapshot.clipsToBounds = true
        captured.frame = snapshot.bounds
        snapshot.addSubview(captured)
        return snapshot
    }
}
