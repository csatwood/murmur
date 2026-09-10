import SwiftUI

// MARK: - Insights
//
// Redesigned per the "Main" canvas (Insights.dc.html): same `GlassPanelPage`
// shell as Home, warm ink/sunset palette instead of the shared dynamic
// `Palette`. The line-chart math (monotone interpolation, hover crosshair,
// end-label placement) is untouched — this is a View-layer rewrite only.
//
// The design replaced the old saturated bar chart with a line + soft area
// wash (the dataviz rule: "trend over time" is a line, not bars), a 2.5px
// stroke, recessive hairline gridlines, a direct end-label on the latest
// point, and a hover crosshair + tooltip (the last two aren't in the static
// mockup — added because a 7-point chart with no way to read exact values
// per day is a worse chart, not a more faithful one).

struct InsightsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var hoverIndex: Int?

    var body: some View {
        GlassPanelPage {
            VStack(alignment: .leading, spacing: 0) {
                header

                // `.pcard flat stat-row`: a flat strip on the pane with
                // hairline dividers — no card fill, not three boxed cards.
                Card(flat: true) {
                    HStack(alignment: .top, spacing: 0) {
                        statTile(.lines, "\(app.entries.count)", "dictations",
                                 trend: dictationsTrend, isFirst: true)
                        statTile(.wave, compact(totalWords), "total words",
                                 trend: wordsTrend, isFirst: false)
                        statTile(.calendar, avgWords, "avg words / dictation",
                                 trend: nil, isFirst: false)
                    }
                }
                .padding(.top, 24)

                chartCard
                    .padding(.top, 26)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insights")
                .font(.manrope(22, .medium))
                .tracking(-0.33)
                .foregroundStyle(Palette.warmInk)
            Text("Word-count trends over time.")
                .font(.manrope(12.5))
                .foregroundStyle(Palette.warmInkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Words dictated")
                    .font(.manrope(13, .semibold))
                    .foregroundStyle(Palette.warmInk)
                Spacer()
                Text("Last 7 days")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            TrendChart(points: last7Days, hoverIndex: $hoverIndex)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // No drop shadow, by request (same call as Scratchpad's editor
        // card and Ask Murmur's composer) — it read as an odd smear along
        // the bottom edge sitting on the frosted glass panel.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statTile(
        _ icon: MurmurIcon, _ value: String, _ label: String,
        trend: String?, isFirst: Bool
    ) -> some View {
        // The divider is an *overlay*, not a layout sibling. A bare
        // `Rectangle` with only a width set expands to whatever height is
        // offered, so as a sibling it competed with the chart for free
        // vertical space and stretched this whole strip. As an overlay it
        // paints inside the tile's content-derived height and can never
        // influence layout.
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.manrope(27))
                .tracking(-0.54)
                .foregroundStyle(Palette.warmInk)
            HStack(spacing: 5) {
                MurmurIconView(icon: icon)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Palette.warmInkFaint)
                Text(label)
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.warmInkFaint)
            }
            .padding(.top, 4)
            if let trend {
                HStack(spacing: 4) {
                    MurmurIconView(icon: .arrowRight)
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(-45))
                    Text(trend).font(.manrope(12, .semibold))
                }
                .foregroundStyle(Palette.sunsetDeep)
                .padding(.top, 6)
            }
        }
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isFirst ? 0 : 20)
        .overlay(alignment: .leading) {
            // Sits exactly on the tile boundary (outside this tile's own
            // 20pt leading inset), the same seam `.stat-row > div` draws it
            // on in the design.
            if !isFirst {
                Rectangle().fill(Palette.warmDivider).frame(width: 1)
                    .padding(.leading, -20)
            }
        }
    }

    // MARK: Derived data

    private var totalWords: Int {
        app.entries.reduce(0) { $0 + $1.wordCount }
    }

    private var avgWords: String {
        app.entries.isEmpty ? "—" : "\(totalWords / app.entries.count)"
    }

    private func compact(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fK", Double(number) / 1000) : "\(number)"
    }

    private var last7Days: [(label: String, value: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let words = app.entries
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            return (day.formatted(.dateTime.day().month(.abbreviated)), words)
        }
    }

    /// Compares the last 7 days against the 7 before them.
    private func weekOverWeek(_ metric: (Range<Int>) -> Int) -> String? {
        let this = metric(0..<7)
        let prior = metric(7..<14)
        guard prior > 0, this != prior else { return nil }
        let change = Double(this - prior) / Double(prior) * 100
        guard change > 0 else { return nil }
        return "\(Int(change))% vs last week"
    }

    private var wordsTrend: String? {
        weekOverWeek { range in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return range.reduce(0) { sum, offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                return sum + app.entries
                    .filter { calendar.isDate($0.date, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.wordCount }
            }
        }
    }

    private var dictationsTrend: String? {
        weekOverWeek { range in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return range.reduce(0) { sum, offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                return sum + app.entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            }
        }
    }
}

