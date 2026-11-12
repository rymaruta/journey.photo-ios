import SwiftUI

/// **ホームの「フォロー中」が空のときの「おすすめの人」**（資料「SNS をもっと SNS に」④・板 Main の「フォロー中が空」・
/// 1.1.83・2026-11-12）。並べる人は `SuggestedPeople.pick` が決める。
///
/// 並び（資料の模型どおり）: 明朝 20 の見出し「まず、写真の好きな人を」→ 13 の一文 → 真鍮の眉「おすすめの人」→
/// 人ごとに「顔 44・名前 15・"41 枚 · 最近 [撮影地]" 12 ＋右にフォロー」と、その下に写真3枚（高さ 96・すき間 4）。
/// この場で1人でもフォローしたら、下に白い主ボタン「フォロー中の写真を見る」（写真のある画面なので白・板 Main）。
///
/// 色: フォローは白の塗りに墨（`FollowPill`・板 Main）。眉ラベルは真鍮（黒地の上の合図）。
/// 押したらすぐフォローする（確かめは出さない・押し直しで外せる＝CLAUDE.md「聞くのは最小に」）。
///
/// 2026-11-12 判断: 資料の「はじめての投稿」の印は枝 sns-loop のもので、1.1.82 から戻した（5596d647）ので付けない。
struct HomeSuggestedPeopleView: View {
    let people: [SuggestedPeople.Person]
    /// 「フォロー中の写真を見る」。この場でフォローした人を渡す（呼ぶ側がフォロー中の一覧を読み直す）
    let onSeeFeed: (Set<String>) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    /// この場でフォローした人（押し直しで外せる）
    @State private var followedHere: Set<String> = []
    /// 送っている最中の人（連打で2回送らない）
    @State private var busy: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(SuggestedPeople.title)
                    .font(JPFont.stateTitle)
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(SuggestedPeople.message)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(SuggestedPeople.eyebrow)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            ForEach(people) { person in
                personBlock(person)
            }
            if SuggestedPeople.showsSeeFeed(followedHere: followedHere) {
                Button { onSeeFeed(followedHere) } label: {
                    Text(SuggestedPeople.seeFeed)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .webPrimaryButton()
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.suggested.seeFeed")
                .padding(.top, JPSpace.xxs)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, JPSpace.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.suggested")
    }

    private func personBlock(_ person: SuggestedPeople.Person) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            HStack(spacing: JPSpace.s) {
                NavigationLink {
                    UserProfileView(userId: person.userId)
                } label: {
                    HStack(spacing: JPSpace.s) {
                        DMAvatar(userId: person.userId, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .font(JPFont.bodyEmphasis)
                                .foregroundStyle(WebTheme.text)
                                .lineLimit(1)
                            // 数と撮影地は中黒で区切らず、字の太さ・色と 8pt の間で分ける（2026-11-12 の決まり）
                            HStack(spacing: 8) {
                                Text(SuggestedPeople.countLine(person))
                                    .font(JPFont.caption.weight(.semibold))
                                    .foregroundStyle(WebTheme.text2)
                                if let recent = SuggestedPeople.recentLine(person) {
                                    Text(recent)
                                        .font(JPFont.caption)
                                        .foregroundStyle(WebTheme.text3)
                                }
                            }
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SuggestedPeople.spoken(person))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home.suggested.person")
                followButton(person)
            }
            photoRow(person)
        }
    }

    private func followButton(_ person: SuggestedPeople.Person) -> some View {
        let on = followedHere.contains(person.userId)
        return Button {
            Task { await toggle(person) }
        } label: {
            FollowPill(title: on ? SuggestedPeople.following : SuggestedPeople.follow, isFollowing: on)
                .frame(minWidth: 96)
        }
        .buttonStyle(.plain)
        .disabled(busy.contains(person.userId))
        .accessibilityLabel(on ? L("\(person.name) さんをフォロー中", "Following \(person.name)")
                               : L("\(person.name) さんをフォロー", "Follow \(person.name)"))
        .accessibilityIdentifier("home.suggested.follow")
    }

    /// 写真3枚（高さ 96・すき間 4）。押すとその写真の詳細（3枚を送れる）
    private func photoRow(_ person: SuggestedPeople.Person) -> some View {
        HStack(spacing: 4) {
            ForEach(person.photos) { photo in
                NavigationLink {
                    PhotoDetailView(photo: photo, context: person.photos)
                } label: {
                    WebTheme.card
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .overlay(RemoteImage(url: photo.gridImageURL).allowsHitTesting(false))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(photo.title?.resolved() ?? L("写真", "Photo"))
            }
            // 3枚に満たない人も、1枚の幅を揃える
            ForEach(0..<max(0, SuggestedPeople.photosPerPerson - person.photos.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).frame(height: 96)
            }
        }
    }

    /// フォローする・外す。失敗したら元に戻して知らせる（黙らない）
    private func toggle(_ person: SuggestedPeople.Person) async {
        let id = person.userId
        guard !busy.contains(id) else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        let wants = !followedHere.contains(id)
        do {
            let result = wants
                ? try await environment.social.follow(userId: id)
                : try await environment.social.unfollow(userId: id)
            if result.following { followedHere.insert(id) } else { followedHere.remove(id) }
        } catch is CancellationError {
            return
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription
                        ?? L("うまくいきませんでした", "That didn't work"), kind: .failure)
        }
    }
}
