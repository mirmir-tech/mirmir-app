#if DEBUG
import MirmirKit
import SwiftUI

extension View {
    /// Renders the view as the app does, on `AppModel.preview` sample data.
    func previewModel(_ model: AppModel = .preview()) -> some View {
        environment(model).tint(Palette.signal)
    }
}

extension AppModel {
    /// The preview model opened on one sidebar section.
    func showing(_ section: SidebarSection) -> AppModel {
        self.section = section
        return self
    }
}
#endif
