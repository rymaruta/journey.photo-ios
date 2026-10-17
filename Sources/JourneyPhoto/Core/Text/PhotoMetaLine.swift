import Foundation

/// 写真の詳細（板 02）とビューア（板 14）の小さい1行たち。
///
///     題の下      2026.09.12 · 17:42 · 1/3枚
///     ビューア上  1 / 3（読み上げは「3枚中1枚目」）
///     ビューア下  SONY ILCE-7M3 · E 28-200mm · f/3.2 · 1/400s · ISO 500
///
/// **持っているものだけを繋ぐ。** 空の欠片に区切りだけが残る
/// （「 · 17:42」）行を作らない。
enum PhotoMetaLine {

    /// 区切り（板の ` · `）
    static let separator = " · "

    // MARK: - 撮影日時

    /// 「2026.09.12 · 17:42」。
    ///
    /// **日付は `date`、時刻は EXIF の `dateTimeOriginal` からだけ取る。**
    /// `date` に時刻が付いている行はあるが、それは撮った時刻とは限らない
    /// （`TakenDay` の注記）。カメラが書いた撮影時刻なら出してよい。
    ///
    /// EXIF の日付が `date` と食い違うときは**時刻を出さない**
    /// ——持ち主が撮影日を直した写真に、別の日の時刻を添えることになる。
    ///
    /// 書式は2通り来る: Web は `2024-10-12T09:00:00`、アプリは
    /// EXIF の生の `2024:10:12 09:00:00`（`ImagePreparer`）。
    static func stamp(date: String?, exifDateTime: String?) -> String? {
        let exif = parts(exifDateTime)
        guard let day = TakenDay.ymd(date) ?? exif.map({ ($0.y, $0.m, $0.d) }) else { return nil }
        let (y, m, d) = day
        var line = "\(y).\(pad(m)).\(pad(d))"
        if let exif, let hh = exif.hh, let mm = exif.mm,
           exif.y == y, exif.m == m, exif.d == d {
            line += separator + "\(pad(hh)):\(pad(mm))"
        }
        return line
    }

    /// 同じ投稿の何枚目か（「1/3枚」）。**1枚だけの投稿には出さない**
    /// ——「1/1枚」は何も伝えない
    static func groupPosition(_ position: Int, of total: Int) -> String? {
        guard total > 1 else { return nil }
        let p = min(max(position, 1), total)
        return L("\(p)/\(total)枚", "\(p) of \(total)")
    }

