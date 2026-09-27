import Foundation

/// 読み込んだアルバムの一覧に、この画面で書いた分（作った・名前を変えた・
/// 招待リンクを作った／取り消した・消した）を重ねる。
///
/// サーバーの一覧（`listAlbums`）は結果整合で読むので、書いた直後の読み込みは
/// 書く前の姿を返しうる。そのまま採ると、作ったアルバムが消え、消したアルバムが
/// 戻り、名前や招待リンクが巻き戻っていた（書き込みの前に始めた読み込みの返事も同じ）。
///
/// **重ねるのは、一覧に反映されるまでか、書いてから `window` 秒まで。**
/// ずっと重ねると、その後に Web や別の端末で名前を変えた・消した分が、
/// この画面では画面を出るまで見えなくなる。消した分だけは持ち続ける
/// （ID は戻らない）
enum AlbumMerge {

    static let window: TimeInterval = 30

    struct Stamped<Value: Equatable>: Equatable {
        let value: Value
        let at: Date
    }

    struct Writes: Equatable {
        var created: [Stamped<Album>] = []
        var renamed: [String: Stamped<String>] = [:]
        /// 招待リンク。nil は取り消した
        var invites: [String: Stamped<AlbumService.Invite?>] = [:]
        var deleted: Set<String> = []
    }

    static func merge(loaded: [Album], writes: Writes) -> [Album] {
        let loadedIds = Set(loaded.map(\.id))
        let missing = writes.created.reversed().map(\.value).filter {
            !loadedIds.contains($0.id) && !writes.deleted.contains($0.id)
        }
        return (missing + loaded)
            .filter { !writes.deleted.contains($0.id) }
            .map { album in
                let title = writes.renamed[album.id]?.value ?? album.title
                let invite = writes.invites[album.id]
                let token = invite.map { $0.value?.token } ?? album.inviteToken
                let expires = invite.map { $0.value?.expiresAt } ?? album.inviteExpiresAt
                guard title != album.title || token != album.inviteToken
                        || expires != album.inviteExpiresAt else { return album }
                return Album(id: album.id, title: title, createdAt: album.createdAt,
                             memberCount: album.memberCount, inviteToken: token,
                             inviteExpiresAt: expires)
            }
    }

    /// 一覧に反映された書き込みと、古くなった書き込みを外す
    static func settled(_ writes: Writes, loaded: [Album], now: Date = Date()) -> Writes {
        let byId = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fresh: (Date) -> Bool = { now.timeIntervalSince($0) < window }
        var next = writes
        next.created.removeAll { byId[$0.value.id] != nil || !fresh($0.at) }
        next.renamed = next.renamed.filter { byId[$0.key]?.title != $0.value.value && fresh($0.value.at) }
        next.invites = next.invites.filter {
            byId[$0.key]?.inviteToken != $0.value.value?.token && fresh($0.value.at)
        }
        return next
    }
}
