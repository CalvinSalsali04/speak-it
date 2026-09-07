import SwiftUI

/// Seven dots for the week, today's ringed. Sized to sit on the eyebrow line
/// beside the date, so the row costs Today no vertical space.
///
/// It is not a button and has nothing to configure. Filled means the person
/// kept a thought or finished a task that day; an empty dot is simply an
/// empty dot, never a loss. VoiceOver reads the row as one sentence.
struct WeekRowView: View {
    let activity: WeekActivity

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<7, id: \.self) { index in
                dot(active: activity.days[index], isToday: index == activity.todayIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.accessibilityLabel)
        .accessibilityIdentifier("today.weekRow")
    }

    private func dot(active: Bool, isToday: Bool) -> some View {
        Circle()
            .fill(active ? Color.speakInk : Color.speakDivider)
            .frame(width: 7, height: 7)
            .overlay {
                if isToday {
                    Circle()
                        .stroke(Color.speakInk, lineWidth: 1.25)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 12, height: 12)
    }
}
