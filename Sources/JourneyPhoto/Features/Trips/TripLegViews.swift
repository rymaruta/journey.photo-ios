import SwiftUI
import MapKit

/// 場所と場所の間の1行（移動の見込み・2026-11-10 owner の要望・札 #521）。
///
/// 「歩き 約 15 分 · 車 約 6 分」。**押すと区間のシート**（`TripLegSheet`）——第2段で「どの電車・バスか」を
/// 出すときは、シートの中身だけを差し替える（この行と区間の型 `TripTravel.Leg` はそのまま）。
///
/// - 返った手段だけ並べる（最大2つ）。どれも返らなければ「経路を地図で開く」
/// - 圏外では聞かない（「電波が戻ると移動の見込みが出ます」）
/// - 聞いている間は細い線だけ（数を作らない）
struct TripLegRow: View {
    let leg: TripTravel.Leg
    let estimates: [TripTravel.Estimate]
    /// 聞き終えた（返らなかった手段も含めて）
    let settled: Bool
    let offline: Bool
    let throttled: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: JPSpace.s) {
                // 番号の丸の中心の下に、縦の線（行と行のつながり）
                Rectangle()
                    .fill(WebTheme.hairline)
                    .frame(width: JPStroke.hairline, height: 20)
                    .frame(width: TripStyle.stopNumberSide)
                    .accessibilityHidden(true)
                content
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(leg: leg, estimates: estimates, offline: offline))
        .accessibilityHint(L("区間の経路を地図のアプリで開く画面を出します", "Shows ways to open this route in a maps app."))
        .accessibilityIdentifier("trip.leg")
    }

    @ViewBuilder
    private var content: some View {
        if offline && estimates.isEmpty {
            note(TripTravel.offlineNote, symbol: "wifi.slash")
        } else if !estimates.isEmpty {
            HStack(spacing: JPSpace.s) {
                ForEach(estimates, id: \.mode) { estimate in
                    HStack(spacing: 4) {
                        Image(systemName: estimate.mode.symbol)
                            .font(JPFont.caption)
                            .accessibilityHidden(true)
                        Text("\(estimate.mode.label) \(TripTravel.duration(estimate.seconds))")
                            .font(JPFont.caption.monospacedDigit())
                    }
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(1)
                }
            }
        } else if settled || throttled {
            note(TripTravel.openInMaps, symbol: "map")
        } else {
            // 聞いている間（数を作らない）
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 96, height: 8)
                .accessibilityHidden(true)
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(JPFont.caption).accessibilityHidden(true)
            Text(text).font(JPFont.caption)
        }
        .foregroundStyle(WebTheme.faint)
    }

    nonisolated static func spoken(leg: TripTravel.Leg, estimates: [TripTravel.Estimate], offline: Bool) -> String {
        let route = L("\(leg.from.name)から\(leg.to.name)", "\(leg.from.name) to \(leg.to.name)")
        if !estimates.isEmpty { return "\(route)、\(TripTravel.spoken(estimates))" }
        if offline { return "\(route)、\(TripTravel.offlineNote)" }
        return route
    }
}

/// 区間のシート（2026-11-10 判断「0 円の形」・札 #521・提案の版4「乗り換えの詳しさ」）。
///
/// どの電車・バス・のりばまでは**地図のアプリが出す**（有料の API は使わない）。ここで出すのは:
/// - 区間の両端と、返った見込み（Apple のマップによるもの）
/// - 出る時刻の目安（「13:00 ごろに出ると、日の入り 16:47 の前に着く見込み」）。地図のアプリには日時を渡せないので、
///   合わせる時刻を見せる
/// - 主: 「Apple のマップで乗り換えを見る」（`MKMapItem.openMaps`・その区間の手段）。副: 「Google マップで乗り換えを見る」
///   （Maps URLs・鍵は要らない・`travelmode`）。選ぶのは2つのボタンだけ。設定は作らない
///
/// 両端は名前で探し直してから渡す（索引の座標は約1kmに丸めてある・`SpotDirections`）
struct TripLegSheet: View {
    let leg: TripTravel.Leg
    let estimates: [TripTravel.Estimate]
    let modes: [TripTravel.Mode]
    /// 行き先の日の日の出・日の入り（端末の計算）
    let sun: TripDraft.Sun?
    /// 行き先の時間帯の案内（「夕方の斜光」なら、その始まりに間に合う時刻で言う）
    let destinationTimes: [String]
    /// 前の場所の時間帯の案内（見てから出ると間に合わないときに一言添える）
    var previousTimes: [String] = []

