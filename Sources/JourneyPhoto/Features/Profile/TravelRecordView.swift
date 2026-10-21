import SwiftUI

/// マイページの「旅の記録」（2026-10-14 owner「妥協なしでこだわりたい」・案 H1「星図」
/// https://claude.ai/artifact/YR7SiY5op4gmCeQ8gxFhXZ）。
///
/// 以前は「訪れた国・地域 3 · 写真をつないだ距離 74,499 km」の小さな1行で、名前が先・数字が小さく、
/// 上の数の段（数字が主）と書き方が割れていた（owner「ちょっと微妙」）。いま:
///
/// - 真鍮の眉ラベル「旅の記録」と、右へ消えていく真鍮の細線。右端に一番古い写真の年
/// - **数字が主**: 距離は細い SF の等幅数字（30pt）に小さな km、国・地域は右に（20pt）
/// - **写真をつないだ線**: 距離と同じ写真・同じ順に撮影地を結んだ形（`TravelRoute`）を、
///   ごく薄い経度・緯度の格子の上に。古い区間ほど薄く、一番新しい点だけ明るい真鍮。
///   画面に出たとき一度だけ古い順に引き、最後の点の光が一度だけ広がる（視差効果を減らす人は動かさない）
///
/// 真鍮は黒い地の上だけ（マイページは黒地）。数字は白のまま（真鍮は合図と飾りの色）。
/// 押すと、それぞれの数え方の説明（呼ぶ側の知らせ）
struct TravelRecordView: View {

    /// 写真をつないだ距離（km）。0 なら距離と線を出さない
    let kilometers: Double
    /// 訪れた国・地域の名前（初めて訪れた順）。空なら国を出さない
    let countries: [String]
    /// 撮影地（距離と同じ写真・同じ順）
    let coordinates: [Photo.Coords]
    /// 一番古い写真の年
    let firstYear: Int?
    let onDistanceTap: () -> Void
    let onCountriesTap: () -> Void
    /// 写真をつないだ線を出すか（畳んだ状態は `TravelRecordSection` が持つ・2026-10-21）
    var routeShown: Bool = true
    /// 線の開け閉め。nil なら開け閉めの印を出さない（いつも `routeShown` のまま）
    var onRouteToggle: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 線を引いた割合（0〜1）。画面に出たときに1度だけ伸ばす
    @State private var drawn: Double = 0
    /// 最後の点の光（広がり 0〜1・濃さ）。線を引き終えてから1度だけ
    @State private var haloScale: Double = 0
    @State private var haloOpacity: Double = 0
    @State private var played = false

    /// 線の高さ（板 H1 の 64pt に、上下の弧のふくらみの分を足した）
    static let routeHeight: CGFloat = 100

