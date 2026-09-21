import Foundation

/// 機種名の整え。Web の `lib/utils/cameraName.ts` の写し。
///
/// **保存済みの値にはメーカー名が二重に残っている**（実データに
/// `"Hasselblad Hasselblad X2D II 100C"`）。EXIF の `Make` と `Model` を
/// 繋ぐときに、`Model` 側が既にメーカー名から始まっていると重なる。
///
/// **通さないと同じ機種が2つに割れる。** Web は集約ページ
/// （`/camera/*`）の値をこれで揃えているので、アプリだけ生の値を使うと
/// 同じ写真が別の機種として数えられ、画面にも二重の名前が出る。
enum CameraName {

    /// 先頭の語が続きにもう一度現れるなら、**1つぶんだけ**落とす。
    /// 空なら nil（呼ぶ側が「出さない」を決める）。
    static func deduped(_ camera: String?) -> String? {
        let value = (camera ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !value.isEmpty else { return nil }
        guard let space = value.firstIndex(of: " ") else { return value }
        let first = String(value[value.startIndex..<space])
        let rest = String(value[value.index(after: space)...])
        // **「先頭の語 ＋ 空白」で始まっているときだけ。** 単に先頭の語を
        // 含むだけで落とすと、`Canon EOS Canon` のような並びまで削る
        return rest.lowercased().hasPrefix(first.lowercased() + " ") ? rest : value
    }
}
