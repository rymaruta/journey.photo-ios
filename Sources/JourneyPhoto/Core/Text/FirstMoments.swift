import Foundation

// 楽しさの案 A（2026-11-08・札 #502 の提案書）: 「はじめて」の瞬間を静かに祝う。
//
// 守ること（提案書 5・owner の方針）:
// - 文は**事実だけ**を言う（「京都、はじめての1枚です」）。数を稼ぐ文（「あと3枚で」）・連続日数・順位・共有を促す文は出さない
// - 判定は端末の中で済ませる（サーバーに聞かない・保存を足さない）。**確かめられないときは祝わない**
//   （撮影地・日付が欠けた投稿、一覧が欠けているかもしれない回は「無い」方へ倒す）

// MARK: - 初めての反応（お知らせの行）

/// 初めてのいいね・コメントを、その人について一度だけ特別に見せる。
///
/// 「初めて」の判定（2026-11-08 判断）:
/// - お知らせの一覧は新しい順で、**サーバーは 50 件までに切る**（`api-user/src/notify.ts` の `NOTIFS_MAX`）。
///   50 件に届いている一覧は古い側が切れているかもしれないので、**そのときは決めない**（祝わない）
/// - 一覧に在るその種類のうち**いちばん古い 1 件**を「初めて」とする。ただし**直近 7 日以内**のものだけ。
///   この機能の前から居る人の古いいいねを、今さら「初めて」と祝わない（印だけ付けて、以後も祝わない）
/// - 退会した人のものは祝わない（印だけ付ける）
/// - 決めた行の id を人ごとに端末へ控える（`firstReaction.<種類>.<uid>`）。控えた行は一覧に在る間、印を保つ。
///   控えが在れば判定し直さない＝「一度だけ」。退会で消す（`AccountLocalData`）
enum FirstReaction {

    enum Kind: String, CaseIterable, Equatable {
        case like, comment

        /// 眉ラベル（真鍮・黒地の上）。色だけで伝えないよう、印と一緒に字でも言う
        var eyebrow: String {
            switch self {
            case .like: return L("はじめてのいいね", "Your first like")
            case .comment: return L("はじめてのコメント", "Your first comment")
            }
        }

        /// 一言。事実だけ（数や次の目標は言わない）
        var note: String {
            switch self {
            case .like: return L("あなたの写真が、はじめて誰かに届きました", "Your photo reached someone for the first time")
            case .comment: return L("あなたの写真に、はじめて言葉が届きました", "Someone wrote to you about a photo for the first time")
            }
        }

        var notification: AppNotification.Kind {
            switch self {
            case .like: return .like
            case .comment: return .comment
            }
        }
    }

    /// サーバーが一覧を切る件数（`NOTIFS_MAX`）。これに届いた一覧は古い側が切れているかもしれない
    static let listLimit = 50
    /// 「初めて」と祝う新しさ
    static let freshSeconds: TimeInterval = 7 * 24 * 60 * 60
    /// 「祝わないと決めた」印（行の id ではない値）
    static let skipped = "-"

    static func key(_ userId: String, _ kind: Kind) -> String { "firstReaction.\(kind.rawValue).\(userId)" }

    /// 一覧の中で「初めて」の印を付ける行（行の id → 種類）。決めた分は端末に控える。
    static func resolve(rows: [AppNotification], userId: String?, now: Date = Date(),
                        defaults: UserDefaults = .standard) -> [String: Kind] {
        guard let userId, !userId.isEmpty else { return [:] }
        var out: [String: Kind] = [:]
        for kind in Kind.allCases {
            let storeKey = key(userId, kind)
            if let stored = defaults.string(forKey: storeKey) {
                if stored != skipped, rows.contains(where: { $0.id == stored }) { out[stored] = kind }
                continue
            }
            // 切れているかもしれない一覧では、いちばん古い行が本当に初めてか分からない
            guard rows.count < listLimit else { continue }
            let ofKind = rows.filter { $0.kind == kind.notification }
            guard let oldest = oldest(of: ofKind) else { continue }
            var fresh = false
            if let at = oldest.t.flatMap(NotificationGroups.parse) {
                let age = now.timeIntervalSince(at)
                fresh = age >= -24 * 60 * 60 && age <= freshSeconds
            }
            if oldest.deleted == true || !fresh {
                defaults.set(skipped, forKey: storeKey)
                continue
            }
            defaults.set(oldest.id, forKey: storeKey)
            out[oldest.id] = kind
        }
        return out
    }

    /// 時刻がすべて読めるときは時刻でいちばん古い行、読めない行があれば並び（新しい順）の最後
    private static func oldest(of rows: [AppNotification]) -> AppNotification? {
        let dated = rows.compactMap { row in row.t.flatMap(NotificationGroups.parse).map { (row, $0) } }
        if !rows.isEmpty, dated.count == rows.count { return dated.min { $0.1 < $1.1 }?.0 }
        return rows.last
    }