    private var shape: TravelRoute.Shape? {
        kilometers > 0 ? TravelRoute.shape(of: coordinates) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: JPSpace.s) {
                eyebrow
                if shape != nil, let onRouteToggle { routeToggle(onRouteToggle) }
            }
            HStack(alignment: .top, spacing: 12) {
                if kilometers > 0 { distanceBlock }
                Spacer(minLength: 0)
                if !countries.isEmpty { countriesBlock }
            }
            if routeShown, let shape {
                Button(action: onDistanceTap) {
                    route(shape)
                        .frame(height: Self.routeHeight)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                .onAppear(perform: play)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 眉ラベル

    /// 眉ラベルは土台の `JPEyebrowLine`（v2 の板 02・字は SF 600・字間 0.14em・真鍮 55% から消える線）。
    /// 2026-10-14 判断: 以前はここに同じ形（11pt regular・字間 2・線 60%）を書いていたので、土台の部品に寄せた
    private var eyebrow: some View {
        JPEyebrowLine(L("旅の記録", "TRAVEL LOG"),
                      spoken: L("旅の記録", "Travel log"),
                      trailing: firstYear.map { L("\(String($0)) 年から", "Since \(String($0))") })
    }

    /// 線の開け閉め（眉ラベルの右・「線を見る ⌄」「畳む ⌃」）。見た目は「すべて見る ›」（`MoreLink`）と同じ
    /// text-2 の 13pt。押せる高さは 44pt、並びの上では字の高さのまま（押せる範囲の形だけ広げる）
    private func routeToggle(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: JPSpace.xxs) {
                Text(routeShown ? L("畳む", "Hide") : L("線を見る", "Show route"))
                Image(systemName: routeShown ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(JPFont.footnote)
            .foregroundStyle(WebTheme.text2)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: WebTheme.minTapTarget, alignment: .trailing)
            // 押せる範囲の形だけを 44pt へ広げる（並びの高さは字のまま）。負の余白で張り出すと、
            // 字を大きくしたとき下の数字の行に重なる（2026-10-21 判断・確かめ役の見直し）
            .contentShape(Rectangle().inset(by: -Self.toggleTapSlack))
        }
        .buttonStyle(.plain)
        // **読み上げには出さない。** 線そのものが読み上げに乗らない（数字と数え方の説明が同じ中身を
        // 読む）ので、開け閉めだけ読ませても何も変わらない（2026-10-21 判断）
        .accessibilityHidden(true)
        .accessibilityIdentifier("profile.travelRecord.routeToggle")
    }

    /// 開け閉めの字（13pt・行の高さ約 18）を 44pt にする、押せる範囲の広げ幅（上下左右）
    nonisolated static let toggleTapSlack: CGFloat = 13

    // MARK: - 数字

    private var distanceBlock: some View {
        Button(action: onDistanceTap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(TravelDistance.formatted(kilometers))
                        // 板の 30 は Dynamic Type の段の 28 で出す（`JPTypeScale.figureLarge` の注記）
                        .font(JPFont.figureLarge)
                        .foregroundStyle(Color.white)
                    Text("km")
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                }
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: CGFloat(JPTypeScale.figureLarge)))
                Text(L("写真をつないだ距離", "Distance between photos"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .frame(minHeight: WebTheme.minTapTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("写真をつないだ距離 \(TravelDistance.formatted(kilometers)) キロメートル",
                              "Distance between photos, \(TravelDistance.formatted(kilometers)) kilometers"))
        .accessibilityHint(L("数え方を表示", "Shows how this is counted"))
    }

    private var countriesBlock: some View {
        Button(action: onCountriesTap) {
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(countries.count)")
                    .font(JPFont.number(JPTypeScale.figureMedium, weight: JPFont.figureWeight, relativeTo: .title3))
                    .foregroundStyle(Color.white)
                    // 距離の数字（28pt）と下の線をそろえる
                    .padding(.top, 8)
                Text(L("か国・地域", countries.count == 1 ? "country or region" : "countries & regions"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Text(TravelRoute.countriesLine(countries))
                    .font(.caption)
                    // 白 42% だと黒地で約 3.9:1 で 12pt に足りない。text-3（黒地の不透明の灰）
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .multilineTextAlignment(.trailing)
            .frame(minHeight: WebTheme.minTapTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("訪れた国・地域 \(countries.count)、\(countries.joined(separator: "、"))",
                              "Countries and regions visited, \(countries.count): \(countries.joined(separator: ", "))"))
        .accessibilityHint(L("数え方を表示", "Shows how this is counted"))
    }

    // MARK: - 写真をつないだ線

    private func route(_ shape: TravelRoute.Shape) -> some View {
        TravelRouteCanvas(shape: shape, progress: drawn, haloScale: haloScale, haloOpacity: haloOpacity)
    }

    /// 画面に出たときに1度だけ線を引く
    private func play() {
        guard !played else { return }
        played = true
        if reduceMotion {
            drawn = 1
            return
        }
        withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 1.6)) { drawn = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            haloOpacity = 0.55
            withAnimation(.easeOut(duration: 1.8)) {
                haloScale = 1
                haloOpacity = 0
            }
        }
    }
}

/// 写真をつないだ線の絵。**引いた割合（`progress`）で毎コマ描き直す**（`Animatable`）——点は線が
/// 届いたときに出す。式の結果だけを渡すと、点が線の伸びと関係なく一斉に薄く出てしまう
private struct TravelRouteCanvas: View, Animatable {
    let shape: TravelRoute.Shape
    var progress: Double
    let haloScale: Double
    let haloOpacity: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// 一番新しい点の明るい真鍮（`ProMarkColors.irisStops` の明るい端と同じ）
    private static let latest = ProMarkColors.color(0xF3DCA6)

    var body: some View {
        GeometryReader { proxy in
            // 上下は弧のふくらみの分を空ける（行きは上・帰りは下へふくらむ）
            let inset: CGFloat = 6, band: CGFloat = 26
            let rect = CGRect(x: inset, y: band,
                              width: max(1, proxy.size.width - inset * 2),
                              height: max(1, proxy.size.height - band * 2))
            let points = shape.points.map { CGPoint(x: rect.minX + $0.x * rect.width,
                                                    y: rect.minY + $0.y * rect.height) }
            let last = max(1, points.count - 1)
            ZStack {
                // 経度・緯度の格子（白 7%・0.5pt）。線の通る範囲だけ
                Path { path in
                    for x in shape.meridians {
                        let px = rect.minX + CGFloat(x) * rect.width
                        path.move(to: CGPoint(x: px, y: 0))
                        path.addLine(to: CGPoint(x: px, y: proxy.size.height))
                    }
                    for y in shape.parallels {
                        let py = rect.minY + CGFloat(y) * rect.height
                        path.move(to: CGPoint(x: 0, y: py))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: py))
                    }
                }
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)

                // 線。区間ごとに上へふくらむ弧（航路）。古い区間ほど薄い真鍮
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    let controls = TravelRoute.arcControls(shape.points, size: rect.size, band: band)
                    for index in 1..<points.count {
                        let c = controls[index - 1]
                        path.addQuadCurve(to: points[index],
                                          control: CGPoint(x: rect.minX + c.x * rect.width,
                                                           y: rect.minY + c.y * rect.height))
                    }
                }
                .trim(from: 0, to: progress)
                .stroke(LinearGradient(stops: [.init(color: WebTheme.accent.opacity(0.35), location: 0),
                                               .init(color: WebTheme.accent, location: 1)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                // 点。線が届いたものから出す。古いほど薄い
                Path { path in
                    for index in 0..<(points.count - 1) where progress >= Double(index) / Double(last) {
                        path.addEllipse(in: CGRect(x: points[index].x - 1.3, y: points[index].y - 1.3,
                                                   width: 2.6, height: 2.6))
                    }
                }
                .fill(WebTheme.accent.opacity(0.8))

                // 一番新しい写真。明るい真鍮の点と、一度だけ広がる光
                if let newest = points.last {
                    Circle()
                        .stroke(Self.latest, lineWidth: 0.8)
                        .frame(width: 4 + 14 * haloScale, height: 4 + 14 * haloScale)
                        .opacity(haloOpacity)
                        .position(x: newest.x, y: newest.y)
                    Circle()
                        .fill(Self.latest)
                        .frame(width: 4, height: 4)
                        .position(x: newest.x, y: newest.y)
                        .opacity(progress >= 1 ? 1 : 0)
                }
            }
        }
    }
}
