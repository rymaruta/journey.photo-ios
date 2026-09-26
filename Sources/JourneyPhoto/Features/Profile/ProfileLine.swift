import Foundation

/// プロフィールの見出しの下に並べる文字（板 05c・05d）。
enum ProfileLine {

    /// 「@ユーザー名 · 居住地」の1行（板: 12px・白60%）。片方だけならその片方、
    /// どちらも無ければ出さない。居住地の頭のピンは文字で付ける（1行で折り返す
    /// ときに印だけ取り残されないように）
    static func handleAndHome(username: String?, home: String?) -> String? {
        let handle = username.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "@\($0)" }
        let place = home.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "📍\($0)" }
        let parts = [handle, place].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// ひとことと自己紹介（板は「ひとことプロフィール」の1段落）。**空は出さない・
    /// 同じ文は二度出さない**（Web で両方に同じ文を入れている人がいる）
    static func about(status: String?, bio: String?) -> [String] {
        var lines: [String] = []
        for text in [status, bio] {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty, !lines.contains(trimmed) else { continue }
            lines.append(trimmed)
        }
        return lines
    }

    /// 格子の1枚の状態の読み上げ（ピン・下書き・複数枚）。**印は絵では見えるが
    /// 読まれないので、値として読む**
    static func gridState(pinned: Bool, draft: Bool, multiple: Bool) -> String {
        [pinned ? L("ピン留め中", "Pinned") : nil,
         draft ? L("下書き", "Draft") : nil,
         multiple ? L("複数枚の投稿", "Multiple photos") : nil]
            .compactMap { $0 }
            .joined(separator: L("、", ", "))
    }
}
