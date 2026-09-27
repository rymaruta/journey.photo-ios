import Foundation

/// 写真の編集で、撮影日の欄に出す値と送る値。
///
/// **欄は保存されている撮影日（`photo.date`）から出す。** EXIF から出して
/// 毎回送っていたので、Web で撮影日を直した写真をアプリで開き、タグだけ
/// 直して保存すると EXIF の日付に戻っていた。時刻付きで保存されている
/// 写真（`2026-09-13T08:21:05`）は、保存のたびに時刻が落ちて同じ日の
/// 並び順が崩れていた。Web の `lib/utils/dateInput.ts`
/// （`toDateInputValue` / `mergeDate`）と同じ考え。
enum EditDay {

    /// 欄に出す `YYYY-MM-DD`。**保存された撮影日が無ければ空**（Web と同じ）。
    ///
    /// EXIF に落とすと、欄に日付が見えているのに触らなければ送らないので
    /// 保存されない。送るようにすると、カメラの日付が未設定の写真
    /// （`1980:01:01`）で保存そのものが 400 に落ちる
    static func field(date: String?) -> String {
        guard let date else { return "" }
        return leadingDay(date) ?? ""
    }

    /// 送る値。**欄を触っていなければ nil**（送らない＝時刻も保つ）。
    /// 空も送らない（空文字は api-user の日付検査に落ちる）
    static func toSend(opened: String, field: String) -> String? {
        let day = field.trimmingCharacters(in: .whitespaces)
        guard !day.isEmpty, day != opened else { return nil }
        return day
    }

    /// 先頭の `YYYY-MM-DD`（`2026-09-13T08:21:05` や `…Z` の形も）
    private static func leadingDay(_ raw: String) -> String? {
        let head = String(raw.prefix(10))
        guard head.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return head
    }
}
