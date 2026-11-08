import Foundation

/// 手荷物タグを自分で選ぶ画面の文言と決まり（2026-11-08 owner 承認・札 #501・デザイナーのモック「手荷物タグの選び方」案A）。
///
/// 画面（`TrunkTagsView`）は見た目だけを持ち、**何を出すか・どの行を押せるか・どう保存するか**はここに置く
/// （Linux でも試験できるように）。「捨てる」は使わない——外すは「タグを外す」「保存せずに閉じる」。
enum TrunkTagText {

    // MARK: 文言

    static let title = L("手荷物タグ", "Baggage tags")
    static let intro = L("トランクに吊るすタグに、どのラベルの地名を載せるか選べます。",
                         "Choose which label\u{2019}s place goes on each tag hanging from your trunk.")
    static let nowEyebrow = L("いまのタグ", "TAGS NOW")
    static let footer = L("おまかせの枠は、新しく貼ったラベルの地名が順に載ります。選んだ枠と外した枠は、そのまま残ります。",
                          "Auto tags show the places of your newest labels in order. Tags you chose or removed stay as they are.")
    static let emptySlot = L("空き", "Empty")

    static let sheetNote = L("貼ったラベルの地名が、タグに載ります。", "The place name of a label you\u{2019}ve stuck goes on the tag.")
    static let backToAuto = L("おまかせに戻す", "Back to auto")
    static let removeTag = L("タグを外す", "Remove tag")
    static let done = L("完了", "Done")
    static let close = L("閉じる", "Close")
    static let onTag = L("載せている", "On the tag")
    static let sameNameNote = L("同じ地名は、タグに1枚だけ載せられます。", "Each place can be on only one tag.")
    static let noPlaceTitle = L("地名がありません", "No place name")
    static let noPlaceNote = L("タグには載せられません", "Can\u{2019}t go on a tag")

    static let emptyTitle = L("貼ったラベルがありません", "No labels stuck yet")
    static let emptyMessage = L("ラベルを貼ると、タグに載せられます。", "Stick a label and you can put it on a tag.")
    static let stickAction = L("ラベルを貼る", "Stick labels")

    static let loadingNote = L("ラベルを読み込んでいます", "Loading your labels")
    static let saveFailedTitle = L("タグを保存できませんでした", "Couldn\u{2019}t save the tags")
    static let saveFailedMessage = L("通信に失敗しました。選んだ内容はまだ保存されていません。",
                                     "The connection failed. What you chose hasn\u{2019}t been saved yet.")
    static let retry = L("もう一度", "Try again")
    static let closeWithoutSaving = L("保存せずに閉じる", "Close without saving")

    static let offlineTitle = L("電波のあるところで選べます", "Choose where you have a signal")
    static let offlineMessage = L("いまのタグは見られます。選ぶ行は押せますが、保存は電波が戻ってからです。",
                                  "You can still see your tags. You can tap a row, but it saves once you have a signal again.")

    /// ラベルをはがして、タグの枠がおまかせに戻ったとき（一度だけ・知らせ）
    static let pickResetNotice = L("ラベルをはがしたので、タグをおまかせに戻しました",
                                   "You peeled that label off, so its tag is back to auto")

