import SwiftUI

/// **旅とオフライン保存の画面の v2 の決まり**（v2 の板 Trips・TripBook・TripPlans・TripPlanDays・
/// TripPlanPick・OfflineTripSave・OfflineSaveStates・OfflineTrip・OfflineSpot・OfflineSaved、2026-10-14）。
///
/// 値はここに数だけで持つ（Linux のテストで見張る・`TripsDesignTests`）。余白・角・線・字の段は
/// 土台（`JPSpace`・`JPRadius`・`JPStroke`・`JPTypeScale`）を使い、ここには**旅の画面にしか無い寸法**だけを置く。
enum TripStyle {

    // MARK: 旅の一覧（板 Trips）

    /// いちばん新しい一冊の大きな表紙の札の高さ（板 190）
    static let coverCardHeight: CGFloat = 190
    /// 残りの一冊の行の高さ（板 72）
    static let rowMinHeight: CGFloat = 72
    /// 行の写真（板 72×56・角 10 は `JPRadius.s`）
    static let rowThumb = CGSize(width: 72, height: 56)
    /// 表紙の札の下の暗さ（板: 黒 72% → 65% の所で 0）
    static let coverCardShade = 0.72

    // MARK: 旅の一冊（板 TripBook）

    /// 表紙の上の暗さ（板: 黒 50% から 140pt で 0。戻るのガラスの丸を写真の上で読ませる）
    static let bookTopShade = 0.5
    static let bookTopShadeHeight: CGFloat = 140
    /// たどった場所の図の地（板 #0B0C0E）
    static let routeGround: UInt32 = 0x0B0C0E
    /// 図の線（板 1.4 の真鍮の実線。v1 の点線をやめた）
    static let routeLineWidth: CGFloat = 1.5
    /// 図の番号の丸（板 r9・終点だけ r10 の真鍮の塗り）
    static let routeDot: CGFloat = 18

    // MARK: 旅行プラン（板 TripPlans・TripPlanDays・TripPlanPick）

    /// 札の左の組み絵の枠（板 64・角 12 は `JPRadius.field`）
    static let planThumb: CGFloat = 64
    /// 「出発まで N 日」を出すのは、出発がこの日数の内に来るときだけ（2026-10-14 判断: 板は「近い札だけ」と
    /// 書くだけで日数を決めていない。2週間＝旅の支度を始める頃）
    static let departureWindowDays = 14
    /// 日付の欄の高さ（板 52）
    static let dateFieldHeight: CGFloat = 52
    /// 場所の番号の丸（板 24・真鍮の線 1.4）。線は 1.5 にそろえる（`JPStroke` の 1 と 2 の間・2 では
    /// 24 の丸の中で数字が窮屈）
    static let stopNumberSide: CGFloat = 24
    static let stopNumberStroke: CGFloat = 1.5
    /// 選ぶ行の高さ（板 68）と、左の絵（板 48・角 10）
    static let pickRowMinHeight: CGFloat = 68
    static let pickThumb: CGFloat = 48
    /// 選んだ印の丸（板 26）
    static let pickMark: CGFloat = 26
    /// 押せない「作る」の濃さ（板 0.32）
    static let disabledOpacity = 0.32

    // MARK: 電波なしで使う（板 OfflineTripSave・OfflineSaveStates・OfflineSaved）

    /// 保存の進みの線の太さ（板 4・v1 は 6）
    static let progressHeight: CGFloat = 4
    /// 進みの線の地（白 10%）
    static let progressTrackOpacity = 0.10
    /// 途中で止まった進みの真鍮の濃さ（板 50%）
    static let stalledProgressOpacity = 0.5
    // 「端末から削除」の線の赤の濃さ・確かめの「削除する」の地と線は土台の `JPOutlineTone`（2026-10-14）
    /// 圏外の場所の光の時刻の行（板 36）
    static let lightRowMinHeight: CGFloat = 36
    /// 保存した旅の行（板 84）と写真（板 56）
    static let savedRowMinHeight: CGFloat = 84
    static let savedThumb: CGFloat = 56

    // MARK: - 計算（Linux で試す）

