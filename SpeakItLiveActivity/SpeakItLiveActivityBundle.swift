import SwiftUI
import WidgetKit

@main
struct SpeakItLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SpeakItQuickCaptureWidget()
        SpeakItTodayWidget()
        SpeakItCaptureLiveActivity()
        if #available(iOS 18.0, *) {
            SpeakItControlWidget()
        }
    }
}
