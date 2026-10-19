import SwiftUI
import UIKit

/// 自分のキャンプ場（板「写真で作るキャンプ場」1 自分のキャンプ場・Main）。
///
/// - 眉ラベル「<名前> のキャンプ場 · <育ち>」・明朝の題（キャンプ場の名前）・「空の色は、その時刻に撮った写真から」
/// - 島（370 × 360・指で回す）・「指で回すと…」・時刻 4 と季節 4 の丸い札（選んでいるものは真鍮の縁と字）
/// - 主ボタン「撮って加える」（写真の無い画面＝真鍮の塗りに墨）と、友達のキャンプ場の丸
/// - 入口はマイページの旅の記録の「旅のトランク」の下の行（`MyPageView.tripToolsCard`）
///
/// 板に無いもの（2026-10-18 判断）: 左上の戻る（キャンプ場の他の板と同じ形）、右上の部品図鑑（新しく集めた数の真鍮の
/// 件数バッジ）、題を押すと育ちの画面。友達のキャンプ場を訪ねる・薪をくべるはサーバーが要るので「近日」の案内だけ
struct CampHomeView: View {

    var ownerName: String?

    @ObservedObject private var store = CampStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var time: CampTime = CampTime(slot: CampClock.slot(of: Date()))
    @State private var season: CampSeason = CampClock.season(of: Date())
    @State private var angle = CampAngle.resting
    @State private var capturing = false
    @State private var showsDex = false
    @State private var showsGrow = false
    @State private var showsFriends = false
    @State private var justPlaced: String?
    @State private var previewPose = 0
    @State private var focus: CampFocus = .all
    @State private var stageOverride: CampStage?
    @State private var placingCutout: CampCutoutRecord?
    @State private var glow: UInt32 = 0x16140F

