import SwiftUI

/// Home week strip with a subtle expand control that reveals a compact month grid.
/// Selection is a pure `Date` binding — no domain logic.
struct TTHomeWeekDatePicker: View {
    @Binding var selected: Date
    var accent: Color = TTColor.actionOrange

    @State private var isExpanded = false
    @State private var visibleMonth: Date = Date()
    @State private var weekDragOffset: CGFloat = 0
    @State private var monthDragOffset: CGFloat = 0
    @Namespace private var dayNS

    private let calendar = Calendar.current
    private let soft = Animation.spring(response: 0.42, dampingFraction: 0.86)
    private let chipWidth: CGFloat = 48
    private let chipHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekRow
            if isExpanded {
                monthPanel
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
        }
        .animation(soft, value: isExpanded)
        .animation(soft, value: calendar.isDate(selected, equalTo: visibleMonth, toGranularity: .month))
        .onAppear {
            visibleMonth = startOfMonth(selected)
        }
        .onChange(of: selected) { _, newValue in
            let month = startOfMonth(newValue)
            if !calendar.isDate(month, equalTo: visibleMonth, toGranularity: .month) {
                withAnimation(soft) { visibleMonth = month }
            }
        }
    }

    // MARK: - Week row

    private var weekRow: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weekDays, id: \.self) { day in
                            weekChip(day)
                                .id(dayKey(day))
                        }
                    }
                    .padding(.trailing, 2)
                    .offset(x: weekDragOffset * 0.15)
                }
                .simultaneousGesture(weekScrubGesture)
                .onAppear { scrollWeek(proxy) }
                .onChange(of: selected) { _, _ in scrollWeek(proxy) }
            }

            expandButton
        }
    }

    private func weekChip(_ day: Date) -> some View {
        let on = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        return Button {
            select(day)
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(TTFont.textSM(.semibold))
                Text(day.formatted(.dateTime.day()))
                    .font(TTFont.headingXS(.semibold))
            }
            .foregroundStyle(on ? .white : .black)
            .frame(width: chipWidth, height: chipHeight)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent)
                        .matchedGeometryEffect(id: "homeWeekPill", in: dayNS)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.96))
                }
            }
            .overlay(alignment: .bottom) {
                if isToday && !on {
                    Circle()
                        .fill(accent.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 6)
                }
            }
        }
        .buttonStyle(TTHomeCardPressStyle())
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var expandButton: some View {
        Button {
            TTHomeHaptics.light()
            withAnimation(soft) {
                isExpanded.toggle()
                if isExpanded {
                    visibleMonth = startOfMonth(selected)
                }
            }
        } label: {
            TTIcon(icon: isExpanded ? .chevronUp : .chevronDown, size: 11)
                .foregroundStyle(Color(white: 0.42))
                .frame(width: 28, height: chipHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide calendar" : "Show month calendar")
        .opacity(0.72)
    }

    // MARK: - Month panel

    private var monthPanel: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeaders
            monthGrid
                .offset(x: monthDragOffset)
                .gesture(monthSwipeGesture)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                TTIcon(icon: .chevronLeft, size: 12)
                    .foregroundStyle(Color(white: 0.4))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.96))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .contentTransition(.opacity)

            Spacer(minLength: 8)

            Button {
                shiftMonth(by: 1)
            } label: {
                TTIcon(icon: .chevronRight, size: 12)
                    .foregroundStyle(Color(white: 0.4))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.96))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(TTFont.workSans(10, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let cells = monthCells
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    monthDayCell(day)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func monthDayCell(_ day: Date) -> some View {
        let on = calendar.isDate(day, inSameDayAs: selected)
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)

        return Button {
            select(day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(TTFont.workSans(13, weight: on ? .semibold : .medium))
                .foregroundStyle(
                    on ? Color.white
                        : inMonth ? Color.black.opacity(0.88) : Color.black.opacity(0.28)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if on {
                        Circle().fill(accent)
                    } else if isToday {
                        Circle().strokeBorder(accent.opacity(0.45), lineWidth: 1.2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.month().day().year()))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Gestures

    private var weekScrubGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                // Prefer horizontal scrub; ignore mostly-vertical pans (scroll)
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                weekDragOffset = value.translation.width
            }
            .onEnded { value in
                defer { withAnimation(.easeOut(duration: 0.2)) { weekDragOffset = 0 } }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let threshold: CGFloat = 42
                if value.translation.width < -threshold {
                    shiftDay(by: 1)
                } else if value.translation.width > threshold {
                    shiftDay(by: -1)
                }
            }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                monthDragOffset = value.translation.width * 0.35
            }
            .onEnded { value in
                let dx = value.translation.width
                withAnimation(soft) { monthDragOffset = 0 }
                guard abs(dx) > abs(value.translation.height), abs(dx) > 48 else { return }
                shiftMonth(by: dx < 0 ? 1 : -1)
            }
    }

    // MARK: - Actions

    private func select(_ day: Date) {
        TTHomeHaptics.selection()
        withAnimation(soft) {
            selected = calendar.startOfDay(for: day)
            visibleMonth = startOfMonth(day)
        }
    }

    private func shiftDay(by delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selected) else { return }
        select(next)
    }

    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        TTHomeHaptics.light()
        withAnimation(soft) {
            visibleMonth = startOfMonth(next)
        }
    }

    private func scrollWeek(_ proxy: ScrollViewProxy) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(dayKey(selected), anchor: .center)
        }
    }

    // MARK: - Calendar helpers

    private var weekDays: [Date] {
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selected)) ?? selected
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard first > 0, first < symbols.count else { return symbols }
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading empty cells + in-range days; trailing empty weeks dropped for a compact height.
    private var monthCells: [Date?] {
        let monthStart = startOfMonth(visibleMonth)
        let gridStart = startOfWeek(monthStart)
        let raw: [Date?] = (0..<42).map { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
        let weeks = stride(from: 0, to: raw.count, by: 7).map { i in
            Array(raw[i..<min(i + 7, raw.count)])
        }
        let kept = weeks.filter { week in
            week.contains { day in
                guard let day else { return false }
                return calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
            }
        }
        return kept.flatMap { $0 }
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func startOfWeek(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
