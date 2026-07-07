import SwiftUI

// MARK: - Events Calendar tab
//
// Glass redesign: the month grid floats as one glass pane on the black
// atmosphere; the selected day's events list under it, followed by an
// agenda of ALL past events grouped under their dates — tap any row to
// open that event's hub. Copy is 360-era (spins/videos, not photos).

struct EventsCalendarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var connectSheetPresented = false

    private let cal = Calendar.current

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BoothifySpacing.lg) {
                    calendarCard
                        .entrance(0)

                    selectedDaySection
                        .entrance(1)

                    allEventsSection
                        .entrance(2)

                    connectBanner
                        .entrance(3)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.top, BoothifySpacing.sm)
                .padding(.bottom, BoothifySpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap(.light)
                    app.push(.booth360Landing)
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

    // MARK: - Calendar pane (month header + weekdays + grid on one glass)

    private var calendarCard: some View {
        VStack(spacing: BoothifySpacing.sm) {
            monthHeader
            weekdayRow
            calendarGrid
        }
        .padding(BoothifySpacing.sm + 4)
        // Rich glassmorphism: a violet tint under the pane makes the glass
        // read clearly on the black stage (same treatment as the home hero).
        .background(
            LinearGradient(
                colors: [BoothifyTheme.indigoGlow.opacity(0.30), BoothifyTheme.violet.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
        )
        .glassSurface(radius: BoothifyRadius.hero)
    }

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
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

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
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(cal.shortStandaloneWeekdaySymbols, id: \.self) { day in
                Text(day.prefix(1))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

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
                    Color.clear.frame(height: 48)
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

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDaySection: some View {
        let events = eventsOn(selectedDate)

        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
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
            .padding(.horizontal, 2)

            if events.isEmpty {
                // Quiet whisper — the calendar above is the hero.
                Text("No events on this day.")
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .padding(.leading, 2)
            } else {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
        }
    }

    // MARK: - All past events (agenda, newest first)

    @ViewBuilder
    private var allEventsSection: some View {
        if !app.events.isEmpty {
            VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                Text("ALL EVENTS")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .padding(.horizontal, 2)

                ForEach(app.events.sorted(by: { $0.createdAt > $1.createdAt })) { event in
                    eventRow(event, showDate: true)
                }
            }
        }
    }

    // MARK: - Event row (glass, 360-era copy)

    private func eventRow(_ event: Event, showDate: Bool = false) -> some View {
        let spins = app.jobs(for: event.id).filter { $0.status == .completed }.count
        let isLive = app.currentEventId == event.id

        return Button {
            Haptics.tap()
            app.push(.booth360EventHub(eventId: event.id))
        } label: {
            HStack(spacing: BoothifySpacing.sm + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .fill(BoothifyTheme.violet.opacity(isLive ? 0.30 : 0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: "rotate.3d")
                        .font(.body.weight(.medium))
                        .foregroundStyle(isLive ? .white : BoothifyTheme.violet)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isLive {
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .kerning(0.5)
                                .foregroundStyle(BoothifyTheme.violet)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BoothifyTheme.violet.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(rowSubtitle(event: event, spins: spins, showDate: showDate))
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: BoothifySpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .padding(.horizontal, BoothifySpacing.sm + 4)
            .padding(.vertical, BoothifySpacing.sm + 2)
            .glassSurface(radius: BoothifyRadius.card)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this event")
    }

    private func rowSubtitle(event: Event, spins: Int, showDate: Bool) -> String {
        var parts: [String] = []
        if showDate {
            parts.append(event.createdAt.formatted(.dateTime.month(.abbreviated).day()))
        }
        parts.append(spins == 1 ? "1 video" : "\(spins) videos")
        return parts.joined(separator: " · ")
    }

    // MARK: - Connect banner (quiet, at the bottom)

    private var connectBanner: some View {
        Button {
            Haptics.tap(.light)
            connectSheetPresented = true
        } label: {
            HStack(spacing: BoothifySpacing.sm + 2) {
                Image(systemName: "link")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("Connect Google or iPhone calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BoothifyTheme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.sm + 2)
            .glassSurface(radius: BoothifyRadius.card)
        }
        .buttonStyle(.plain)
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

// MARK: - Connect Calendar sheet

struct ConnectCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()

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
                    .glassSurface(radius: BoothifyRadius.tile)
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
