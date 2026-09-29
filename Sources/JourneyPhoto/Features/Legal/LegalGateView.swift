import SwiftUI

/// 初回に一度だけ出す同意画面（板 42「はじめる前に」）。
///
/// 上に写真を敷き、左上にロゴ、明朝の見出し、3つの約束を札のアイコンで並べ、
/// 下に固定した白いカプセルで同意する。
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
            VStack(spacing: 0) { heroImage; Spacer(minLength: 0) }
                .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppLogo().padding(.top, 6).padding(.bottom, 58)
                    heading
                    experience(L("撮りたい場所を見つける", "Find your next place to shoot"), detail: L("写真と地図から、次に行きたい撮影地を探せます。", "Discover your next shooting location through photos and the map."), systemImage: "map")
                    experience(L("写真と撮影情報を残す", "Keep the photo and how you shot it"), detail: L("作品だけでなく、カメラやレンズ、撮影地まで一緒に残せます。", "Keep the camera, lens and shooting location together with your work."), systemImage: "camera")
                    experience(L("旅を、一冊にする", "Turn a journey into a book"), detail: L("旅の前から撮影後まで。写真を旅の記録としてまとめられます。", "From planning to the photos you bring home, keep the whole journey together."), systemImage: "book.closed")
                    safetyNote
                    links
                }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.safeAreaInset(edge: .bottom) { agreeButton }.onAppear { pickHero() }
    }

    private var heroImage: some View {
        Color.clear.frame(height: 250).overlay {
            if let hero { AsyncImage(url: hero.gridImageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if case .success(let image) = phase { image.resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hero.gridAlignment) }
            }}
        }.clipped().overlay(alignment: .bottom) { LinearGradient(colors: [Color.black.opacity(0), Color.black], startPoint: .top, endPoint: .bottom).frame(height: 170) }.accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JOURNEY PHOTO").font(JPFont.mono(11)).tracking(1.6).foregroundStyle(WebTheme.accent).accessibilityHidden(true)
            Text(L("次に撮りたい場所が、見つかる。", "Find the place you want to photograph next."))
                .font(JPFont.display(32, relativeTo: .largeTitle)).foregroundStyle(WebTheme.text).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            Text(L("写真から旅が始まり、旅がまた写真になる。", "Let a photo start the journey — and the journey become your next photo."))
                .font(.subheadline).foregroundStyle(WebTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 4)
    }

    private func experience(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(WebTheme.accent).frame(width: 44, height: 44)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(WebTheme.text)
                Text(detail).font(.footnote).lineSpacing(3).foregroundStyle(WebTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 3)
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("安心して写真を楽しむために", "For a safe photo community"), systemImage: "shield")
                .font(.footnote.weight(.semibold)).foregroundStyle(WebTheme.accent)
            Text(L("いやがらせ・わいせつ・権利を侵す投稿は認めません。写真から通報・ブロックできます。撮影情報（EXIF）は端末で取り除き、撮影地は約1kmに丸めて保存します。", "Harassment, obscene content and rights violations are not allowed. Photos can be reported and posters blocked. Metadata is removed on device and locations are rounded to about 1 km."))
                .font(.footnote).lineSpacing(4).foregroundStyle(WebTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    private var links: some View { HStack(spacing: 20) { Link(destination: LegalConsent.termsURL) { Text(L("利用規約", "Terms of Use")).underline() }; Link(destination: LegalConsent.privacyURL) { Text(L("プライバシーポリシー", "Privacy Policy")).underline() } }.font(.footnote).foregroundStyle(WebTheme.accent).frame(minHeight: 32) }

    private var agreeButton: some View { Button { consent.accept() } label: { Text(L("同意してJourney Photoをはじめる", "Agree and start Journey Photo")).jpPillButton() }.buttonStyle(.plain).accessibilityIdentifier("legal.agree").jpBottomBar() }

    private func pickHero() { guard hero == nil, let photos = PhotoSnapshotStore().load() else { return }; hero = photos.first { photo in photo.gridImageURL != nil && !hidden.reportedPhotoIds.contains(photo.id) && !((photo.userId ?? photo.uploadedBy).map { hidden.blockedUserIds.contains($0) } ?? false) } }
}
