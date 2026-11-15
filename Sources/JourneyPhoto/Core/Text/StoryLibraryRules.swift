import Foundation

/// ストーリーの「＋」で先に開く**最近の写真と動画の一覧**の決まり（札 #627・2026-11-15 判断）。
///
/// owner「ストーリーを追加押すとカメラ起動しちゃう！」。今のインスタと同じ形にする:
/// 「＋」を押すと写真と動画の一覧が先に開き、**最初のマスはカメラ**。マスを押すとそのまま作る画面へ進む。
///
/// | 操作 | 前 | 今 |
/// |---|---|---|
/// | 写真を載せる | 「＋ → 写真へ切り替え → 選ぶ」の3回 | 「＋ → 選ぶ」の2回 |
/// | 撮る | 「＋」の1回 | 「＋ → カメラのマス」の2回 |
///
/// アイコン長押しの「ストーリーを撮る」は今のままカメラを先頭に開く（撮りたい人の近道）。
///
/// 一覧は端末の写真ライブラリを自分で並べるので**許可が要る**。許可の段ごとの出し方:
/// - すべて許可: 一覧（新しい順・写真と動画）
/// - 一部だけ許可: 許された写真の一覧と、1行の「写真を増やす」
/// - まだ聞いていない・許可していない: 今の写真選び（PHPicker・許可が要らない）と、1行の「すべての写真をここに並べる」
///
/// 画面（`StoryLibraryGrid`・`StoryComposerView`）から**判断だけ**を出して試せるようにしたもの
enum StoryLibraryRules {

    // MARK: - 許可の段で出し方を決める

    /// 写真を選ぶ段の中身
    enum Content: Equatable {
        /// 自前の一覧（先頭はカメラのマス）。`limited` は「一部だけ許可」の1行を足す
        case grid(limited: Bool)
        /// 今の写真選び（埋め込みの PHPicker）。`offer` はその上に出す1行
        case systemPicker(offer: AccessOffer?)
    }

    /// 許可を増やす1行の中身
    enum AccessOffer: Equatable {
        /// まだ聞いていない: 押すと iOS の許可のダイアログ
        case ask
        /// 許可していない: 押すと設定の画面
        case openSettings
    }

    /// 許可の段から、写真を選ぶ段の中身を決める。**「制限」（保護者の決まり）は本人が変えられないので1行を出さない**
    static func content(for access: StoryCameraRules.LibraryAccess) -> Content {
        switch access {
        case .authorized: return .grid(limited: false)
        case .limited: return .grid(limited: true)
        case .notDetermined: return .systemPicker(offer: .ask)
        case .denied: return .systemPicker(offer: .openSettings)
        case .restricted: return .systemPicker(offer: nil)
        }
    }

    /// 許可を増やす1行の言葉（押す前に何が起きるか分かる言葉・説明は1行まで）
    static func offerTitle(_ offer: AccessOffer) -> String {
        switch offer {
        case .ask: return L("すべての写真をここに並べる", "Show all your photos here")
        case .openSettings: return L("設定で写真へのアクセスを許可", "Allow photo access in Settings")
        }
    }

    /// 1行の読み上げの補足（押すと何が開くか）
    static func offerHint(_ offer: AccessOffer) -> String {
        switch offer {
        case .ask: return L("写真へのアクセスを尋ねます。許可すると、押すだけで選べます",
                            "Asks for photo access. Once allowed, one tap picks a photo")
        case .openSettings: return L("設定の画面を開きます", "Opens Settings")
        }
    }

    /// 一部だけ許可した人の1行（左の説明と右の押せる言葉）
    static let limitedNote = L("選んだ写真だけ並んでいます", "Showing only the photos you allowed")
    static let limitedAction = L("写真を増やす", "Add photos")

    /// 写真が1枚も無いときの見出し（`stateTitle`）
    static let emptyTitle = L("まだ写真がありません", "No photos yet")

    // MARK: - 並べ方

