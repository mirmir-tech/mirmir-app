import MirmirKit
import SwiftUI

/// How the models screens show a memory fit: one wording and one color for
/// every view, so no view maps the judgement to text of its own.
extension MemoryFit {
    /// The judgement in a sentence's words; nil when the server cannot tell.
    var label: String? {
        switch self {
        case .fits: "fits"
        case .tight: "fits with little to spare"
        case .doesNotFit: "does not fit"
        case .unknown: nil
        }
    }

    /// A tint that draws the eye to a tight or failed fit; nil otherwise.
    var color: Color? {
        switch self {
        case .tight: Palette.warning
        case .doesNotFit: Palette.danger
        case .fits, .unknown: nil
        }
    }

    /// A list entry's marker: only the fits worth a second look.
    var marker: String {
        switch self {
        case .tight, .doesNotFit: label.map { " · \($0)" } ?? ""
        case .fits, .unknown: ""
        }
    }

    /// `Needs 6 GB, fits` for a requirement and this judgement.
    func summary(needs required: UInt64?) -> String {
        let needs = required.map { "Needs \(Format.bytes($0))" }
        return [needs, label].compactMap(\.self).joined(separator: ", ")
    }
}
