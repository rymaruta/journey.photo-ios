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

    /// 上に敷く写真。**アプリに同梱した作例写真から選ぶ**（`LegalGateLayout.heroAsset`・2026-10-21 判断）。
    /// 前は公開一覧の控え（`PhotoSnapshotStore`）の先頭を借りていて、スーパーの袋入りのぶどうが
    /// いちばん大きく出た（run 609 の 01）。新しく入れた直後（控えが空）は黒のままだった。
    /// 同梱の写真なら、同意の前に通信せず、初めての起動でも必ず出る
    private let heroAsset = LegalGateLayout.heroAsset()

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
                        experience(L("撮りたい場所を見つける", "Find your next place to shoot"), detail: L("写真と地図から、次に行きたい観光スポットを探せます。", "Discover your next photo spot through photos and the map."), systemImage: "map")
                        experience(L("写真と撮影情報を残す", "Keep the photo and how you shot it"), detail: L("作品だけでなく、カメラやレンズ、撮影地まで一緒に残せます。", "Keep the camera, lens and shooting location together with your work."), systemImage: "camera")
                        experience(L("旅を、一冊にする", "Turn a journey into a book"), detail: L("旅の前から撮影後まで。写真を旅の記録としてまとめられます。", "From planning to the photos you bring home, keep the whole journey together."), systemImage: "book.closed")
                        safetyNote
                        links
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .top) { heroImage }
                }
                .ignoresSafeArea(edges: .top)
            }
        }.safeAreaInset(edge: .bottom) { agreeButton }
    }

    private var heroImage: some View {
        Color.clear.frame(height: LegalGateLayout.heroHeight).overlay {
            // 作例写真（CC0・表記の要らない実写真・`Tools/composition-examples/photo-sources.json`）。
            // 出典の表記の決まりは「構図の作例」と同じで、CC0 なので札は要らない
            Image(heroAsset).resizable().aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // 改行は「写真から、／次の旅が始まる。」に固定（2026-10-21・run 609 の 01 で「次の旅／が始まる。」と
            // 語の途中で折れていた）。字は一言（`Labels.Brand.tagline`）と同じ
            Text(Labels.Brand.taglineLines)
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
            // 2026-11-25 判断（審査 1.2 の差し戻し・札 #604）: 「一切許さない」と「消す・止める」を先に、太い白の字で言う。
            // 前は「認めません」だけで、審査で「不適切な内容と嫌がらせを許さないと規約に明記して」と言われた
            Text(LegalGateText.zeroTolerance)
                .font(JPFont.footnote.weight(.semibold)).lineSpacing(4).foregroundStyle(WebTheme.text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("legal.zeroTolerance")
            Text(LegalGateText.howToReport)
                .font(JPFont.footnote).lineSpacing(4).foregroundStyle(WebTheme.text2).fixedSize(horizontal: false, vertical: true)
        }.padding(14)
        // 板 v2 の札（surface-1・白 8% の縁・角 14）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    // 押せる高さは**リンクごとに** 44pt（外の枠だけ高くしても、押せるのは文字の高さだけ）
    private var links: some View { VStack(alignment: .leading, spacing: 0) { HStack(spacing: 20) { Link(destination: LegalConsent.termsURL) { Text(L("利用規約", "Terms of Use")).underline().frame(minHeight: 44).contentShape(Rectangle()) }; Link(destination: LegalConsent.privacyURL) { Text(L("プライバシーポリシー", "Privacy Policy")).underline().frame(minHeight: 44).contentShape(Rectangle()) } }.font(JPFont.body).foregroundStyle(WebTheme.accent)
        // 押すと何に同意するのかを、ボタンの上で言う（審査 1.2: 登録・ログインの前に規約へ同意させる・2026-11-25）
        Text(LegalGateText.agreeNote).font(JPFont.caption).foregroundStyle(WebTheme.text3).fixedSize(horizontal: false, vertical: true) } }

    private var agreeButton: some View { Button { consent.accept() } label: { Text(LegalGateText.agree).jpPillButton(LegalGateLayout.agreeStyle) }.buttonStyle(.plain).accessibilityIdentifier("legal.agree").jpBottomBar() }
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

    /// 上に敷く写真の候補（2026-10-21 判断）。アプリに同梱した構図の作例写真（すべて CC0 の実写真・
    /// 出典は `Tools/composition-examples/photo-sources.json`）のうち、横長の帯（300pt）に切っても旅の写真に
    /// 見えるもの: 新倉山浅間公園の忠霊塔と富士山・山あいの湖・防波堤の灯台と夕空・アタカマの塩湖。
    /// 八坂の塔（人の後ろ姿が大きく写る）は、いちばん大きな写真には使わない（確かめ役の見直し）
    static let heroAssets = ["composition-ai-rootRectangle", "composition-ai-ratio16x9", "composition-ai-thirds",
                             "composition-ai-phiGrid"]

    /// 開くたびに1枚（日ごとに替わる。同じ日は同じ写真・試験で決められるように日を渡せる）
    static func heroAsset(day: Date = Date(), calendar: Calendar = .current) -> String {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        return heroAssets[((ordinal % heroAssets.count) + heroAssets.count) % heroAssets.count]
    }
}

/// 同意の画面の言葉（2026-11-25・審査 1.2 の差し戻し・札 #604）。試験で見張る。
///
/// 審査の指摘: 「登録・ログインの前に利用規約（EULA）へ同意させ、規約に不適切な投稿と嫌がらせを一切許さないと書くこと」。
/// サイトの規約（`/terms` の 4 節の頭）と同じ中身を、ここでも短く言う
enum LegalGateText {
    /// 決まりの一言（太い白の字）
    static var zeroTolerance: String {
        L("不適切な投稿や、ほかの人へのいやがらせは一切許しません。違反した投稿は削除し、投稿した人の利用を止めます。",
          "We have zero tolerance for objectionable content and abusive users. Posts that break these rules are removed, and the people who posted them are banned.")
    }
    /// 通報とブロックの場所と、写真の情報の扱い
    static var howToReport: String {
        L("写真、コメント、プロフィール、メッセージの「…」から、通報とブロックができます。撮影情報（EXIF）は端末で取り除き、撮影地は約1kmに丸めて保存します。",
          "You can report or block from the \u{2026} menu on any photo, comment, profile or message. Photo metadata is removed on your device, and locations are rounded to about 1 km.")
    }
    /// 主ボタン（何に同意するかをボタンの字で言う）
    static var agree: String { L("利用規約に同意してはじめる", "Agree to the Terms and start") }
    /// ボタンの上の注記
    static var agreeNote: String {
        L("「利用規約に同意してはじめる」を押すと、利用規約とプライバシーポリシーに同意したことになります。ログインや登録の前に、この同意が要ります。",
          "By tapping \u{201C}Agree to the Terms and start,\u{201D} you agree to the Terms of Use (EULA) and the Privacy Policy. This is required before you sign in or sign up.")
    }
}
