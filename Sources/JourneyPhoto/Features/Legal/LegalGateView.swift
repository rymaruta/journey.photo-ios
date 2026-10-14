import SwiftUI

/// 初回に一度だけ出す同意画面（板 42「はじめる前に」）。
///
/// 上に写真を敷き、左上にロゴ、明朝の見出し、3つの約束を札のアイコンで並べ、
/// 下に固定した白いカプセルで同意する。
///
/// **v2（2026-10-14・板 LegalGate）**: 写真 300 に上 30% の暗がりと下への黒の溶け、眉ラベルは**白**（写真の上・
/// CLAUDE.md）、約束の印は 36 の角丸の箱（シートの面 #161617・角 10）に**白**の線、規約のリンクは真鍮、
/// 主ボタンは白（写真のある画面・`JPPillStyle.main(onPhoto: true)`）。中身（3つの体験と安心の札）は
/// owner が決めた今の文言のまま（板の「はじめる前に」の3段落には戻さない）
struct LegalGateView: View {

    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var hidden: ModerationStore

    /// 上に敷く写真。**同梱しない・同意の前に通信しない**——前に取れた
    /// 公開一覧の控え（`PhotoSnapshotStore`）の先頭を借りる。控えが無ければ
    /// （初めての起動）黒のまま。
    @State private var hero: Photo?

    var body: some View {
        ZStack(alignment: .top) {
            WebTheme.background.ignoresSafeArea()
            // **写真は本文と一緒に流す。** 写真だけ上に留めると、背の低い端末で送ったとき
            // 真鍮の印・字・リンクがグラデーションの無い写真の上を通る（真鍮は黒い地の上だけ）。
            // 写真を上端から敷く形は写真詳細と同じ（ScrollView ごと上の安全域を無視し、
            // 本文はその分だけ下げる）
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 板 v2: ロゴは写真の左上、眉と見出しは写真の下の方（溶けの黒の上）に下げる
                        AppLogo().padding(.top, geo.safeAreaInsets.top + 6).padding(.bottom, LegalGateLayout.logoToHeading)
                        heading
                        experience(L("撮りたい場所を見つける", "Find your next place to shoot"), detail: L("写真と地図から、次に行きたい撮影スポットを探せます。", "Discover your next photo spot through photos and the map."), systemImage: "map")
                        experience(L("写真と撮影情報を残す", "Keep the photo and how you shot it"), detail: L("作品だけでなく、カメラやレンズ、撮影地まで一緒に残せます。", "Keep the camera, lens and shooting location together with your work."), systemImage: "camera")
                        experience(L("旅を、一冊にする", "Turn a journey into a book"), detail: L("旅の前から撮影後まで。写真を旅の記録としてまとめられます。", "From planning to the photos you bring home, keep the whole journey together."), systemImage: "book.closed")
                        safetyNote
                        links
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .top) { heroImage }
                }
                .ignoresSafeArea(edges: .top)
            }
        }.safeAreaInset(edge: .bottom) { agreeButton }.onAppear { pickHero() }
    }

    private var heroImage: some View {
        Color.clear.frame(height: LegalGateLayout.heroHeight).overlay {
            if let hero { AsyncImage(url: hero.gridImageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if case .success(let image) = phase { image.resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hero.gridAlignment) }
            }}
        }.clipped()
        // 板 v2: 上 30% の暗がり（時刻の帯とロゴを読ませる）→ 透明 → 下端の黒（98%）
        .overlay {
            LinearGradient(stops: [.init(color: Color.black.opacity(0.3), location: 0),
                                   .init(color: Color.black.opacity(0), location: 0.3),
                                   .init(color: Color.black, location: 0.98)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 眉ラベルは**白**（写真の上に重なる・CLAUDE.md「白のまま: 規約の眉ラベル」）
            Text("JOURNEY PHOTO").jpEyebrow().foregroundStyle(Color.white.opacity(0.9)).accessibilityHidden(true)
            Text(L("次に撮りたい場所が、見つかる。", "Find the place you want to photograph next."))
                .font(JPFont.display(32, relativeTo: .largeTitle)).foregroundStyle(WebTheme.text).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            Text(L("写真から旅が始まり、旅がまた写真になる。", "Let a photo start the journey — and the journey become your next photo."))
                .font(.subheadline).foregroundStyle(WebTheme.muted2).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 4)
    }

    private func experience(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // 板 v2: 36 の角丸の箱（シートの面・角 10）に白の線の絵。真鍮は規約のリンクに取っておく
            Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(WebTheme.foreground)
                .frame(width: LegalGateLayout.iconTile, height: LegalGateLayout.iconTile)
                .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.s)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(JPFont.bodyEmphasis).foregroundStyle(WebTheme.text)
                Text(detail).font(JPFont.footnote).lineSpacing(4).foregroundStyle(WebTheme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("安心して写真を楽しむために", "For a safe photo community"), systemImage: "shield")
                .font(.footnote.weight(.semibold)).foregroundStyle(WebTheme.accent)
            Text(L("いやがらせ・わいせつ・権利を侵す投稿は認めません。写真から通報・ブロックできます。撮影情報（EXIF）は端末で取り除き、撮影地は約1kmに丸めて保存します。", "Harassment, obscene content and rights violations are not allowed. Photos can be reported and posters blocked. Metadata is removed on device and locations are rounded to about 1 km."))
                .font(JPFont.footnote).lineSpacing(4).foregroundStyle(WebTheme.text2).fixedSize(horizontal: false, vertical: true)
        }.padding(14)
        // 板 v2 の札（surface-1・白 8% の縁・角 14）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    // 押せる高さは**リンクごとに** 44pt（外の枠だけ高くしても、押せるのは文字の高さだけ）
    private var links: some View { HStack(spacing: 20) { Link(destination: LegalConsent.termsURL) { Text(L("利用規約", "Terms of Use")).underline().frame(minHeight: 44).contentShape(Rectangle()) }; Link(destination: LegalConsent.privacyURL) { Text(L("プライバシーポリシー", "Privacy Policy")).underline().frame(minHeight: 44).contentShape(Rectangle()) } }.font(JPFont.body).foregroundStyle(WebTheme.accent) }

    private var agreeButton: some View { Button { consent.accept() } label: { Text(L("同意してJourney Photoをはじめる", "Agree and start Journey Photo")).jpPillButton(LegalGateLayout.agreeStyle) }.buttonStyle(.plain).accessibilityIdentifier("legal.agree").jpBottomBar() }

    private func pickHero() { guard hero == nil, let photos = PhotoSnapshotStore().load() else { return }; hero = photos.first { photo in photo.gridImageURL != nil && !hidden.reportedPhotoIds.contains(photo.id) && !((photo.userId ?? photo.uploadedBy).map { hidden.blockedUserIds.contains($0) } ?? false) } }
}

/// 同意の画面の決まり（v2 の板 LegalGate・2026-10-14）。テストで見張る
enum LegalGateLayout {
    /// 写真の高さ（v2: 300・v1 は 250）
    static let heroHeight: CGFloat = 300
    /// 約束の印の箱（v2: 36・v1 は 44）。飾りなので押せない（44 の決まりの外）
    static let iconTile: CGFloat = 36
    /// ロゴの下から眉ラベルまで（v2: 眉が写真の下端 54 の所＝黒 70% 以上の上に来る。v1 は 58）
    static let logoToHeading: CGFloat = 140
    /// 主ボタン: 写真のある画面なので白（CLAUDE.md）
    static let agreeStyle = JPPillStyle.main(onPhoto: true)
}
