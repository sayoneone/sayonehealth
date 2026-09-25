import WidgetKit
import SwiftUI

@main
struct SayoneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        FavoritesWidget()
        QuickLogControl()
    }
}