    /// 並べる上限（新しい順の先頭から）。**それより古い写真は右上の「アルバム」（PHPicker・検索とアルバムつき）から**。
    /// 数万枚を1つの格子に載せない（下まで指で送る人はいない・格子の行を作る数を抑える）
    static let maxItems = 3000

    /// 列の数。**板の決まり: 格子は3列、アクセシビリティの大きさでは2列**（DesignSystem「格子は 3 列→2 列」）
    static func columns(accessibilitySize: Bool) -> Int { accessibilitySize ? 2 : 3 }

    /// マスの縦横比（幅 ÷ 高さ）。**作る画面の写真の枠（およそ 390×610・0.64）に近い 2:3**——
    /// マスで見た切り取りが、作る画面に入ったときとほぼ同じになる
    static let cellAspect: Double = 2.0 / 3.0

    /// 一覧の1件（端末の写真ライブラリの1枚・1本）
    struct Item: Equatable, Identifiable {
        /// `PHAsset.localIdentifier`
        let id: String
        let isVideo: Bool
        /// 動画の長さ（秒）。写真は 0
        let duration: Double
        let date: Date?
    }

    // MARK: - 動画の長さの印

    /// マスの右下の長さ（「0:15」「1:05」「1:02:03」）。**四捨五入でなく切り上げ**——0.4 秒の動画を「0:00」にしない
    static func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 読み上げの長さ（「15秒」「1分5秒」）
    static func spokenDuration(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded(.up)))
        let minutes = total / 60
        let secs = total % 60
        if minutes == 0 { return L("\(secs)秒", "\(secs) seconds") }
        if secs == 0 { return L("\(minutes)分", "\(minutes) minutes") }
        return L("\(minutes)分\(secs)秒", "\(minutes) min \(secs) sec")
    }

    /// マスの読み上げ（「動画、15秒、11月14日」）。区切りは「、」（中黒で並べない・owner の好み 2026-11-12）
    static func accessibilityLabel(_ item: Item, calendar: Calendar = .current) -> String {
        var parts: [String] = [item.isVideo ? L("動画", "Video") : L("写真", "Photo")]
        if item.isVideo { parts.append(spokenDuration(item.duration)) }
        if let date = item.date {
            let day = calendar.dateComponents([.month, .day], from: date)
            if let month = day.month, let dayOfMonth = day.day {
                parts.append(L("\(month)月\(dayOfMonth)日", "\(month)/\(dayOfMonth)"))
            }
        }
        return parts.joined(separator: L("、", ", "))
    }

    // MARK: - 押したとき

    /// マスを押したときにすること
    enum TapAction: Equatable {
        /// そのまま読み込んで作る画面へ（1枚だけ選ぶ・いちばん多い操作）
        case open
        /// 印を付ける・外す（「選択」を入れているとき）
        case toggle
        /// 何もしない（読み込み中・印が上限まで付いていて、印の無いマスを押した）
        case ignore
    }

    /// マスを押したときにすること。**読み込み中は何もしない**（2本の読み込みが混ざって並ぶ・`loadingPicks` の決まり）
    static func tapAction(selecting: Bool, isMarked: Bool, markedCount: Int, loading: Bool) -> TapAction {
        guard !loading else { return .ignore }
        guard selecting else { return .open }
        if isMarked { return .toggle }
        return markedCount < StoryQueue.maxShots ? .toggle : .ignore
    }

    /// 印を付ける・外した後の並び（**選んだ順**＝出る順。外したら詰める）
    static func toggled(_ marked: [String], id: String) -> [String] {
        if let index = marked.firstIndex(of: id) {
            var next = marked
            next.remove(at: index)
            return next
        }
        guard marked.count < StoryQueue.maxShots else { return marked }
        return marked + [id]
    }

    /// 印の番号（1から）。印が無ければ nil
    static func markNumber(_ marked: [String], id: String) -> Int? {
        marked.firstIndex(of: id).map { $0 + 1 }
    }

    /// カメラのマスを押せるか。**「選択」を入れている間は押せない**——印の写真と撮った1枚の順が分からなくなる
    static func cameraEnabled(selecting: Bool, loading: Bool) -> Bool { !selecting && !loading }
}
