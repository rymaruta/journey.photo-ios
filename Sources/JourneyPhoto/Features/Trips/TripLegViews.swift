import SwiftUI
import MapKit

/// 場所と場所の間の1行（移動の見込み・2026-11-10 owner の要望・札 #521）。
///
/// 🔴 **場所の行とつなぐ形**（2026-11-11 owner「UI もブラッシュアップして」・実機の写真で区間の行が場所の行と
/// 見分けにくかった）: 番号の丸の列に縦の線を通して前後の場所をつなぎ、右に**手段の記号と時間を1行**で出す。
/// 時間は SF の等幅数字。行の高さは押せる 44pt。区切り線で挟まない（つなぎに見えるように）。
///
/// 状態はどれも同じ並び（記号 → 1行の字）: 聞いている（時計）・圏外（電波なし）・返らない（地図）・
/// 長い移動（飛行機・まっすぐの距離の概数・所要時間は出さない）・見込み（手段ごとの記号と時間）。
/// 日をまたぐ区間は字の頭に「前の日の〇〇から」。
///
/// **押すと、その区間の両端で Apple のマップを開く**（2026-11-12 判断・owner「Apple の地図を開いたり、何線に乗ればいいかはできる？」）。
/// 何線に乗るか・乗り換え・時刻は Apple のマップの公共交通の経路が出す（アプリの中では出せない・`TripTravel.mapsMode`）。
/// 開く手段は字の先頭に出し（`TripTravel.ordered`）、右端の外へ出る矢印（真鍮）で「地図のアプリが開く」と分かるように。
/// 押す回数: 前は 行 → シート → 「Apple のマップで乗り換えを見る」の 2 回。いまは行の 1 回。
/// 出る時刻の目安と Google マップは右端の「i」（区間のシート `TripLegSheet`・1 回）。
/// 長い移動（国をまたぐ・海を越える）は Apple のマップに経路が無いので、行を押すと Google フライトのシート（前と同じ）
struct TripLegRow: View {
    let leg: TripTravel.Leg
    let estimates: [TripTravel.Estimate]
    /// 聞き終えた（返らなかった手段も含めて）
    let settled: Bool
    let offline: Bool
    let throttled: Bool
    /// 区間のシート（出る時刻の目安・Google マップ。長い移動は Google フライト）
    let details: () -> Void

    /// 探している間（名前で探し直す・最大で数秒）。続けて押しても1回だけ開く
    @State private var opening = false
    @State private var openTask: Task<Void, Never>?

    /// 縦の線の太さ（番号の丸の線と同じ 1.5）・濃さ（白 18%）
    nonisolated static let connectorWidth: CGFloat = TripStyle.stopNumberStroke
    nonisolated static let connectorOpacity = 0.18

    enum Look: Equatable {
        case loading, offline, unavailable, long, estimates
    }

    /// 出す形（`TripTravel.showsAsLong` が先・2026-11-11）
    nonisolated static func state(leg: TripTravel.Leg, estimates: [TripTravel.Estimate], settled: Bool,
                                  offline: Bool, throttled: Bool) -> Look {
        if TripTravel.showsAsLong(leg, estimates: estimates, settled: settled) { return .long }
        if !estimates.isEmpty { return .estimates }
        if offline { return .offline }
        if settled || throttled { return .unavailable }
        return .loading
    }

    private var state: Look {
        Self.state(leg: leg, estimates: estimates, settled: settled, offline: offline, throttled: throttled)
    }

    /// Apple のマップを開く手段
    private var mode: TripTravel.Mode { TripTravel.mapsMode(estimates, leg: leg, settled: settled) }

    /// 行を押したとき。長い移動はシート、ほかは Apple のマップ
    private func tap() {
        guard state != .long else { details(); return }
        guard !opening else { return }
        opening = true
        let mode = mode
        // 圏外では名前で探し直さない（返らずに待つだけ）。丸めた座標に名前を付けて渡す
        let search = !offline
        openTask = Task { @MainActor in
            defer { opening = false }
            await TripLegMaps.open(leg, mode: mode, search: search)
        }
    }

