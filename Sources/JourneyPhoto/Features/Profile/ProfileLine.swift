import Foundation

/// プロフィールの見出しの下に並べる文字（板 05c・05d）。
enum ProfileLine {

    /// 「@ユーザー名 · 居住地」の1行（板: 12px・白60%）。片方だけならその片方、
    /// どちらも無ければ出さない。
    ///
    /// **居住地の頭のピンは線の印**（板: 11px の線のピン）で、画面側で描く。
    /// 以前は絵文字の「📍」を文字に混ぜていて、板と違う赤いピンが出ていた
    struct HandleAndHome: Equatable {
        let handle: String?
        let home: String?

        /// 読み上げ。印は読まれないので「居住地」と言葉で添える
        var spoken: String {
            [handle, home.map { L("居住地 \($0)", "Lives in \($0)") }]
                .compactMap { $0 }
                .joined(separator: L("、", ", "))
        }
    }

    static func handleAndHome(username: String?, home: String?) -> HandleAndHome? {
        let handle = username.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "@\($0)" }
        let place = home.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        guard handle != nil || place != nil else { return nil }
        return HandleAndHome(handle: handle, home: place)
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