// MARK: - Trend chart

/// Reports the hover tooltip's own rendered size back up so its position
/// can be derived from its *actual* height instead of a guessed constant.
private struct TooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TrendChart: View {
    let points: [(label: String, value: Int)]
    @Binding var hoverIndex: Int?

    /// The hover tooltip's own measured size (see `SizeKey` below) — its
    /// position is derived from this rather than a guessed fixed offset,
    /// so the gap above the curve is exact regardless of font metrics.
    @State private var tooltipSize: CGSize = .zero

    /// Fixed clearance between the tooltip's bottom edge and the point it
    /// describes. Previously the tooltip was centered a flat 34pt above
    /// the point with no regard for its own height, which happened to
    /// leave a reasonable gap only by coincidence for a short tooltip —
    /// against Manrope's actual line height here, the box's bottom edge
    /// landed right on the curve instead, worst right at a peak (the one
    /// case that most needs clearance). Positioning off the tooltip's own
    /// measured height fixes this everywhere, not just at the extremes.
    private static let tooltipGap: CGFloat = 10

    /// The plot and the y-axis labels must be laid out at exactly the same
    /// height or the ticks stop lining up with their gridlines. A seven-
    /// point weekly trend doesn't get more readable past roughly this
    /// height — it just leaves the line stranded in empty space — so the
    /// chart is deliberately sized, not stretched to fill the window.
    private let plotHeight: CGFloat = 240

    private var maxValue: Int {
        max(points.map(\.value).max() ?? 0, 1)
    }

    /// Rounds the axis top up to a clean tick so gridlines read as round
    /// numbers rather than arbitrary maxima.
    private var axisTop: Int {
        let raw = Double(maxValue) * 1.15
        let magnitude = pow(10, floor(log10(max(raw, 1))))
        return max(Int(ceil(raw / magnitude) * magnitude), 1)
    }

    private var ticks: [Int] {
        (0...3).map { axisTop * $0 / 3 }
    }

    /// The y a given tick sits at. Used by both the gridlines and the axis
    /// labels so the two can't drift apart.
    private func gridY(for tick: Int, in height: CGFloat) -> CGFloat {
        height - (CGFloat(tick) / CGFloat(axisTop)) * height
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Y axis. Each label is positioned on its gridline's exact y,
            // not spread evenly down the column: four labels in four equal
            // slices only ever agrees with four gridlines at thirds for the
            // topmost one, which left "0" floating far below the baseline.
            ZStack(alignment: .topTrailing) {
                Color.clear
                ForEach(ticks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.manrope(10))
                        .foregroundStyle(Palette.warmInkFainter)
                        .alignmentGuide(.top) { d in d.height / 2 }
                        .offset(y: gridY(for: tick, in: plotHeight))
                }
            }
            .frame(width: 34, height: plotHeight, alignment: .topTrailing)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let coords = coordinates(in: CGSize(width: w, height: h))

                    ZStack(alignment: .topLeading) {
                        // Recessive gridlines
                        ForEach(ticks, id: \.self) { tick in
                            let y = gridY(for: tick, in: h)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Palette.warmRowBorder, lineWidth: 1)
                        }

                        // Area wash — ~10% opacity, never a saturated block
                        smoothPath(coords, closedTo: h)
                            .fill(Palette.sunset.opacity(0.1))

