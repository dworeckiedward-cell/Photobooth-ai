import SwiftUI

// MARK: - Events Calendar tab

struct EventsCalendarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var connectSheetPresented = false

    private let cal = Calendar.current

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                connectBanner
                    .padding(.horizontal, BoothifySpacing.md)
                    .padding(.top, BoothifySpacing.xs)
                    .padding(.bottom, BoothifySpacing.sm)

                monthHeader
                    .padding(.horizontal, BoothifySpacing.md)
                    .padding(.bottom, BoothifySpacing.sm)

                weekdayRow
                    .padding(.horizontal, BoothifySpacing.sm)

                Divider()
                    .background(BoothifyTheme.surfaceLine)
                    .padding(.top, BoothifySpacing.xs)

                calendarGrid
                    .padding(.horizontal, BoothifySpacing.sm)
                    .padding(.vertical, BoothifySpacing.sm)

                Divider()
                    .background(BoothifyTheme.surfaceLine)

                dayEventsList
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap(.light)
                    app.push(.photoboothLanding)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                }
                .accessibilityLabel("New Event")
            }
        }
        .task { await app.loadRecentEvents() }
        .refreshable { await app.loadRecentEvents() }
        .sheet(isPresented: $connectSheetPresented) {
            ConnectCalendarSheet()
        }
    }

    // MARK: - Connect banner

    private var connectBanner: some View {
        Button {
            Haptics.tap(.light)
            connectSheetPresented = true
        } label: {
            AppCard(padding: BoothifySpacing.sm + 2) {
                HStack(spacing: BoothifySpacing.md) {
                    AppIconBadge(symbol: "link.circle.fill", color: BoothifyTheme.violet, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect your calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Sync with Google Calendar or iPhone")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) {
                    displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80), value: displayMonth)

            Spacer()

            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) {
                    displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Weekday row

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(cal.shortStandaloneWeekdaySymbols, id: \.self) { day in
                Text(day.prefix(1))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let cells = monthCells(for: displayMonth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(
                        date: date,
                        isToday: cal.isDateInToday(date),
                        isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                        hasEvents: eventCount(on: date) > 0,
                        eventCount: eventCount(on: date)
                    ) {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72)) {
                            selectedDate = date
                        }
                    }
                } else {
                    Color.clear
                        .frame(height: dayCellHeight)
                }
            }
        }
        .id(displayMonth)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24)),
            removal:   .opacity.combined(with: .offset(x: -24))
        ))
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80), value: displayMonth)
    }

    private var dayCellHeight: CGFloat { 44 }

    // MARK: - Day events list

    @ViewBuilder
    private var dayEventsList: some View {
        let events = eventsOn(selectedDate)
        let dateStr = selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))

        ScrollView {
            VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                HStack {
                    Text(dateStr)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Spacer()
                    if !events.isEmpty {
                        Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(BoothifyTheme.textMuted)
                    }
                }
                .padding(.top, BoothifySpacing.md)

                if events.isEmpty {
                    emptyDayView
                } else {
                    ForEach(events) { event in
                        CalendarEventRow(event: event) {
                            Haptics.tap()
                            app.push(.eventHub(eventId: event.id))
                        }
                    }
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.bottom, BoothifySpacing.xl)
        }
    }

    private var emptyDayView: some View {
        AppEmptyState(
            symbol: "calendar",
            title: "No events",
            subtitle: "No photobooth events on this day.",
            actionLabel: "New Event",
            action: { app.push(.photoboothLanding) }
        )
        .padding(.top, BoothifySpacing.sm)
    }

    // MARK: - Calendar helpers

    private func monthCells(for month: Date) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }

        // Weekday of first day (0 = Sunday in default Gregorian)
        let firstWeekday = cal.component(.weekday, from: firstDay) - 1
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstDay) {
                cells.append(d)
            }
        }
        // Pad to complete last row
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func eventsOn(_ date: Date) -> [Event] {
        app.events.filter { cal.isDate($0.createdAt, inSameDayAs: date) }
    }

    private func eventCount(on date: Date) -> Int {
        eventsOn(date).count
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let eventCount: Int
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                ZStack {
                    // Selected background
                    if isSelected {
                        Circle()
                            .fill(BoothifyTheme.violet)
                            .frame(width: 34, height: 34)
                    } else if isToday {
                        Circle()
                            .fill(BoothifyTheme.violet.opacity(0.18))
                            .frame(width: 34, height: 34)
                    }

                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 15, weight: isToday || isSelected ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected ? .white :
                            isToday    ? BoothifyTheme.violet : .white
                        )
                }

                // Event dot(s)
                if hasEvents {
                    HStack(spacing: 3) {
                        ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white.opacity(0.8) : BoothifyTheme.violet)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Spacer().frame(height: 4 + 3) // same height as dots row so cells stay uniform
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
        .accessibilityLabel("\(date.formatted(.dateTime.day().month())), \(hasEvents ? "\(eventCount) events" : "no events")")
    }
}

// MARK: - Event row in day list

private struct CalendarEventRow: View {
    let event: Event
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BoothifySpacing.md) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BoothifyTheme.violet)
                    .frame(width: 3)
                    .frame(minHeight: 52)

                AppIconBadge(symbol: "camera.aperture", color: BoothifyTheme.violet, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(event.completedPhotos) photo\(event.completedPhotos == 1 ? "" : "s") completed")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .padding(.vertical, BoothifySpacing.sm)
            .padding(.horizontal, BoothifySpacing.md)
            .background(BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(BoothifyTheme.violet.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connect Calendar sheet

struct ConnectCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BoothifyTheme.bg.ignoresSafeArea()

                VStack(spacing: BoothifySpacing.xl) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(BoothifyTheme.violet.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(BoothifyTheme.violet)
                    }
                    .padding(.top, BoothifySpacing.xl)

                    VStack(spacing: BoothifySpacing.sm) {
                        Text("Calendar Sync")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Connect your calendar to see upcoming bookings and automatically add new events.")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BoothifySpacing.xl)
                    }

                    // Coming soon notice — not tappable, not a false affordance
                    HStack(spacing: BoothifySpacing.md) {
                        AppIconBadge(symbol: "lock.fill", color: BoothifyTheme.textMuted, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Google Calendar & iPhone Calendar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.textSecondary)
                            Text("Calendar sync is coming in a future update.")
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(BoothifySpacing.md)
                    .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )
                    .padding(.horizontal, BoothifySpacing.lg)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Calendar sync coming soon")

                    Spacer()
                }
            }
            .navigationTitle("Connect Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BoothifyTheme.violet)
                }
            }
        }
    }

}

// MARK: - Calendar extension

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

#Preview {
    NavigationStack {
        EventsCalendarView()
    }
    .environment(AppState())
}