    /// 縦の線と行の高さ（UI テストの見本のときだけ読み上げの値に出して数で確かめる・Debug）
    @State private var connectorHeight: CGFloat = 0
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Button(action: tap) {
                HStack(spacing: JPSpace.s) {
                    // 番号の丸の列（縦の線は下の `background` で行の高さいっぱいに描く）
                    Color.clear
                        .frame(width: TripStyle.stopNumberSide, height: 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        // 日をまたぐ区間は、どこからの区間かを頭に（「前の日の伏見稲荷大社から」）
                        if leg.crossesDay {
                            Text(TripTravel.crossDayLabel(leg))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(1)
                        }
                        line
                    }
                    .padding(.vertical, 6)
                    Spacer(minLength: 0)
                    trailingMark
                }
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(opening)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.spoken(leg: leg, estimates: shownEstimates, offline: offline, state: state))
            .accessibilityHint(Self.hint(state, mode: mode))
            .accessibilityValue(measuredValue)
            .accessibilityIdentifier("trip.leg")

            // 出る時刻の目安・Google マップ（区間のシート）。長い移動は行そのものがシートを開くので出さない
            if state != .long {
                Button(action: details) {
                    Image(systemName: "info.circle")
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("区間の案内（出る時刻の目安、Google マップ）", "Leg details (when to leave, Google Maps)"))
                .accessibilityIdentifier("trip.leg.more")
            }
        }
        // 🔴 **縦の線は行の高さに合わせて描く**（確かめ役の指摘: ScrollView の中では `maxHeight: .infinity` が
        // 行の高さまで伸びない見込みだった）。番号の丸の列の真ん中に、上の端から下の端まで
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(Self.connectorOpacity))
                .frame(width: Self.connectorWidth)
                .frame(maxHeight: .infinity)
                .frame(width: TripStyle.stopNumberSide)
                .measuringHeight(Self.measures) { connectorHeight = $0 }
                .accessibilityHidden(true)
        }
        .measuringHeight(Self.measures) { rowHeight = $0 }
        .onDisappear { openTask?.cancel() }
    }

    /// 右端の印。Apple のマップへ出る行は外へ出る矢印（真鍮・黒地の上のリンク）、探している間は回る印。
    /// 長い移動はシートが開くので山形
    @ViewBuilder
    private var trailingMark: some View {
        if opening {
            ProgressView()
                .tint(WebTheme.accent)
                .accessibilityHidden(true)
        } else if state == .long {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
        }
    }

    /// 行に出す見込み（開く手段を先頭に）
    private var shownEstimates: [TripTravel.Estimate] { TripTravel.ordered(estimates, first: mode) }

    /// 高さを測るのは見本のときだけ（Debug・ふだんは描き直しのたびに状態を書かない）
    nonisolated static var measures: Bool {
        #if DEBUG
        return TripPlanFixture.isOn
        #else
        return false
        #endif
    }

    /// 見本のときだけ「line=44.0 row=44.0」（UI テストが線の高さを数で見る）。ふだんは空
    private var measuredValue: String {
        #if DEBUG
        if TripPlanFixture.isOn {
            return String(format: "line=%.1f row=%.1f", connectorHeight, rowHeight)
        }
        #endif
        return ""
    }

    /// 押すと何が開くか（長い移動は Google フライトのシート・ほかは Apple のマップ）
    nonisolated static func hint(_ state: Look, mode: TripTravel.Mode) -> String {
        state == .long
            ? L("Google フライトで便を探す画面を出します", "Shows a way to search Google Flights.")
            : TripTravel.mapsHint(mode)
    }

    /// 1行（記号 → 字）。見込みは手段ごとに記号と等幅数字の時間を並べる
    @ViewBuilder
    private var line: some View {
        switch state {
        case .estimates:
            HStack(spacing: JPSpace.s) {
                ForEach(shownEstimates, id: \.mode) { estimate in
                    HStack(spacing: 4) {
                        Image(systemName: estimate.mode.symbol)
                            .font(JPFont.caption)
                            .accessibilityHidden(true)
                        Text(estimate.mode.label)
                            .font(JPFont.caption)
                        Text(TripTravel.duration(estimate.seconds))
                            .font(JPFont.mono(12, medium: true))
                    }
                    // 開く手段（先頭）は明るく、ほかは控えめに（並びでも伝える・色だけに頼らない）
                    .foregroundStyle(estimate.mode == mode ? WebTheme.text : WebTheme.muted2)
                    .lineLimit(1)
                }
            }
        case .long:
            note(TripTravel.longLine(leg), symbol: "airplane", strong: true)
        case .offline:
            note(TripTravel.offlineNote, symbol: "wifi.slash")
        case .unavailable:
            note(TripTravel.openInMaps, symbol: "map")
        case .loading:
            note(L("移動の目安を調べています", "Checking travel time…"), symbol: "clock")
        }
    }

    private func note(_ text: String, symbol: String, strong: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(JPFont.caption).accessibilityHidden(true)
            Text(text).font(JPFont.caption).lineLimit(1)
        }
        .foregroundStyle(strong ? WebTheme.muted2 : WebTheme.faint)
    }

    nonisolated static func spoken(leg: TripTravel.Leg, estimates: [TripTravel.Estimate], offline: Bool,
                                   state: Look? = nil) -> String {
        let route = leg.crossesDay
            ? L("前の日の\(leg.from.name)から\(leg.to.name)", "\(leg.from.name) (previous day) to \(leg.to.name)")
            : L("\(leg.from.name)から\(leg.to.name)", "\(leg.from.name) to \(leg.to.name)")
        // 長い移動は見えている形（`state`）で言う（国内で返らずに倒れた区間も「長い移動」と読む）
        if state == .long || TripTravel.skipsDirections(leg) { return "\(route)、\(TripTravel.longLine(leg))" }
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
/// - 主: 「Apple のマップで乗り換えを見る」（`MKMapItem.openMaps`・その区間の手段・行を押したときと同じ `TripLegMaps`）。副: 「Google マップで乗り換えを見る」
///   （Maps URLs・鍵は要らない・`travelmode`）。選ぶのは2つのボタンだけ。設定は作らない
///
/// 両端は名前で探し直してから渡す（索引の座標は約1kmに丸めてある・`SpotDirections`）
struct TripLegSheet: View {
    let leg: TripTravel.Leg
    let estimates: [TripTravel.Estimate]
    /// Apple のマップ・Google マップを開く手段（行と同じ `TripTravel.mapsMode`）
    let mode: TripTravel.Mode
    /// 行き先の日の日の出・日の入り（端末の計算）
    let sun: TripDraft.Sun?
    /// 行き先の時間帯の案内（「夕方の斜光」なら、その始まりに間に合う時刻で言う）
    let destinationTimes: [String]
    /// 前の場所の時間帯の案内（見てから出ると間に合わないときに一言添える）
    var previousTimes: [String] = []
    /// 長い移動（国をまたぐ・海を越える・2026-11-11）。Apple のマップには経路が無いので、Google フライトだけを出す
    var long = false
    /// 行き先の日の日付（Google フライトに渡す）
    var date: String? = nil

    @Environment(\.openURL) private var openURL
    @State private var opening = false
    @State private var task: Task<Void, Never>?

    private var isTransit: Bool { mode == .transit }

    var body: some View {
        if long {
            longBody
        } else {
            regularBody
        }
    }

    /// 長い移動（2026-11-11 owner「日本からブラジルとか無理じゃん」）: 所要時間は出さない（推定の数を作らない）。
    /// 押せるのは「Google フライトで探す」1つ（鍵の要らない検索の URL・出発と到着の都市名・日程の日付）。
    /// Apple のマップは経路を出せないので出さない
    private var longBody: some View {
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
                HStack(spacing: JPSpace.xs) {
                    Image(systemName: "airplane").accessibilityHidden(true)
                    Text(TripTravel.longLine(leg)).font(JPFont.body)
                }
                .foregroundStyle(WebTheme.text)
                .padding(JPSpace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .jpCardFace()
                Button {
                    if let url = TripTravel.googleFlightsURL(leg, date: date) { openURL(url) }
                } label: {
                    Text(L("Google フライトで探す", "Search Google Flights"))
                        .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip.leg.flights")
                Text(TripTravel.longNote(leg))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
        }
    }

    private var regularBody: some View {
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
                     ? L("どの電車、バス、のりばまで、地図のアプリが出します。見終わったら左上の「journey.photo」で戻れます",
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

    /// 🔴 **閉じたら開かない**（探している間に閉じると、押していないものが開く・`TripDayMapView` と同じ）
    private func openApple() {
        guard !opening else { return }
        opening = true
        let mode = mode
        task = Task { @MainActor in
            defer { opening = false }
            await TripLegMaps.open(leg, mode: mode, search: true)
        }
    }

    private func openGoogle() {
        guard !opening else { return }
        opening = true
        task = Task { @MainActor in
            defer { opening = false }
            let (origin, target) = await TripLegMaps.resolve(leg, search: true)
            guard !Task.isCancelled else { return }
            let from = Photo.Coords(lat: origin.placemark.coordinate.latitude, lng: origin.placemark.coordinate.longitude)
            let to = Photo.Coords(lat: target.placemark.coordinate.latitude, lng: target.placemark.coordinate.longitude)
            if let url = TripTravel.googleURL(from: from, to: to, mode: mode) { openURL(url) }
        }
    }
}

/// 区間の両端で Apple のマップを開く（区間の行・区間のシートで共通・2026-11-12）。
///
/// `MKMapItem.openMaps(with: [出発, 到着], launchOptions: [手段])`: Apple の文書「2つ渡すと、1つ目から2つ目への経路」。
/// 手段の鍵 `MKLaunchOptionsDirectionsModeTransit` で公共交通の経路が開き、何線か・乗り換え・時刻は地図のアプリが出す。
/// **出発の時刻は渡せない**（開く口の鍵にも、Apple の地図の URL の `directions` の引数にも、時刻が無い）。
/// 両端は名前で探し直してから渡す（索引の座標は約1kmに丸めてある・`SpotDirections`）
@MainActor
enum TripLegMaps {

    /// 両端（名前で探し直す・並べて探す・待ちを1回分に）。`search == false`（圏外）は丸めた座標に名前を付けたもの
    static func resolve(_ leg: TripTravel.Leg, search: Bool) async -> (MKMapItem, MKMapItem) {
        guard search else {
            return (SpotDirections.rounded(name: leg.from.name, coords: leg.from.coords),
                    SpotDirections.rounded(name: leg.to.name, coords: leg.to.coords))
        }
        async let from = SpotDirections.item(name: leg.from.name, coords: leg.from.coords)
        async let to = SpotDirections.item(name: leg.to.name, coords: leg.to.coords)
        return await (from, to)
    }

    /// 開く手段の鍵（Apple の地図の `launchOptions`）
    nonisolated static func launchOptions(_ mode: TripTravel.Mode) -> [String: Any] {
        [MKLaunchOptionsDirectionsModeKey: TravelEstimator.launchMode(mode)]
    }

    /// 🔴 **探している間に画面を離れた（取り消された）回は開かない**（押していないものが開いたように見える・`SpotDirections`）
    static func open(_ leg: TripTravel.Leg, mode: TripTravel.Mode, search: Bool) async {
        let (origin, target) = await resolve(leg, search: search)
        guard SpotDirections.shouldOpen(cancelled: Task.isCancelled, stillWanted: true) else { return }
        #if DEBUG
        // UI テストの見本では地図のアプリへ出ない（試験の画面から出てしまう）。開いた手段を数えに残す
        if TripPlanFixture.isOn {
            TripPlanFixtureCounter.shared.mark("M:\(mode.rawValue)")
            return
        }
        #endif
        MKMapItem.openMaps(with: [origin, target], launchOptions: launchOptions(mode))
    }
}

extension View {
    /// 高さを測る（`enabled` のときだけ見張りを付ける・見本の UI テスト用）
    @ViewBuilder
    fileprivate func measuringHeight(_ enabled: Bool, _ action: @escaping (CGFloat) -> Void) -> some View {
        if enabled {
            onGeometryChange(for: CGFloat.self) { $0.size.height } action: { action($0) }
        } else {
            self
        }
    }
}
