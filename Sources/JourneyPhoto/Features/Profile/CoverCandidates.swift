import Foundation

/// アイコン・カバーを自分の写真から選ぶときの候補（#304・板 50 CoverPick・50b AvatarCrop・2026-10-18）。
///
/// - **出すのは全体に公開している自分の写真だけ**（カバーとアイコンは誰にでも見えるので、下書き・
///   公開範囲を絞った写真は出さない）。条件はサーバーの `isPublicListPhoto`（`api-user/src/feed.ts`）と
///   Web の `lib/utils/coverCandidates.ts` と同じ
/// - カバーは「いいねの多い順」（同じ数なら新しい順）と「最近」（投稿の新しい順）の4枚
/// - アイコンは最近の10枚（板 50b の格子 5×2）
/// - いいねの数は候補の下に出さない（競う数にしない・板の付箋）——ここは並べるだけ
enum CoverCandidates {

    enum Sort: String, CaseIterable, Identifiable {
        case likes
        case recent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .likes: return L("いいねの多い順", "Most liked")
            case .recent: return L("最近", "Recent")
            }
        }
    }

    /// カバーの候補の数（板 50: 4枚）
    static let coverCount = 4
    /// アイコンの候補の数（板 50b: 5×2）
    static let avatarCount = 10

    /// 全体に公開している写真か（下書き・公開範囲を絞った写真・画像の無い行は false）
    static func isCandidate(_ photo: Photo) -> Bool {
        guard !photo.src.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if photo.published == false { return false }
        if let audience = photo.audience, !audience.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    static func cover(_ photos: [Photo], sort: Sort, limit: Int = coverCount) -> [Photo] {
        Array(sorted(photos.filter(isCandidate), by: sort).prefix(limit))
    }

    static func avatar(_ photos: [Photo], limit: Int = avatarCount) -> [Photo] {
        Array(sorted(photos.filter(isCandidate), by: .recent).prefix(limit))
    }

    private static func sorted(_ photos: [Photo], by sort: Sort) -> [Photo] {
        photos.sorted { a, b in
            if sort == .likes {
                let la = max(0, a.likes ?? 0), lb = max(0, b.likes ?? 0)
                if la != lb { return la > lb }
            }
            // 投稿の時刻は ISO 8601 の文字なので、文字のまま比べて新しい順になる
            let ta = a.createdAt ?? "", tb = b.createdAt ?? ""
            if ta != tb { return ta > tb }
            return a.id < b.id
        }
    }
}

/// 「この1枚をカバーに」を差し出す決まり（#304・板 51 CoverOffer・51b CoverOfferLiked・2026-10-18）
enum CoverOfferRules {

    /// いいねが集まった1枚を差し出す件数。2026-10-18 判断: いいねの件数の決まった値がアプリにもサーバーにも
    /// 無かった（通知・メダルは件数で区切っていない）ので 10 にした。owner が別の値を決めたらここだけ替える
    static let likedThreshold = 10

    /// 初めての投稿か。**いま全部上がった投稿（`posted`）のほかに、自分の写真が1枚も無い**とき。
    /// 一覧に今の投稿がまだ載っていない（索引の遅れ）こともあるので、載っていない分は数えない
    static func isFirstPost(myPhotos: [Photo], posted: Set<String>) -> Bool {
        guard !posted.isEmpty else { return false }
        return myPhotos.allSatisfy { posted.contains($0.id) }
    }

    /// いいねが集まった1枚（無ければ nil）。全体に公開している写真のうち、件数に届いていて、
    /// まだ聞いていない・いまのカバーに選んだ写真でないものの、いちばん多い1枚
    static func likedCandidate(_ photos: [Photo], asked: Set<String>, currentCover: String?,
                               threshold: Int = likedThreshold) -> Photo? {
        photos.filter { CoverCandidates.isCandidate($0)
            && ($0.likes ?? 0) >= threshold
            && !asked.contains($0.id)
            && $0.id != currentCover }
            .max { a, b in
                let la = a.likes ?? 0, lb = b.likes ?? 0
                if la != lb { return la < lb }
                return (a.createdAt ?? "") < (b.createdAt ?? "")
            }
    }
}
