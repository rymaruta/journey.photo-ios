import Foundation

/// **撮影スポットを DM で送る**（資料「SNS をもっと SNS に」⑤「一緒に行こう」・1.1.83・2026-11-12）。
///
/// 撮影スポットの頁の右上の「送る」（今の ↑ と同じ場所・入口は増やさない）から、写真と同じ「送る」シート
/// （`SendSheet`・顔の列 `DMPeopleFacesRow`）を開き、顔を押すとその人へ1通。受けた人の会話には
/// 撮影スポットの札（`DMSpotCard`）が出て、1回で「行きたい場所」に入れられる。
///
/// 🔴 2026-11-12 判断: **サーバーの口は変えない。** 資料は「DM の引用に撮影スポットの種類を足す API の変更」と
/// 書いていたが、送るのは**撮影スポットのサイトの頁のリンク（`<サイト>/spots/<スラッグ>`）だけの文**にした。
/// - アプリは文の中の頁のリンクを見つけて札にする（`slug(in:siteBase:)`）。Web の DM と古いアプリでは
///   そのままリンクとして読める（頁は公開済みの撮影スポットにしか建たない＝開けないリンクは送らない）
/// - サーバーは、承認されるまではリンクを断る（`dm.ts` の `containsUrl`・写真を送るのと同じ考え）。
///   断られたらサーバーの言葉をそのまま出す
/// - 引用の種類を足す口（写真の `dmPhotoQuote` と同じ形）は、札の絵をサーバーが持てる利点があるが、
///   API の変更と Web の DM の対応が要る。リンクで足りる間は作らない
enum DMSpotShare {

    /// 送る文（頁のリンクだけ）
    static func message(pageURL: URL) -> String { pageURL.absoluteString }

    /// 文の中の撮影スポットの頁のリンクからスラッグを拾う。**このサイトの `/spots/<スラッグ>` だけ**
    /// （ほかのサイト・ほかの頁・スラッグの無いリンクは札にしない）。最初の1つだけ
    static func slug(in text: String, siteBase: URL) -> String? {
        firstMatch(in: text, siteBase: siteBase)?.slug
    }

    /// 文の中の撮影スポットの頁のリンクそのもの（札が作れなかったときに出す・文全体は出さない）
    static func link(in text: String, siteBase: URL) -> String? {
        firstMatch(in: text, siteBase: siteBase).map { String(text[$0.range]) }
    }

    /// 札のほかに吹き出しに残す文（頁のリンクを抜いた残り）。残りが空なら nil（札だけ出す）
    static func remainder(_ text: String, siteBase: URL) -> String? {
        guard let match = firstMatch(in: text, siteBase: siteBase) else {
            return text.isEmpty ? nil : text
        }
        var rest = text
        rest.removeSubrange(match.range)
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstMatch(in text: String, siteBase: URL) -> (slug: String, range: Range<String.Index>)? {
        guard let host = siteBase.host?.lowercased() else { return nil }
        // 区切りは空白（URL の中に空白は入らない）
        var index = text.startIndex
        while index < text.endIndex {
            let start = text[index...].firstIndex { !$0.isWhitespace } ?? text.endIndex
            guard start < text.endIndex else { break }
            let end = text[start...].firstIndex { $0.isWhitespace } ?? text.endIndex
            let token = String(text[start..<end])
            if let slug = spotSlug(token, host: host) { return (slug, start..<end) }
            index = end
        }
        return nil
    }

    /// 1語が撮影スポットの頁のリンクなら、そのスラッグ
    private static func spotSlug(_ token: String, host: String) -> String? {
        guard let url = URL(string: token),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let tokenHost = url.host?.lowercased(),
              tokenHost == host || tokenHost == "www." + host || "www." + tokenHost == host else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "spots" else { return nil }
        let slug = (parts[1].removingPercentEncoding ?? parts[1]).trimmingCharacters(in: .whitespaces)
        return slug.isEmpty ? nil : slug
    }

    /// 撮影スポットを1通送る。鍵は1回の送信につき1つ
    @discardableResult
    static func send(service: DMService, me: String?, peerId: String, pageURL: URL,
                     clientId: String = DMRules.newClientId()) async throws -> DMSendResult {
        guard let id = DMStart.conversationId(me: me, peer: peerId) else { throw DMPhotoSend.Failure.invalid }
        return try await service.send(id, text: message(pageURL: pageURL), clientId: clientId)
    }

    // MARK: 言葉（資料の模型どおり）

    /// 札の眉ラベル（黒地の上なので真鍮）
    static var eyebrow: String { L("一緒に行こう", "Let\u{2019}s go together") }
    /// 札の2行目の種類（「観光スポット」・2026-11-12 owner 承認の呼び名）。地域は別の字（`DMSpotCard`）で、
    /// 中黒で区切らない（2026-11-12 の決まり）。**「見頃」は言わない**（台帳の季節は見頃の約束ではない・
    /// `HomeTopCard` の注記。資料の模型の「見頃 11月下旬 〜」は付けない）
    static var kindLabel: String { L("観光スポット", "Sightseeing spot") }
    static var addToWishlist: String { L("行きたい場所に入れる", "Add to Want to go") }
    static var addedToWishlist: String { L("行きたい場所に入れました", "In Want to go") }
    /// 札を読めなかったとき（索引に無い・読めない）は札を出さず、リンクの文のまま出す
    static func spoken(name: String, region: String?, mine: Bool) -> String {
        let head = mine ? L("送った観光スポット", "Spot you sent") : L("届いた観光スポット", "Spot received")
        // 区切りは日本語は「、」、英語は「, 」（確かめ役の指摘・2026-11-12）
        let comma = L("、", ", ")
        guard let region, !region.isEmpty else { return head + comma + name }
        return head + comma + name + comma + region
    }

    // MARK: 送る前に分かる「送れない相手」（確かめ役の指摘・2026-11-12）

    /// サーバーは、承認されるまで会話にリンクを入れない（`dm.ts` の `containsUrl` → 400 `requestUrl`）。
    /// 観光スポットは頁のリンクで送るので、**まだ会話が無い相手・こちらから始めて承認待ちの相手**には届かない。
    /// 受信箱を読めているときだけ見分け、その顔を薄くする（読めていなければ薄くしない＝サーバーが決める）。
    /// 相手から届いたリクエスト（`request`）は、返信すると承認したことになる（板 DM）ので薄くしない
    static func unreachablePeers(_ people: [FollowUser], inbox: DMInbox, inboxLoaded: Bool) -> Set<String> {
        guard inboxLoaded else { return [] }
        var states: [String: DMEntryState] = [:]
        for thread in inbox.items { states[thread.peerId] = thread.state }
        return Set(people.compactMap { person in
            switch states[person.id] {
            case .inbox?, .request?: return nil
            case .pending?, nil: return person.id
            }
        })
    }

    /// 承認前の相手に送ろうとしたとき・サーバーが `requestUrl` で断ったときの言葉（写真の `requestPhoto` と同じ考え）
    static var refusedBeforeAccept: String {
        L("承認されるまでは観光スポットを送れません。まず文字で話しかけてください",
          "You can't send spots until they accept. Start with a text message.")
    }

    /// 送れなかったときの言葉。リンクを断られた（`requestUrl`）なら観光スポットの言葉、ほかはサーバーの言葉
    static func failureText(_ error: Error) -> String {
        if let refused = error as? DMService.Refused, refused.code == "requestUrl" { return refusedBeforeAccept }
        return (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
    }
}