    /// 退会のとき（`AccountLocalData.remove`）
    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        for kind in Kind.allCases { defaults.removeObject(forKey: key(userId, kind)) }
    }
}

// MARK: - 投稿を終えたときの一言（届いたラベルの画面）

/// 届いたラベルの画面に添える、事実の一文と光の強さ。
enum ArrivalFact {

    /// 一文（「京都、はじめての1枚です」）。言えるときだけ。
    ///
    /// - 節目「はじめて」・「はじめての国」はサーバーが決めた事実なのでそのまま言う
    /// - それ以外は、自分の写真の一覧から**この県で撮った写真がほかに無い**ときだけ言う。
    ///   一覧が読めていない・今投稿した写真が一覧に載っていない（一覧が古いかもしれない）・県が読めない・
    ///   同じ県のほかの写真が 1 枚でも在るときは言わない（取りこぼしは「言わない」方へ倒す）
    /// - ほかの公開の写真に、県が読めないもの（撮影地が空・英語・座標だけ）が1枚でも在るときも言わない
    /// - 県は撮影地の文字から読む既存の判定（`CamperCounting.prefecture(in:)`）を使い回す
    static func sentence(label: TrunkLabel, photos: [Photo]?) -> String? {
        let name = label.place.name
        if label.kind == .milestone {
            switch label.milestone {
            case .first:
                return name.isEmpty ? L("はじめての1枚です", "Your very first photo")
                    : L("\(name)、はじめての1枚です", "\(name) \u{2014} your very first photo")
            case .firstCountry:
                let country = label.place.country ?? name
                return country.isEmpty ? L("はじめての国です", "Your first country")
                    : L("\(country)、はじめての国です", "\(country) \u{2014} your first country")
            default: break
            }
        }
        guard let photos else { return nil }
        let published = photos.filter { $0.published != false }
        guard let mine = published.first(where: { $0.id == label.photoId }) else { return nil }
        guard let prefecture = CamperCounting.prefecture(in: mine.location)
                ?? CamperCounting.prefecture(in: name) else { return nil }
        // ほかの公開の写真の県が1枚でも読めないなら言わない（撮影地が空・英語・座標だけの写真が、
        // 実はその県かもしれない。確かめられないときは祝わない）
        var others: [String?] = []
        for p in published where p.id != label.photoId { others.append(CamperCounting.prefecture(in: p.location)) }
        guard !others.contains(where: { $0 == nil }), !others.contains(where: { $0 == prefecture }) else { return nil }
        return L("\(prefecture)、はじめての1枚です", "\(prefecture) \u{2014} your first photo here")
    }

    #if DEBUG
    /// 画面写真の見本（`-JPPreviewTrunkArrived`）の一覧: 今届いた 1 枚だけ（その県で初めてになる）
    static func previewPhotos(for label: TrunkLabel) -> [Photo] {
        let json: [String: Any] = ["id": label.photoId, "src": "https://example.com/\(label.photoId).jpg",
                                   "location": "京都府 京都市", "published": true]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let photo = try? JSONDecoder().decode(Photo.self, from: data) else { return [] }
        return [photo]
    }
    #endif

    /// 節目と箔押しは、後ろの真鍮の光を一段強くする
    static func isSpecial(_ label: TrunkLabel) -> Bool {
        label.kind == .milestone || label.foil
    }
}

/// 届いたラベルの画面の動きの順序（写真 → ラベルが落ちる → 一文）。秒は画面の外から入れて試す。
struct ArrivalSequence: Equatable {
    enum Step: Int, Comparable {
        case start, photo, label, sentence
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// 写真が現れるまで・ラベルが落ち始めるまで・一文が現れるまで（開いてからの秒）
    static let photoAt = 0.15
    static let labelAt = 0.55
    static let sentenceAt = 1.25
    /// ラベルが落ち始めてから、貼りついて触覚を鳴らすまで（ばねが落ち切る少し前）
    static let landAfter = 0.28

    /// その段を見せてよいか。動きを減らす設定のときは、待たずに全部を最初から出す（画面が使う）
    static func isShown(_ target: Step, current: Step, reduceMotion: Bool) -> Bool {
        let now = reduceMotion ? firstStep(reduceMotion: true) : current
        return now >= target
    }

    /// 動きを減らす設定のときは、待たずに全部を最初から出す（同じ情報を静かに出す）
    static func firstStep(reduceMotion: Bool) -> Step { reduceMotion ? .sentence : .start }

    /// 次に進む前の待ち（秒）。動きを減らすときは進めるものが無い
    static func delays(reduceMotion: Bool) -> [(Step, Double)] {
        reduceMotion ? [] : [(.photo, photoAt), (.label, labelAt - photoAt), (.sentence, sentenceAt - labelAt)]
    }
}