    /// 一冊の写真が**どれも撮影日を持たない**（投稿した日でまとめた旅）。板の「投稿日でまとめています」の札
    nonisolated static func groupedByUploadDate(_ photos: [Photo]) -> Bool {
        !photos.isEmpty && photos.allSatisfy { ($0.date ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 一覧の行・表紙の札の下の1行（「2026.09.12 — 09.14 · 3日間 · 24枚」）
    nonisolated static func tripLine(_ trip: TripBook.Trip) -> String {
        "\(TripBook.dateRange(from: trip.start, to: trip.end))\u{2002}\(TripBook.daysLabel(trip.days))\u{2002}\(PhotoMapViewModel.photoCountLabel(trip.photos.count))"
    }

    /// 一冊のページの写真の下の1行（板「07:12 · 24mm · f/8」）。**持っているものだけを繋ぐ**。
    /// 時刻はカメラが書いた撮影時刻で、撮影日と食い違えば出さない（`PhotoMetaLine.stamp` と同じ決まり）
    nonisolated static func pageMeta(_ photo: Photo) -> String? {
        var parts: [String] = []
        if let stamp = PhotoMetaLine.stamp(date: photo.date, exifDateTime: photo.exif?.dateTimeOriginal),
           let range = stamp.range(of: PhotoMetaLine.separator) {
            parts.append(String(stamp[range.upperBound...]))
        }
        if let focal = trimmed(photo.exif?.focalLength) {
            parts.append(focal.allSatisfy { $0.isNumber || $0 == "." } ? "\(focal)mm" : focal)
        }
        if let aperture = trimmed(photo.exif?.aperture) {
            parts.append(aperture.lowercased().hasPrefix("f") ? aperture : "f/\(aperture)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: PhotoMetaLine.separator)
    }

    /// 出発までの日数（`YYYY-MM-DD` 同士を暦の日で数える）。読めなければ nil
    nonisolated static func daysUntil(start: String?, today: String) -> Int? {
        guard let s = TakenDay.ymd(start), let t = TakenDay.ymd(today) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let from = calendar.date(from: DateComponents(year: t.0, month: t.1, day: t.2)),
              let to = calendar.date(from: DateComponents(year: s.0, month: s.1, day: s.2)) else { return nil }
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    /// 札の真鍮の眉「出発まで 3 日」。**出発が `departureWindowDays` の内に来るプランだけ**（板）
    nonisolated static func departureEyebrow(start: String?, today: String) -> String? {
        guard let days = daysUntil(start: start, today: today), days >= 0, days <= departureWindowDays else { return nil }
        if days == 0 { return L("今日出発", "Leaving today") }
        return L("出発まで \(days) 日", days == 1 ? "1 day to go" : "\(days) days to go")
    }

    /// 帰ってきたプラン（帰着の日が今日より前）。札を灰にして「帰着済み」と添える（板）
    nonisolated static func isFinished(end: String?, today: String) -> Bool {
        guard let days = daysUntil(start: end, today: today) else { return false }
        return days < 0
    }

    /// プランの札の下の1行（板「2026年10月17日 〜 10月18日 · 6か所」・帰った旅は「· 帰着済み」）
    nonisolated static func planLine(start: String?, end: String?, places: Int, finished: Bool) -> String {
        var parts = [TripPlanText.period(start: start, end: end) ?? L("日付未定", "No dates yet"),
                     TripPlanText.placeCount(places)]
        if finished { parts.append(L("帰着済み", "Back home")) }
        return parts.joined(separator: "\u{2002}")
    }

    /// 日程の通し番号（板: 1日目 1・2、2日目 3 …）。日ごとに、その日の項目の番号を返す
    nonisolated static func stopNumbers(_ counts: [Int]) -> [[Int]] {
        var next = 1
        return counts.map { count in
            defer { next += count }
            return Array(next..<(next + max(count, 0)))
        }
    }

    /// 選んでよい残りの数（1日に置ける数 − いまある数）。0 未満にしない
    nonisolated static func remaining(dayCount: Int, max: Int) -> Int {
        Swift.max(max - dayCount, 0)
    }

    /// 「保存した旅」の容量の線の割合（使っている分 ÷（使っている分＋空き））。空きが読めなければ nil（線を出さない）
    nonisolated static func usageFraction(used: Int64, free: Int64?) -> Double? {
        guard let free, free >= 0 else { return nil }
        let total = Double(max(used, 0)) + Double(free)
        guard total > 0 else { return nil }
        return min(max(Double(max(used, 0)) / total, 0), 1)
    }

    /// 「48 MB」を数と単位に分ける（板: 数は細い大きな数字、単位は 13 の灰）。分けられなければ単位は空
    nonisolated static func splitBytes(_ label: String) -> (number: String, unit: String) {
        guard let space = label.lastIndex(of: " "), label.hasSuffix("B") else { return (label, "") }
        return (String(label[..<space]), String(label[label.index(after: space)...]))
    }

    private nonisolated static func trimmed(_ s: String?) -> String? {
        let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}

/// 場所の番号の丸（板 TripPlanDays・OfflineTrip: 24・**真鍮の線と真鍮の数字**・地は黒）。
/// 旅行プランの日程と、圏外の旅行プランで同じ形を使う。地図の画像の点と同じ番号
struct TripStopNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(JPFont.number(JPTypeScale.caption, weight: .bold))
            .foregroundStyle(WebTheme.accent)
            .frame(width: TripStyle.stopNumberSide, height: TripStyle.stopNumberSide)
            .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: TripStyle.stopNumberStroke))
            .accessibilityHidden(true)
    }
}

/// 線の小ボタン（板 `.bo`: 44・白 14% の線・15 の semibold）。**幅は中身に合わせる**
/// （`fill` で札の幅いっぱい）。危ないもの（端末から削除）は赤の字に赤 40% の線。
/// 形は土台の `jpOutlineButton`（2026-10-14 判断: 線の小ボタンを1つに寄せた）
struct TripOutlineButton: View {
    let title: String
    var danger = false
    /// 削除の確かめの「削除する」（赤 16% の地・赤 50% の線・白の字）
    var strong = false
    var fill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .jpOutlineButton(.regular, tone: strong ? .strong : danger ? .danger : .plain, fullWidth: fill)
        }
        .buttonStyle(.plain)
    }
}

/// 保存の進み（板 OfflineTripSave: 高さ 4・白 10% の地に真鍮。途中で止まったら真鍮 50%）
struct OfflineProgressBar: View {
    let done: Int
    let total: Int
    var stalled = false

