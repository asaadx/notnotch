// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The alarm picker from the phone's Clock: an hour, a minute and a meridiem
/// on three drums behind one shared band. Each drum is dragged, flicked or
/// scrolled, coasts and settles on a value.
struct NotchTaskTimePicker: View {
    @Binding var time: NotchTaskTime
    let text: NotchTaskStrings
    static let rowHeight: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(height: Self.rowHeight)
            HStack(spacing: 0) {
                NotchTaskTimeWheel(count: 12, loops: true, alignment: .trailing, label: text.hour,
                                   selection: Binding(get: { time.hour - 1 }, set: { time.hour = $0 + 1 })) { "\($0 + 1)" }
                    .frame(width: 58)
                NotchTaskTimeWheel(count: 60, loops: true, alignment: .center, label: text.minute,
                                   selection: $time.minute) { String(format: "%02d", $0) }
                    .frame(width: 58)
                NotchTaskTimeWheel(count: 2, loops: false, alignment: .leading, label: text.time,
                                   selection: Binding(get: { time.pm ? 1 : 0 }, set: { time.pm = $0 == 1 })) { $0 == 1 ? "pm" : "am" }
                    .frame(width: 50)
            }
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                   .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// One drum. Its position is a continuous row offset; the value under the
/// band is that offset rounded. A looping drum runs on past either end, as
/// the hours and minutes do on the phone.
struct NotchTaskTimeWheel: View {
    let count: Int
    let loops: Bool
    let alignment: Alignment
    let label: String
    @Binding var selection: Int
    let title: (Int) -> String
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var hovered = false
    @State private var scrollMonitor: Any?
    @State private var settle: DispatchWorkItem?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var rowHeight: CGFloat { NotchTaskTimePicker.rowHeight }

    var body: some View {
        GeometryReader { proxy in
            NotchTaskDrum(offset: offset, count: count, loops: loops, rowHeight: rowHeight,
                          height: proxy.size.height, alignment: alignment, title: title)
                .contentShape(Rectangle())
                .gesture(drag(height: proxy.size.height))
        }
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onHover { hovering in
            hovered = hovering
            hovering ? installScrollMonitor() : removeScrollMonitor()
        }
        .onAppear { offset = CGFloat(selection) }
        // A typed time turns the drum the short way round to its value.
        .onChange(of: selection) { _, value in
            let current = Int(offset.rounded())
            guard dragStart == nil, wrapped(current) != value else { return }
            var delta = value - wrapped(current)
            if loops, abs(delta) > count / 2 { delta -= delta.signum() * count }
            snap(to: CGFloat(current + delta), velocity: 0)
        }
        .onDisappear { removeScrollMonitor() }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    // MARK: - Input

    /// Follows the pointer, then coasts the way a flick would on the phone
    /// and settles on a row. A click without a drag brings that row to the
    /// band.
    private func drag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = start; settle?.cancel() }
                move(to: banded(start - value.translation.height / rowHeight))
            }
            .onEnded { value in
                defer { dragStart = nil }
                if abs(value.translation.height) < 3 {
                    let rows = ((value.location.y - height / 2) / rowHeight).rounded()
                    snap(to: offset.rounded() + rows, velocity: 0)
                    return
                }
                // The phone's deceleration rate: a flick at v points a second
                // travels about half of v before it rests.
                let velocity = -value.velocity.height / rowHeight
                snap(to: (offset + velocity * 0.5).rounded(), velocity: velocity)
            }
    }

    /// Wheel and trackpad scrolling while the pointer is over the drum. The
    /// trackpad's own coasting arrives as momentum events, so the drum glides
    /// with the fingers and settles once the scrolling stops.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovered, dragStart == nil else { return event }
            settle?.cancel()
            if event.hasPreciseScrollingDeltas {
                move(to: banded(offset - event.scrollingDeltaY / rowHeight))
                let work = DispatchWorkItem { snap(to: offset.rounded(), velocity: 0) }
                settle = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            } else if event.scrollingDeltaY != 0 {
                step(event.scrollingDeltaY > 0 ? -1 : 1)
            }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    // MARK: - Motion

    private func step(_ rows: Int) {
        snap(to: offset.rounded() + CGFloat(rows), velocity: 0)
    }

    /// Ends on a whole row with a spring that starts at the flick's speed,
    /// so the coast and the settle read as one motion.
    private func snap(to target: CGFloat, velocity: CGFloat) {
        let target = loops ? target : min(CGFloat(count - 1), max(0, target))
        let distance = target - offset
        commit(Int(target))
        guard distance != 0 else { return }
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.15)
            : .interpolatingSpring(stiffness: 120, damping: 22, initialVelocity: Double(velocity / distance))
        withAnimation(animation) { offset = target }
    }

    private func move(to next: CGFloat) {
        let before = Int(offset.rounded())
        offset = next
        let after = Int(next.rounded())
        if after != before {
            commit(after)
            NotchService.shared.provideHapticFeedback()
        }
    }

    /// A non-looping drum gives way past its ends and springs back, like a
    /// scroll view's rubber band.
    private func banded(_ value: CGFloat) -> CGFloat {
        guard !loops else { return value }
        let upper = CGFloat(count - 1)
        if value < 0 { return value * 0.35 }
        if value > upper { return upper + (value - upper) * 0.35 }
        return value
    }

    private func wrapped(_ row: Int) -> Int {
        loops ? ((row % count) + count) % count : min(count - 1, max(0, row))
    }

    private func commit(_ row: Int) {
        let clamped = wrapped(row)
        if selection != clamped { selection = clamped }
    }
}

/// The drum's face for one offset. Animatable, so a settle redraws every
/// frame on the way, with rows curving away from the band like a cylinder.
private struct NotchTaskDrum: View, Animatable {
    var offset: CGFloat
    let count: Int
    let loops: Bool
    let rowHeight: CGFloat
    let height: CGFloat
    let alignment: Alignment
    let title: (Int) -> String
    /// The angle each row turns on the cylinder.
    private static let rowAngle = 20.0

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    var body: some View {
        let center = Int(offset.rounded())
        ZStack {
            ForEach(center - 4...center + 4, id: \.self) { row in
                if loops || (0..<count).contains(row) { face(row) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func face(_ row: Int) -> some View {
        let distance = Double(row) - Double(offset)
        let angle = distance * Self.rowAngle
        let radius = Double(rowHeight) / (Self.rowAngle * .pi / 180)
        if abs(angle) < 88 {
            Text(title(((row % count) + count) % count))
                .font(.system(size: 21, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(max(0.2, 1 - abs(distance) * 0.45)))
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 8)
                .frame(height: rowHeight)
                .rotation3DEffect(.degrees(-angle), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .offset(y: CGFloat(radius * sin(angle * .pi / 180)))
        }
    }
}
