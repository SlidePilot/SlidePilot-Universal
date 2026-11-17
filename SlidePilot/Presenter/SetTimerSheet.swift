import SlidePilotCore
import SwiftUI

/// Asks for the timer's hours, minutes and seconds (TIME-03). Cancel keeps the old time
/// (the old app applied it anyway, DEF-01).
struct SetTimerSheet: View {
    let apply: (Int) -> Void
    @State private var components: TimerDurationComponents
    @Environment(\.dismiss) private var dismiss

    init(duration: Int, apply: @escaping (Int) -> Void) {
        self.apply = apply
        _components = State(initialValue: TimerDurationComponents(totalSeconds: duration))
    }

    var body: some View {
        NavigationStack {
            DurationFields(components: $components)
                .navigationTitle("Set Timer")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set") {
                            apply(components.totalSeconds)
                            dismiss()
                        }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

#if os(macOS)
/// Text fields with steppers, like the old app's hour/minute/second picker.
private struct DurationFields: View {
    @Binding var components: TimerDurationComponents

    var body: some View {
        Form {
            field("Hours", value: $components.hours, range: TimerDurationComponents.hourRange)
            field("Minutes", value: $components.minutes, range: TimerDurationComponents.minuteRange)
            field("Seconds", value: $components.seconds, range: TimerDurationComponents.secondRange)
        }
        .formStyle(.grouped)
        .frame(minWidth: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let clamped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
        // A text binding updates on every keystroke, so Return or Set right after typing
        // applies the typed number (a value-format field only commits when editing ends).
        let text = Binding(
            get: { String(clamped.wrappedValue) },
            set: { clamped.wrappedValue = Int($0.filter(\.isNumber)) ?? 0 }
        )
        return LabeledContent(title) {
            HStack {
                TextField(title, text: text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 60)
                Stepper(title, value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }
}
#else
/// Wheels for hours, minutes and seconds, like the Clock app's timer.
private struct DurationFields: View {
    @Binding var components: TimerDurationComponents

    var body: some View {
        HStack(spacing: 0) {
            wheel("Hours", value: $components.hours, range: TimerDurationComponents.hourRange)
            wheel("Minutes", value: $components.minutes, range: TimerDurationComponents.minuteRange)
            wheel("Seconds", value: $components.seconds, range: TimerDurationComponents.secondRange)
        }
        .padding(.horizontal)
    }

    private func wheel(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack {
            Text(title)
                .font(.headline)
                .accessibilityHidden(true)
            Picker(title, selection: value) {
                ForEach(range, id: \.self) { number in
                    Text(number, format: .number).tag(number)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
    }
}
#endif