    /// 題の下の1行（板 02）。日時も枚数も無ければ nil（行ごと出さない）
    static func headline(date: String?, exifDateTime: String?,
                         position: Int, of total: Int) -> String? {
        let parts = [stamp(date: date, exifDateTime: exifDateTime),
                     groupPosition(position, of: total)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    // MARK: - ビューア

    /// ビューアの上の「1枚目 / 3」（板 14）。**送る先が無ければ出さない**。
    /// - Parameter index: 0 始まり
    ///
    /// **v2（2026-10-14・板 PhotoViewer）: 画面の字は「1 / 3」**（等幅の数字だけ）。読み上げは
    /// 「3枚中1枚目」（`viewerPositionSpoken`）——数字と斜線だけでは何の数か伝わらない
    static func viewerPosition(_ index: Int, of total: Int) -> String? {
        guard total > 1 else { return nil }
        let p = min(max(index + 1, 1), total)
        return "\(p) / \(total)"
    }

    /// ビューアの「1 / 3」の読み上げ（板の `aria-label="3枚中1枚目"`）
    static func viewerPositionSpoken(_ index: Int, of total: Int) -> String? {
        guard total > 1 else { return nil }
        let p = min(max(index + 1, 1), total)
        return L("\(total)枚中\(p)枚目", "Photo \(p) of \(total)")
    }

    /// ビューアの下の撮影情報の1行（板 14: 機種 · レンズ · f · s · ISO）。
    ///
    /// 機種は `CameraName.deduped` を通す（二重のメーカー名を出さない）。
    /// シャッターはアプリが `1/400`、Web が `1/400s` で保存しているので
    /// **秒の「s」を揃える**。絞りは `f/` の付かない値も受け止める
    static func exifLine(_ exif: Photo.Exif?) -> String? {
        guard let exif else { return nil }
        let items = [CameraName.deduped(exif.camera), trimmed(exif.lens), aperture(exif), exposure(exif), iso(exif)]
            .compactMap { $0 }
        return items.isEmpty ? nil : items.joined(separator: separator)
    }

    /// 機材の1行（v2 の板 PhotoViewer の下の1行目: 機種 · レンズ）。無ければ nil
    static func gearLine(_ exif: Photo.Exif?) -> String? {
        guard let exif else { return nil }
        let items = [CameraName.deduped(exif.camera), trimmed(exif.lens)].compactMap { $0 }
        return items.isEmpty ? nil : items.joined(separator: separator)
    }

    /// 撮影設定の1行（v2 の板 PhotoDetail の撮影情報の要約・PhotoViewer の下の2行目:
    /// 「24mm · f/8 · 1/125s · ISO 100」）。焦点距離 → 絞り → シャッター → ISO。
    /// 書き方は `exifLine` と同じ（`f/` を付ける・秒の「s」を揃える）。無ければ nil
    static func settingsLine(_ exif: Photo.Exif?) -> String? {
        guard let exif else { return nil }
        let items = [trimmed(exif.focalLength), aperture(exif), exposure(exif), iso(exif)].compactMap { $0 }
        return items.isEmpty ? nil : items.joined(separator: separator)
    }

    /// 撮影情報を開いたときの升目（v2 の板 PhotoDetail: 焦点距離・絞り・シャッター・ISO）。
    /// **無いものは詰める**——空の升を立てない
    static func settingsCells(_ exif: Photo.Exif?) -> [(label: String, value: String)] {
        guard let exif else { return [] }
        let cells: [(String, String?)] = [
            (L("焦点距離", "Focal length"), trimmed(exif.focalLength)),
            (L("絞り", "Aperture"), aperture(exif)),
            (L("シャッター", "Shutter"), exposure(exif)),
            ("ISO", exif.iso.flatMap { $0 > 0 ? "\($0)" : nil }),
        ]
        return cells.compactMap { label, value in value.map { (label, $0) } }
    }

    private static func aperture(_ exif: Photo.Exif) -> String? {
        trimmed(exif.aperture).map { $0.lowercased().hasPrefix("f") ? $0 : "f/\($0)" }
    }

    private static func exposure(_ exif: Photo.Exif) -> String? {
        trimmed(exif.exposure).map { $0.hasSuffix("s") ? $0 : "\($0)s" }
    }

    private static func iso(_ exif: Photo.Exif) -> String? {
        exif.iso.flatMap { $0 > 0 ? "ISO \($0)" : nil }
    }

    // MARK: - 内側

    /// 撮影日時の成分。季節・時間帯の絞り込み（`ShootingTime`）も同じ読み方を使う
    struct Parts: Equatable {
        let y: Int, m: Int, d: Int
        let hh: Int?, mm: Int?
    }

    /// `YYYY-MM-DD[T ]HH:MM` と `YYYY:MM:DD HH:MM` を成分に分ける。
    /// 読めない値は nil、読めない時刻は日付だけにする（Web の `splitStoredDate`）
    static func parts(_ raw: String?) -> Parts? {
        guard let raw = trimmed(raw), raw.count >= 10 else { return nil }
        let head = raw.prefix(10).replacingOccurrences(of: ":", with: "-")
        guard let (y, m, d) = TakenDay.ymd(head) else { return nil }
        let rest = raw.dropFirst(10)
        guard let mark = rest.first, mark == "T" || mark == " " else {
            return Parts(y: y, m: m, d: d, hh: nil, mm: nil)
        }
        let clock = rest.dropFirst().split(separator: ":")
        guard clock.count >= 2, let hh = Int(clock[0]), let mm = Int(clock[1].prefix(2)),
              (0...23).contains(hh), (0...59).contains(mm) else {
            return Parts(y: y, m: m, d: d, hh: nil, mm: nil)
        }
        return Parts(y: y, m: m, d: d, hh: hh, mm: mm)
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func trimmed(_ s: String?) -> String? {
        let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