    /// 保存の失敗の見出しの下に出す一言。サーバーの断りがあればそれ
    static func failureMessage(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return saveFailedMessage }
        return detail
    }

    // MARK: トランクの画面の行

    /// 行の右（「2 / 3 枚」）。まだ1枚も吊るせない間は、いつ吊るせるかを言う
    static func rowValue(shown: Int, open: Int) -> String {
        guard open > 0 else {
            let first = TrunkAging.tagThresholds[0]
            return L("投稿\(first)件で1枚目", "1st tag at \(first) posts")
        }
        return L("\(shown) / \(open) 枚", "\(shown) / \(open) tags")
    }

    // MARK: 枠

    static func slotName(_ slot: Int) -> String { L("\(slot + 1)枚目", "Tag \(slot + 1)") }

    static func placeName(_ label: TrunkLabel?) -> String {
        label?.place.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 枠の1行目（「1枚目 京都」）
    static func slotTitle(_ slot: Int, _ result: TrunkLooks.TagSlotResult) -> String {
        let name = placeName(result.label)
        return name.isEmpty ? slotName(slot) : "\(slotName(slot)) \(name)"
    }

    /// 枠の2行目（おまかせ／あなたが選びました／あと N 件の投稿で…）
    static func slotNote(_ slot: Int, _ result: TrunkLooks.TagSlotResult, posts: Int) -> String {
        switch result.source {
        case .locked:
            let need = slot < TrunkAging.tagThresholds.count ? TrunkAging.tagThresholds[slot] : TrunkAging.tagThresholds[0]
            let more = max(1, need - max(0, posts))
            return L("あと \(more) 件の投稿で、\(slot + 1)枚目が吊るせます", "\(more) more posts to hang tag \(slot + 1)")
        case .auto:
            return result.label == nil
                ? L("おまかせ・載せられる地名がまだありません", "Auto · no place to show yet")
                : L("おまかせ（新しく貼ったラベルから）", "Auto (from your newest labels)")
        case .chosen:
            return L("あなたが選びました", "You chose this")
        case .removed:
            return L("タグを外しています", "No tag on this one")
        }
    }

    /// 吊るせる枠か（選べる）
    static func isOpen(_ result: TrunkLooks.TagSlotResult) -> Bool { result.source != .locked }

    /// 枠 `slot` を `pick` に替えた、枠の順の選び全部（サーバーは全部まとめて置き換える）。
    /// 選んだラベルと同じ地名を別の枠が選んでいたら、その枠はおまかせに戻して送る（サーバーは重複を 409 にする）
    static func picks(replacing slot: Int, with pick: TrunkTagPick, in current: [TrunkTagPick],
                      stuck: [TrunkLabel] = []) -> [TrunkTagPick] {
        var out = current
        while out.count <= slot { out.append(.auto) }
        out[slot] = pick
        if case .label(let id) = pick, let label = stuck.first(where: { $0.id == id }) {
            let name = placeName(label)
            for i in out.indices where i != slot {
                if case .label(let other) = out[i], let o = stuck.first(where: { $0.id == other }), placeName(o) == name {
                    out[i] = .auto
                }
            }
        }
        return TrunkTagPick.normalized(out)
    }

    // MARK: 選ぶ一覧

    /// 一覧の1行
    struct Candidate: Equatable, Identifiable {
        enum Availability: Equatable {
            /// 押して選べる
            case available
            /// いま、この枠に載っている
            case current
            /// 別の枠に同じ地名が載っている（押せる。選ぶと元の枠はおまかせに戻る・番号は 0 始まり）
            case usedInSlot(Int)
            /// 地名が無く、タグに載せられない（押せない）
            case noPlace
        }

        let label: TrunkLabel
        let availability: Availability
        var id: String { label.id }
        var isEnabled: Bool { availability != .noPlace }
    }

    /// 枠 `slot` に載せるラベルの一覧。**貼ったラベルの新しい順で、地名のあるものを先に、地名の無いものを最後に**。
    /// 別の枠に載っている地名も選べる（選ぶと元の枠はおまかせに戻る。同じ地名は1枚だけ・サーバーも 409 `tagPickDuplicate`
    /// なので、送る選びでは元の枠を外す・`picks(replacing:)`）
    static func candidates(stuck: [TrunkLabel], posts: Int, picks: [TrunkTagPick], slot: Int) -> [Candidate] {
        let results = TrunkLooks.tagSlotResults(stuck: stuck, posts: posts, picks: picks)
        var usedElsewhere: [String: Int] = [:]
        for (i, r) in results.enumerated() where i != slot {
            let name = placeName(r.label)
            if !name.isEmpty && usedElsewhere[name] == nil { usedElsewhere[name] = i }
        }
        let shownHere: String? = slot < results.count ? results[slot].label?.id : nil
        var named: [Candidate] = []
        var nameless: [Candidate] = []
        for label in stuck {
            guard TrunkLooks.canHangTag(label) else {
                nameless.append(Candidate(label: label, availability: .noPlace))
                continue
            }
            if label.id == shownHere {
                named.append(Candidate(label: label, availability: .current))
            } else if let other = usedElsewhere[placeName(label)] {
                named.append(Candidate(label: label, availability: .usedInSlot(other)))
            } else {
                named.append(Candidate(label: label, availability: .available))
            }
        }
        return named + nameless
    }

    /// 行の2行目（日付と、押せない理由・載せている印）
    static func candidateNote(_ c: Candidate, selected: Bool) -> String {
        var parts: [String] = []
        if let day = dayText(c.label) { parts.append(day) }
        switch c.availability {
        case .noPlace:
            parts.append(noPlaceNote)
        case .usedInSlot(let other):
            parts.append(L("\(other + 1)枚目の枠が、おまかせに戻ります", "Tag \(other + 1) goes back to auto"))
        case .available, .current:
            if selected { parts.append(onTag) }
        }
        return parts.joined(separator: " ・")
    }

    /// 行の1行目
    static func candidateTitle(_ c: Candidate) -> String {
        c.availability == .noPlace ? noPlaceTitle : placeName(c.label)
    }

    /// 読み上げ（印と理由を文字で）
    static func candidateAccessibility(_ c: Candidate, selected: Bool) -> String {
        let note = candidateNote(c, selected: selected)
        return note.isEmpty ? candidateTitle(c) : "\(candidateTitle(c))、\(note)"
    }

    /// 「2026.10.03」（読めなければ nil）
    static func dayText(_ label: TrunkLabel) -> String? {
        label.day.map { String(format: "%04d.%02d.%02d", $0.year, $0.month, $0.day) }
    }
}