    var body: some View {
        GeometryReader { geo in
            let islandHeight = min(360, max(260, Double(geo.size.height) - 404))
            VStack(spacing: 0) {
                header
                CampIslandView(options: options, angle: angle, skyColors: store.sky(for: time)?.colors, glow: glow,
                               justPlaced: justPlaced, images: CampStoreImages.loader(store), onAngle: { angle = $0 })
                    .frame(height: CGFloat(islandHeight))
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .accessibilityIdentifier("camp.home.island")
                Text(L("指で回すと、島の裏の岩と、焚き火の向こうが見えます",
                       "Turn it with your finger to see the rock below and the far side of the fire"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                chips(CampTime.allCases, selected: time, label: L("時刻", "Time"), name: \.name, id: "camp.home.time") { time = $0 }
                    .padding(.top, 12)
                chips(CampSeason.allCases, selected: season, label: L("季節", "Season"), name: \.name, id: "camp.home.season") { season = $0 }
                    .padding(.top, 8)
                if CampPreview.showsViews { previewViewsButton.padding(.top, 8) }
                Spacer(minLength: 12)
                if let waiting = store.unplaced.first { unplacedRow(waiting) }
                bottom
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { WebTheme.background.ignoresSafeArea() }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                }
                .accessibilityLabel(L("戻る", "Back"))
                .accessibilityIdentifier("camp.home.back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsDex = true } label: { dexMark }
                    .accessibilityLabel(CampDexText.title)
                    .accessibilityValue(store.unseen.isEmpty ? "" : CampDexText.newCount(store.unseen.count))
                    .accessibilityIdentifier("camp.home.dex")
            }
        }
        .navigationDestination(isPresented: $showsDex) { CampDexView() }
        .navigationDestination(isPresented: $showsGrow) { CampGrowView(ownerName: ownerName) }
        .fullScreenCover(isPresented: $capturing) {
            CampCaptureView(ownerName: ownerName) { placedId in
                capturing = false
                if let placedId { justPlaced = placedId }
            }
        }
        .fullScreenCover(item: $placingCutout) { cutout in
            CampPlaceView(cutout: cutout) { placedId in
                placingCutout = nil
                if let placedId { justPlaced = placedId }
            }
        }
        .sheet(isPresented: $showsFriends) { friendsNotice }
        .task { await CampStoreImages.preparePreviewIfNeeded(store) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camp.home")
    }

    private var stage: CampStage { stageOverride ?? store.stage }

    private var options: CampSceneOptions {
        CampSceneOptions(stage: stage, season: season, time: time, focus: focus,
                         cutouts: store.placed.compactMap { c in c.spot.map { CampPlacedCutout(id: c.id, layers: c.layers, spot: $0) } })
    }

    // MARK: - 見出し

    private var header: some View {
        Button { showsGrow = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("\(ownerLabel) のキャンプ場 · \(stage.name)", "\(ownerLabel)\u{2019}s campsite · \(stage.name)"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .lineLimit(1)
                Text(store.displayName(owner: ownerName))
                    .font(JPFont.display(28, relativeTo: .title))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L("空の色は、その時刻に撮った写真から", "The sky takes its color from photos you took at that hour"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("育ちの様子を見る", "See how your campsite grows"))
        .accessibilityIdentifier("camp.home.header")
    }

    private var ownerLabel: String {
        let name = (ownerName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? L("わたし", "My") : name
    }

    /// 図鑑の印（新しく集めた部品があれば真鍮の件数バッジ・真鍮＋墨＋黒 2px の縁）
    private var dexMark: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WebTheme.text)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            if !store.unseen.isEmpty {
                Text("\(store.unseen.count)")
                    .font(JPFont.number(11, weight: .bold))
                    .foregroundStyle(WebTheme.accentText)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background { Capsule().fill(WebTheme.accent) }
                    .overlay(Capsule().strokeBorder(Color.black, lineWidth: 2))
                    .offset(x: -2, y: 4)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - 札

    /// 時刻・季節の丸い札（板: 高さ 44・最小 56・左右 14・縁 1・選んでいるものは真鍮の縁と #F3DCA6 の字）
    private func chips<T: Hashable>(_ items: [T], selected: T, label: String, name: KeyPath<T, String>, id: String,
                                    pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.8)) { pick(item) }
                } label: {
                    Text(item[keyPath: name])
                        .font(.system(size: 14))
                        .foregroundStyle(on ? CampStyle.highlight : WebTheme.text)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 56, minHeight: 44)
                        .overlay(Capsule().strokeBorder(on ? WebTheme.accent : WebTheme.line, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier(id)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: - 下

    /// まだ立てていない切り絵（「あとで置く」・撮る画面を途中で閉じた）
    private func unplacedRow(_ cutout: CampCutoutRecord) -> some View {
        Button { placingCutout = cutout } label: {
            HStack(spacing: 8) {
                Text(L("まだ立てていない切り絵 \(store.unplaced.count) 枚", "\(store.unplaced.count) cutouts waiting to stand"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background { RoundedRectangle(cornerRadius: 12).fill(CampStyle.card) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityIdentifier("camp.home.unplaced")
    }

    private var bottom: some View {
        HStack(spacing: 8) {
            Button { capturing = true } label: {
                Text(L("撮って加える", "Shoot and add"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background { Capsule().fill(WebTheme.accentFill) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camp.home.capture")
            Button { showsFriends = true } label: {
                CampTentGlyph()
                    .stroke(WebTheme.text, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                    .frame(width: 50, height: 50)
                    .overlay(Circle().strokeBorder(WebTheme.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("友達のキャンプ場", "Friends\u{2019} campsites"))
            .accessibilityIdentifier("camp.home.friends")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 38)
    }

    /// 友達のキャンプ場（サーバーが要る・近日）
    private var friendsNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            JPSectionHeading(eyebrow: L("近日", "Coming soon"), title: L("友達のキャンプ場を訪ねる", "Visit friends\u{2019} campsites"))
            Text(L("友達のキャンプ場を訪ねて、焚き火に薪を一本くべられるようになります。くべた人の名前が薪に残ります。サーバーの用意ができるまで、もう少しお待ちください。",
                   "Soon you can visit friends\u{2019} campsites and add a log to their fire. Your name stays on the log. This needs our server, so please wait a little longer."))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button { showsFriends = false } label: {
                Text(Labels.Common.close).jpPillButton(.outline)
            }
            .accessibilityIdentifier("camp.friends.close")
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationBackground(WebTheme.sheet)
    }

    /// 画面写真のための 12 の向き（Debug の起動の鍵 `-JPPreviewCampViews` だけ）
    private var previewViewsButton: some View {
        Button {
            let views = CampView.all()
            let v = views[previewPose % views.count]
            previewPose += 1
            focus = v.focus
            time = v.time
            season = v.season
            stageOverride = v.stage
            glow = v.glow
            angle = v.angle
        } label: {
            Text(L("次の向き（\(previewPose % 12 + 1) / 12）", "Next view (\(previewPose % 12 + 1) / 12)"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("camp.views.next")
        .accessibilityValue("pose-\(previewPose)")
    }
}

/// キャンプ場の画面の色（板の値。デザインシステムの真鍮の明るい側 #F3DCA6）
enum CampStyle {
    static let highlight = CampPalette.color(0xF3DCA6)
    static let card = CampPalette.color(0x121212)
    static let cardSelected = CampPalette.color(0x201B11)
    static let tile = CampPalette.color(0x151515)
}

/// 友達のキャンプ場の印（板: 24 の枠の三角と、扉の小さな三角）
struct CampTentGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = Double(rect.width) / 24, x0 = Double(rect.minX), y0 = Double(rect.minY)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x0 + x * k, y: y0 + y * k) }
        var path = Path()
        path.move(to: p(3, 20))
        path.addLine(to: p(12, 4))
        path.addLine(to: p(21, 20))
        path.closeSubpath()
        path.move(to: p(12, 20))
        path.addLine(to: p(9, 14))
        path.addLine(to: p(15, 14))
        path.closeSubpath()
        return path
    }
}

/// 入れ物の切り絵の紙の絵を読む口
enum CampStoreImages {
    @MainActor
    static func loader(_ store: CampStore) -> CampCutoutImages {
        let dir = store.directory
        return { id, layer in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(id)-\(layer).png")) else { return nil }
            return UIImage(data: data)
        }
    }

    /// 見本の中身を入れる（Debug の起動の鍵だけ・画面写真の試験）
    @MainActor
    static func preparePreviewIfNeeded(_ store: CampStore) async {
        guard CampPreview.usesSample, store.cutouts.isEmpty else { return }
        await CampCutter.preparePreview(store)
    }
}
