import SwiftUI
import UIKit

/// ほかの人からの見え方（#304・板 50c ProfileLooks・2026-10-18）。プロフィールの編集から積む画面。
///
/// いまのアイコンとカバーが、ほかの人の画面でどう出るかの見本（押しても何も起きない絵）。
/// **見本は今アイコンが出ている所だけ**——人のページの上（カバーの帯とアイコン）とコメントの横（2026-10-18 判断:
/// 板の「人のトランクの見出し」「すれちがいの乗車券」はアイコンを出していないので載せない。足すかは旅のトランクの持ち物）。
/// 編集で選んだばかりの（まだ保存していない）絵があれば、それで見せる。
/// 「まだ」の姿: アイコンは名前の頭文字の丸、カバーの帯は出さない（ほかの人には空き地も額縁も見せない・板 05d・31）
struct ProfileLooksView: View {
    let userId: String?
    let name: String
    let username: String?
    /// 編集で選んだばかりの絵（保存前）
    var avatarPreview: UIImage?
    var coverPreview: UIImage?

    /// 置かれているか（読めるまで nil。分からなければ在る扱いで絵を読みにいく）
    @State private var hasAvatar: Bool?
    @State private var hasCover: Bool?

    private var avatarSet: Bool { avatarPreview != nil || hasAvatar != false }
    private var coverSet: Bool { coverPreview != nil || hasCover == true }
    private var unset: Bool { avatarPreview == nil && coverPreview == nil && hasAvatar == false && hasCover == false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(L("いまのアイコンとカバーが、ほかの人の画面でどう出るかの見本です。",
                       "A preview of how your avatar and cover appear to other people."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if unset { unsetNote }
                section(L("人のページ", "Your page"),
                        note: L("いちばん大きく出るところ。カバーは上の帯（下は黒へ溶ける）、アイコンはその下端に重なります。",
                                "The biggest place. The cover is the band at the top; your avatar overlaps its lower edge.")) {
                    pageSample
                }
                section(L("コメントの横", "Beside comments"),
                        note: L("いちばん多く出るところ。28pt の丸なので、顔や形がはっきりした写真ほど見分けやすくなります。",
                                "The most frequent place. It's a 28pt circle, so clear faces and shapes are easiest to recognize.")) {
                    commentSample
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(L("ほかの人からの見え方", "How others see you"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let userId else { return }
            async let a = ProfileImageFromPhoto.exists(userId: userId, kind: .avatar)
            async let c = ProfileImageFromPhoto.exists(userId: userId, kind: .cover)
            let (av, cv) = await (a, c)
            hasAvatar = av
            hasCover = cv
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profileLooks")
    }

    private var unsetNote: some View {
        Text(L("アイコンがまだ無いので、名前の頭文字の丸で出ています。カバーが無いと、ページの上は黒のままです。",
               "Without an avatar, your initial shows in a circle. Without a cover, the top of your page stays black."))
            .font(JPFont.footnote)
            .foregroundStyle(WebTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.m))
    }

    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            content()
                .accessibilityHidden(true)
            Text(note)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 人のページの上（板 50c-1: 高さ 210・カバー 120 の帯・60 の丸）
    private var pageSample: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 210)
            if coverSet {
                // 写真は重ね（overlay）に置く（横長の写真で行の幅を押し広げない・`ProfileEditView` と同じ）
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay {
                        if let coverPreview { Image(uiImage: coverPreview).resizable().scaledToFill() } else { RemoteImage(url: assetURL("cover")) }
                    }
                    .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [WebTheme.background.opacity(0), WebTheme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                avatar(60)
                    .coverCutout(true)
                Text(name)
                    .font(JPFont.display(20, relativeTo: .title3))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .padding(.leading, 16)
            .padding(.top, coverSet ? 86 : 22)
        }
        .background(WebTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: 1))
    }

    /// コメントの横（板 50c-4: 28 の丸）
    private var commentSample: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(28)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                Text(L("すてきな光ですね。", "Lovely light."))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .jpCardFace()
    }

    @ViewBuilder
    private func avatar(_ side: CGFloat) -> some View {
        WebTheme.surface3
            .frame(width: side, height: side)
            .overlay {
                if let avatarPreview {
                    Image(uiImage: avatarPreview).resizable().scaledToFill()
                } else if avatarSet {
                    RemoteImage(url: assetURL(nil))
                } else {
                    Text(String(name.prefix(1)))
                        .font(JPFont.display(side * 0.4, relativeTo: .body))
                        .foregroundStyle(WebTheme.text2)
                }
            }
            .clipShape(Circle())
    }

    private func assetURL(_ suffix: String?) -> URL? {
        userId.flatMap { UserProfile.profileAssetURL(userId: $0, suffix: suffix, cacheBust: ProfileImageVersions.shared.token(for: $0)) }
    }
}
