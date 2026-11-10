import MirmirKit
import SwiftUI

/// The template mark in the menu bar, with live decode tok/s while generating.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MarkImage.menuBar)
            if let decode = model.telemetry?.currentDecode, decode > 0 {
                Text(String(Int(decode.rounded()))).font(.mono(11, weight: .medium))
            }
        }
    }
}