    @Environment(\.openURL) private var openURL
    @State private var opening = false
    @State private var task: Task<Void, Never>?

    private var mode: TripTravel.Mode { TripTravel.openMode(estimates, modes: modes) }
    private var isTransit: Bool { mode == .transit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(L("\(leg.from.number) → \(leg.to.number)", "\(leg.from.number) → \(leg.to.number)"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("\(leg.from.name) → \(leg.to.name)", "\(leg.from.name) → \(leg.to.name)"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if !estimates.isEmpty {
                    VStack(alignment: .leading, spacing: JPSpace.xs) {
                        ForEach(estimates, id: \.mode) { e in
                            HStack(spacing: JPSpace.xs) {
                                Image(systemName: e.mode.symbol)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                Text(e.mode.label).font(JPFont.body)
                                Spacer(minLength: 0)
                                Text(TripTravel.duration(e.seconds)).font(JPFont.bodyEmphasis.monospacedDigit())
                            }
                            .foregroundStyle(WebTheme.text)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(JPSpace.m)
                    .jpCardFace()
                }

                if let first = estimates.first(where: { $0.mode == mode }) ?? estimates.first,
                   let hint = TripTravel.departureHint(travelSeconds: first.seconds,
                                                       destinationTimes: destinationTimes, sun: sun,
                                                       previous: (leg.from.name, previousTimes)) {
                    VStack(alignment: .leading, spacing: JPSpace.xxs) {
                        Text(hint.text)
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if let caution = hint.caution {
                            Text(caution)
                                .font(JPFont.footnote)
                                .foregroundStyle(WebTheme.muted2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let clock = hint.clock {
                            Text(TripTravel.setTimeNote(clock))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(spacing: JPSpace.xs) {
                    Button { openApple() } label: {
                        HStack(spacing: JPSpace.xs) {
                            if opening { ProgressView().tint(WebTheme.accentText) }
                            Text(isTransit ? L("Apple のマップで乗り換えを見る", "See transit in Apple Maps")
                                           : L("Apple のマップで経路を見る", "See the route in Apple Maps"))
                        }
                        .jpPillButton(.main(onPhoto: false))
                    }
                    .buttonStyle(.plain)
                    .disabled(opening)
                    .accessibilityIdentifier("trip.leg.apple")

                    Button { openGoogle() } label: {
                        Text(isTransit ? L("Google マップで乗り換えを見る", "See transit in Google Maps")
                                       : L("Google マップで経路を見る", "See the route in Google Maps"))
                            .jpPillButton(.outline)
                    }
                    .buttonStyle(.plain)
                    .disabled(opening)
                    .accessibilityIdentifier("trip.leg.google")
                }

                Text(isTransit
                     ? L("どの電車・バス・のりばまで、地図のアプリが出します。見終わったら左上の「journey.photo」で戻れます",
                         "The maps app shows which train or bus and where to board. Tap “journey.photo” at the top left to come back.")
                     : L("見終わったら左上の「journey.photo」で戻れます", "Tap “journey.photo” at the top left to come back."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)

                if !estimates.isEmpty {
                    Text(TripTravel.sourceNote)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
        }
        .onDisappear { task?.cancel() }
    }

    /// 両端を名前で探し直す（並べて探す・待ちを1回分に）
    private func resolve() async -> (MKMapItem, MKMapItem) {
        async let from = SpotDirections.item(name: leg.from.name, coords: leg.from.coords)
        async let to = SpotDirections.item(name: leg.to.name, coords: leg.to.coords)
        return await (from, to)
    }

    /// 🔴 **閉じたら開かない**（探している間に閉じると、押していないものが開く・`TripDayMapView` と同じ）
    private func openApple() {
        guard !opening else { return }
        opening = true
        task = Task { @MainActor in
            defer { opening = false }
            let (origin, target) = await resolve()
            guard !Task.isCancelled else { return }
            MKMapItem.openMaps(with: [origin, target], launchOptions: [
                MKLaunchOptionsDirectionsModeKey: TravelEstimator.launchMode(mode)
            ])
        }
    }

    private func openGoogle() {
        guard !opening else { return }
        opening = true
        task = Task { @MainActor in
            defer { opening = false }
            let (origin, target) = await resolve()
            guard !Task.isCancelled else { return }
            let from = Photo.Coords(lat: origin.placemark.coordinate.latitude, lng: origin.placemark.coordinate.longitude)
            let to = Photo.Coords(lat: target.placemark.coordinate.latitude, lng: target.placemark.coordinate.longitude)
            if let url = TripTravel.googleURL(from: from, to: to, mode: mode) { openURL(url) }
        }
    }
}
