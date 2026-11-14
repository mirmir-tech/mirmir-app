import MirmirKit
import SwiftUI

/// The template mark in the menu bar, with live decode tok/s while generating.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MarkImage.menuBar)
            if let decode = model.telemetry?.currentDecode, decode > 0 {
                Text(String(Int(decode.rounded()))).font(.mono(11, weight: .medium))
            }
        }
        // The label lives as long as the app, so reopening the app can
        // recreate a closed main window through it.
        .onAppear { MainWindow.opener = openWindow }
    }
}