    var body: some View {
        let fraction = total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(TripStyle.progressTrackOpacity))
                Capsule()
                    .fill(WebTheme.accent.opacity(stalled ? TripStyle.stalledProgressOpacity : 1))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: TripStyle.progressHeight)
        .accessibilityElement()
        .accessibilityLabel(L("端末への保存", "Saving to this iPhone"))
        .accessibilityValue(OfflineTripText.progressAccessibility(done: done, total: total))
    }
}

/// 日程の行の中身（板 TripPlanDays: 真鍮の番号の丸 → 撮影スポットは明朝・撮影地は SF の太字 →
/// 季節の一文と時間帯の札（F30）→ ひとこと）。**作る流れの下書きと日程の画面で同じ部品**（2026-11-10・札 #521）
struct TripStopLabel: View {
    let number: Int
    let name: String
    let isSpot: Bool
    /// 「冬（12月）· …」。台帳に案内の無い行・撮影地・日付の無いプランは nil
    var season: String? = nil
    /// 「夜明け · 朝」。案内の無い行は nil
    var timeChip: String? = nil
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            TripStopNumber(number: number)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(name)
                    .font(isSpot ? JPFont.rowTitle : JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if season != nil || timeChip != nil {
                    // 季節の一文（白 60%・12）と時間帯の札（白 5% の地・白 10% の縁・12 の 600）
                    TripWrapRow {
                        if let season {
                            Text(season)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(2)
                        }
                        if let timeChip {
                            TripTimeChip(text: timeChip)
                        }
                    }
                }
                // 添えたひとこと（あるときだけ）
                if let note, !note.isEmpty {
                    Text(note)
                        .font(JPFont.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, JPSpace.s)
        .frame(minHeight: JPHeight.tallRow)
        .contentShape(Rectangle())
        // 読み上げは「1 · 名前 · 季節 · 時間帯 · ひとこと」（番号の丸は絵として隠している）
        .accessibilityElement(children: .combine)
        .accessibilityLabel([String(number), name, season, timeChip, note].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: "\u{2002}"))
    }
}

/// 時間帯の札（板 TripPlanDays F30 の `夜景 · 夜`）
struct TripTimeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.caption.weight(.semibold))
            .foregroundStyle(WebTheme.muted)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: JPStroke.hairline))
            .fixedSize()
    }
}

/// 季節の一文と札を並べる（字が大きいときは縦に積む・`ViewThatFits`）
struct TripWrapRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) { content() }
            VStack(alignment: .leading, spacing: JPSpace.xxs) { content() }
        }
    }
}

/// 日の見出しの下の1行（日の出・日の入り / 重なり / 間に合わないとき）。字は 12・白 60%（知らせは白 72%）
struct TripDayNote: View {
    let text: String
    var symbol: String? = nil
    var strong = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(JPFont.caption)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(JPFont.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(strong ? WebTheme.muted2 : WebTheme.faint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 日の出・日の入りの1行の字（「日の出 7:02 · 日の入り 16:45」）
enum TripSunText {
    static func line(_ sun: TripDraft.Sun) -> String? {
        var parts: [String] = []
        if let r = sun.sunrise { parts.append(L("日の出 \(r)", "Sunrise \(r)")) }
        if let s = sun.sunset { parts.append(L("日の入り \(s)", "Sunset \(s)")) }
        return parts.isEmpty ? nil : parts.joined(separator: "\u{2002}")
    }
}