                        // 2.5px line
                        smoothPath(coords, closedTo: nil)
                            .stroke(Palette.sunset,
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        // Crosshair + hovered point
                        if let i = hoverIndex, coords.indices.contains(i) {
                            Path { p in
                                p.move(to: CGPoint(x: coords[i].x, y: 0))
                                p.addLine(to: CGPoint(x: coords[i].x, y: h))
                            }
                            .stroke(Palette.warmDivider, lineWidth: 1)
                            Circle()
                                .fill(Palette.sunset)
                                .frame(width: 8, height: 8)
                                .position(coords[i])
                        }

                        // Direct end-label on the most recent point
                        if let last = coords.last, let value = points.last?.value {
                            Circle()
                                .fill(Palette.sunset)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .position(last)
                            // `.line-chart-end-label`:
                            // `transform: translate(-50%, calc(-100% - 8px))`
                            // — centered on the dot, lifted clear above it.
                            //
                            // Clamping this horizontally (an earlier fix)
                            // was the actual bug: shifting the label left,
                            // toward the plot's interior, moves it onto a
                            // stretch of curve that's still descending —
                            // i.e. *higher* than the dot — so the line
                            // ended up passing through the label instead of
                            // under it. The design never clamps: the card
                            // carries its own ~20pt padding around the
                            // plot, the chart card doesn't clip its
                            // content, so a few points of horizontal
                            // overflow from a right-edge label lands
                            // harmlessly in that padding instead of
                            // overlapping the curve.
                            Text("\(value)")
                                .font(.manrope(12, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.sunset)
                                .fixedSize()
                                .position(x: last.x, y: max(last.y - 17, 9))
                        }

                        // Hover tooltip
                        if let i = hoverIndex, coords.indices.contains(i) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(points[i].value)")
                                    .font(.manrope(12, .semibold))
                                    .foregroundStyle(Palette.warmInk)
                                Text(points[i].label)
                                    .font(.manrope(10))
                                    .foregroundStyle(Palette.warmInkSoft)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.warmDivider, lineWidth: 1))
                            .background(
                                GeometryReader { tooltipGeo in
                                    Color.clear
                                        .preference(key: TooltipSizeKey.self, value: tooltipGeo.size)
                                })
                            // Bottom edge sits `tooltipGap` above the point,
                            // full stop — never clamped back down toward it
                            // (the previous bug: flooring this pulled the
                            // tooltip down toward a high peak once the old
                            // fixed offset went negative, landing it right
                            // on the curve instead of above it, worst
                            // exactly where clearance mattered most) and
                            // never guessed from font metrics (the other
                            // bug: a flat 34pt offset assumed a tooltip
                            // height that didn't match Manrope's real line
                            // height, so even the "un-clamped" version still
                            // touched the curve at every point, not just
                            // peaks). Floating above the plot's own top
                            // edge is fine — the chart card's padding
                            // absorbs it, same as the end-label's horizontal
                            // overflow above.
                            .position(x: min(max(coords[i].x, 40), w - 40),
                                      y: coords[i].y - Self.tooltipGap - tooltipSize.height / 2)
                            .onPreferenceChange(TooltipSizeKey.self) { tooltipSize = $0 }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let step = w / CGFloat(max(points.count - 1, 1))
                            hoverIndex = min(max(Int((location.x / step).rounded()), 0), points.count - 1)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
                }
                .frame(height: plotHeight)

                // X axis — `justify-content: space-between`, matching how
                // the points themselves run edge to edge. Centering each
                // label in an equal-width column instead (as this did)
                // offsets every label from the dot it belongs to, worst at
                // the two ends. The last day (today) is always bold/dark,
                // matching the mockup's own static emphasis — every other
                // day is faint unless actively hovered.
                HStack(spacing: 4) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let isLast = index == points.count - 1
                        let isHighlighted = isLast || index == hoverIndex
                        Text(point.label)
                            .font(.manrope(10.5, isLast ? .semibold : .regular))
                            .foregroundStyle(isHighlighted ? Palette.warmInk : Palette.warmInkFainter)
                            .fixedSize()
                        if index != points.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func coordinates(in size: CGSize) -> [CGPoint] {
        let n = max(points.count - 1, 1)
        return points.enumerated().map { index, point in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(n),
                y: size.height - (CGFloat(point.value) / CGFloat(axisTop)) * size.height)
        }
    }

    /// Monotone cubic (Fritsch–Carlson) Hermite interpolation.
    ///
    /// The mockup smooths with plain Catmull-Rom, which is fine for its
    /// hand-picked sample data but **overshoots** on real data: a flat run
    /// of zero-word days followed by a spike makes the curve swing below
    /// the baseline, drawing days with negative words. Word counts can't
    /// be negative, so the chart must not be able to draw one.
    ///
    /// This variant limits each tangent to the slope of its neighbouring
    /// segments, so the curve is guaranteed to stay within the range of
    /// the two points it connects — it can never dip under a zero day.
    private func smoothPath(_ pts: [CGPoint], closedTo bottom: CGFloat?) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }

        let n = pts.count
        // Secant slope of each segment.
        var slopes = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            slopes[i] = dx == 0 ? 0 : (pts[i + 1].y - pts[i].y) / dx
        }
        // Tangents: average of adjacent secants, endpoints one-sided.
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0
                ? 0                                     // local extremum: flatten
                : (slopes[i - 1] + slopes[i]) / 2
        }
        // Fritsch–Carlson limiter — the step that actually prevents overshoot.
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let alpha = tangents[i] / slopes[i]
            let beta = tangents[i + 1] / slopes[i]
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                tangents[i] = tau * alpha * slopes[i]
                tangents[i + 1] = tau * beta * slopes[i]
            }
        }
        for i in 0..<(n - 1) {
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let dx = (p2.x - p1.x) / 3
            let c1 = CGPoint(x: p1.x + dx, y: p1.y + tangents[i] * dx)
            let c2 = CGPoint(x: p2.x - dx, y: p2.y - tangents[i + 1] * dx)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if let bottom, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.addLine(to: CGPoint(x: first.x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}
