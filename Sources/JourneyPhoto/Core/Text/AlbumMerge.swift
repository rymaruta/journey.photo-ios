import Foundation

/// 読み込んだアルバムの一覧に、この画面で作った・名前を変えた・消した分を重ねる。
///
/// サーバーの一覧（`listAlbums`）は結果整合で読むので、書いた直後の読み込みは
/// 書く前の姿を返しうる。そのまま採ると、作ったアルバムが消え、消したアルバムが
/// 戻り、名前が巻き戻っていた（書き込みの前に始めた読み込みの返事も同じ）。
/// **一覧に反映されたと確かめられた分は、以後サーバーを信じる**（`settled`）
enum AlbumMerge {

    struct Writes: Equatable {
        var created: [Album] = []
        var renamed: [String: String] = [:]
        var deleted: Set<String> = []
    }

    static func merge(loaded: [Album], writes: Writes) -> [Album] {
        let loadedIds = Set(loaded.map(\.id))
        let missing = writes.created.reversed().filter {
            !loadedIds.contains($0.id) && !writes.deleted.contains($0.id)
        }
        return (missing + loaded)
            .filter { !writes.deleted.contains($0.id) }
            .map { album in
                guard let title = writes.renamed[album.id], title != album.title else { return album }
                return Album(id: album.id, title: title, createdAt: album.createdAt,
                             memberCount: album.memberCount, inviteToken: album.inviteToken,
                             inviteExpiresAt: album.inviteExpiresAt)
            }
    }

    /// 一覧に反映された書き込みを外す（消した分は ID が戻らないので持ち続ける）
    static func settled(_ writes: Writes, loaded: [Album]) -> Writes {
        let byId = Dictionary(loaded.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var next = writes
        next.created.removeAll { byId[$0.id] != nil }
        next.renamed = next.renamed.filter { byId[$0.key] != $0.value }
        return next
    }
}
