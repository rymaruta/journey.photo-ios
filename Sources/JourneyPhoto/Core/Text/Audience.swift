import Foundation

/// 公開範囲。**ストーリーと写真で同じものを使う。**
///
/// 元は `StoryService` の中に在った。写真にも同じ三択が要るので出した
/// ——二か所に書くと、片方に選択肢を足したときに静かにずれる
/// （`Tools/check-swift-refs.js` が型の重複を見張っている）。
///
/// **「全体に公開」は送らない**——サーバーも属性を書かない形で
/// 持つので、既にある行と同じ形に揃える。
enum Audience: String, CaseIterable, Identifiable {
    case everyone
    case followers
    /// 自分が選んだ人だけ（`api-user/src/closeFriends.ts`）
    case closeFriends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone: return L("全体に公開", "Everyone")
        case .followers: return L("フォロワーのみ", "Followers")
        case .closeFriends: return L("親しい友達", "Close friends")
        }
    }

    var note: String {
        switch self {
        case .everyone: return L("ログインしている人なら誰でも見られます",
                                 "Anyone signed in can see it")
        case .followers: return L("自分をフォローしている人だけが見られます",
                                  "Only people who follow you")
        case .closeFriends: return L("自分が選んだ人だけが見られます（相手には知らせません）",
                                     "Only people you picked — they aren't told")
        }
    }

    var systemImage: String {
        switch self {
        case .everyone: return "globe"
        case .followers: return "person.2"
        case .closeFriends: return "star"
        }
    }

    /// サーバーへ送る値。**全体に公開は送らない**
    /// （サーバーも属性を書かない形で持つ）
    var wireValue: String? { self == .everyone ? nil : rawValue }
}
extension Audience {
    /// `PUT /photos/{id}` に送る値。**「全体に公開」は空文字**
    /// （`wireValue` の `nil` だと本文からキーごと消え、サーバーは
    /// 既にある印をそのまま残す＝**絞りを外せなくなる**）。
    var patchValue: String { wireValue ?? "" }


    /// 写真に付けたときの但し書き。**ストーリーとは効き方が違う。**
    ///
    /// 絞った写真は静的サイト（`app/data/photos.json`）に載らない
    /// ＝**個別ページもサイトマップも作られない**。つまり検索から
    /// 辿り着けなくなる。アプリの中だけで見えるものになるので、
    /// 選ぶ前にそう言う。
    var photoNote: String {
        switch self {
        case .everyone:
            return L("ウェブサイトにも載り、検索から見つけてもらえます",
                     "Also on the website, findable in search")
        case .followers:
            return L("自分をフォローしている人だけ。ウェブサイトには載りません",
                     "Only your followers — not on the website")
        case .closeFriends:
            return L("自分が選んだ人だけ。ウェブサイトには載りません",
                     "Only people you picked — not on the website")
        }
    }
}
