import SwiftUI

/// The surfaces an extension's own views paint, fixed to Tinycast's light appearance.
enum ExtensionColors {
    static let fieldFill = Color.black.opacity(0.05)
    static let fieldFocusStroke = Color.black.opacity(0.24)
    static let fieldStroke = Color.black.opacity(0.10)
    static let tagFill = Color.black.opacity(0.05)
    static let tagSelectedStroke = Color.black.opacity(0.26)
    /// Fainter than a list row, since a grid tiles many of them.
    static let gridItemFill = Color.black.opacity(0.035)
    static let detailCardFill = Color.black.opacity(0.04)
}
