import CheckPanel
import SwiftUI

extension CheckPanelController {
    /// Add an App…'s check of `app`: how far it has got, what it asks, its Stop.
    func show(_ app: CheckableApp, model: AddAppModel) {
        show { resized, dimmed in
            CheckPanelView(model: model, app: app, resized: resized, dimmed: dimmed)
        }
    }
}
