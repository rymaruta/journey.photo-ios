import Foundation

/// 「行きたい場所」を押す・サーバーに合わせる手順（控えは `WishlistStore`・口は `SavedSpotService`）。
///
/// **仕掛けは写真の保存と同じ。** 押した瞬間に控えを変えて送り、失敗したら
/// **押した人の控えだけ**戻す（`PhotoDetailView.toggleSave`）。起動・ログインの
/// 同期は印を取ってから一覧を取り、印の後に押した分を残して入れ替える
/// （`JourneyPhotoApp.syncSaves`・`LocalEdits`）。2つ目の同期の仕組みは作らない。
///
/// 違いは2つ:
///
///  - **失敗を知らせる。** 保存の失敗はしるしが戻るだけだが、こちらは画面が
///    押したそばから「追加しました」と知らせている。戻すだけだと、知らせと
///    しるしが食い違う。サーバーも失敗を 500 / 503 で返す（`savedSpots.ts`——
///    この一覧が唯一の状態なので飲み込まない）
///  - **端末にしか無かった分を送る。** この仕組みより前は端末だけに残して
///    いたので、最初の同期でサーバーに無い分を送る（`WishlistStore.replace`）
@MainActor
enum WishlistSync {

    /// 押した結果（画面の知らせに使う）
    enum Outcome: Equatable {
        /// サーバーまで届いた（`wanted` は押した後の状態）
        case synced(wanted: Bool)
        /// 端末にだけ残した（未ログイン・送れない形の鍵）
        case local(wanted: Bool)
        /// 送れなかった。控えは戻してある
        case failed(wanted: Bool, message: String)
        /// 端末では外したが、外す要求がサーバーに届かなかった（未送信のはずの鍵）。
        /// サーバーに在ったなら次の同期で戻る
        case removedOnThisDevice
        /// 何もしなかった（空の鍵・送っている最中の連打）
        case ignored
    }

    /// 押すたびに入れ替える
    static func toggle(_ key: String, store: WishlistStore, service: SavedSpotService) async -> Outcome {
        guard !key.isEmpty, !store.isSending(key) else { return .ignored }
        return await set(key, wanted: !store.contains(key), store: store, service: service)
    }

    /// 入れる・外す。**控えを先に変え、送れなかったら戻す**
    static func set(_ key: String, wanted: Bool,
                    store: WishlistStore, service: SavedSpotService) async -> Outcome {
        guard !key.isEmpty, !store.isSending(key) else { return .ignored }
        // 戻すのは押した人の控えだけ（待っている間に人が替わったら書かない）
        let owner = store.owner
        // **未送信の鍵を外すのは端末の中だけで済む**（直前の同期でサーバーに無かった鍵）。
        // 答えを待って戻すと、圏外では外せず（「外せませんでした」）、取り消しでは
        // 外したものが未送信に戻って次の同期で送られていた
        let wasUnsent = store.isUnsent(key, for: owner)
        store.set(key, wanted: wanted)
        let sendable = wanted ? SavedSpotService.canSend(key) : SavedSpotService.canRemove(key)
        guard let owner, !owner.isEmpty, sendable else {
            return .local(wanted: wanted)
        }
        if !wanted && wasUnsent {
            // 実はサーバーに在ることがある（送って時間切れになったが書けていた・別の端末が
            // 後から入れた）ので外す要求は送る。**届かなくても戻さない**が、**黙らない**——
            // サーバーに在ったなら次の同期で戻るので、そう言う。
            //
            // 「届かなかった鍵を控えて外し直す」はやめた（0bbfc86 のレビュー）。サーバーの
            // 一覧に時刻が無く、控えた後に**別の端末で入れ直した場所まで黙って消す**。
            // 見えて直せる失敗（戻る）の方が、見えない消失よりまし
            store.beginSending(key)
            defer { store.endSending(key) }
            do {
                try await service.unsave(key)
                return .local(wanted: false)
            } catch {
                // 取り消しでも外したままなので、黙らない（戻ることがあると言う）
                return .removedOnThisDevice
            }
        }
        store.beginSending(key)
        defer { store.endSending(key) }
        do {
            if wanted {
                try await service.save(key)
            } else {
                try await service.unsave(key)
            }
            // 🔴 **届いたら未送信から外す。** 最初の同期の間に押すと未送信に入ったまま残り、
            // その後 Web で外すと、次の同期で「サーバーに無い未送信」として生き返った
            if wanted { store.markSent(key, for: owner) }
            return .synced(wanted: wanted)
        } catch {
            store.set(key, wanted: !wanted, for: owner)
            // 取り消し（画面を離れた）は失敗と言わない
            if error is CancellationError { return .ignored }
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return .failed(wanted: wanted, message: message)
        }
    }

    /// 画面に出す知らせ。**どこに残ったかを言い分ける**
    /// （未ログインの回だけ「この端末に保存」——ログイン中は Web にも出る）
    static func notice(for outcome: Outcome) -> (text: String, kind: ToastCenter.Message.Kind)? {
        switch outcome {
        case .synced(true):
            return (L("「行きたい」に追加しました", "Added to your wishlist"), .success)
        case .local(true):
            return (L("「行きたい」に追加しました（この端末に保存）", "Added to your wishlist on this device"), .success)
        case .synced(false), .local(false):
            return (L("「行きたい」から外しました", "Removed from your wishlist"), .success)
        case .failed(let wanted, let message):
            let head = wanted
                ? L("「行きたい」に追加できませんでした", "Couldn't add to your wishlist")
                : L("「行きたい」から外せませんでした", "Couldn't remove from your wishlist")
            return ("\(head)（\(message)）", .failure)
        case .removedOnThisDevice:
            // 知らせは2行まで（`ToastOverlay`）。注意の印で出す（✓ だと「残るかも」と食い違う）
            // サーバーに在った鍵なら、次の同期でこの端末にも戻る（言い切らない）
            // **「通信できず」とは言わない。** ここに来るのはサーバーの 5xx・断りも
            // 含む（上の `catch` は理由を分けない）ので、電波のせいにすると嘘になる
            return (L("外しました（サーバーで外せず、あとで戻ることがあります）",
                      "Removed. It may come back after syncing."), .failure)
        case .ignored:
            return nil
        }
    }

    /// 外した直後に**黙って済ませない**知らせ（一覧の外すボタン用——成功は行が消えるので言わない）。
    /// 失敗と「この端末だけ外した」は言う
    static func removalNotice(for outcome: Outcome) -> (text: String, kind: ToastCenter.Message.Kind)? {
        switch outcome {
        case .failed, .removedOnThisDevice: return notice(for: outcome)
        // 種類が増えたら、ここで言うか黙るかを決めさせる（`default` にしない）
        case .synced, .local, .ignored: return nil
        }
    }

    /// サーバーの一覧に合わせ、端末にしか無い分を送る（起動・ログインのたび）。
    ///
    /// - Parameters:
    ///   - owner: 取りに行く人（`auth.userId`）
    ///   - mark: **最初の await の前に**取った `store.syncMark`
    ///   - isCurrent: いまもその人がログインしているか。**待つたびに見る**
    ///     （ストアがまだ前の人を指していることがある——`syncSaves` と同じ照合）
    static func sync(owner: String, since mark: LocalEdits.Mark,
                     store: WishlistStore, service: SavedSpotService,
                     isCurrent: () -> Bool) async {
        let slugs = try? await service.mySpots()
        guard !Task.isCancelled, isCurrent(), let slugs else { return }
        let toSend = store.replace(with: slugs, for: owner, since: mark)
        // **1本ずつ送る。** サーバーは1行を CAS で書くので、並べて飛ばすと
        // 競合して 503 になる（`userList.ts`）
        for key in toSend {
            guard !Task.isCancelled, isCurrent() else { return }
            // 🔴 **待っている間に外したものは送らない**
            guard store.isUnsent(key, for: owner), !store.isSending(key) else { continue }
            store.beginSending(key)
            let sent: Bool
            do {
                try await service.save(key)
                sent = true
            } catch {
                // 送れなかった分は未送信のまま控えに残す（次の同期で送り直す）
                sent = false
            }
            store.endSending(key)
            guard sent else { continue }
            store.markSent(key, for: owner)
            // 送っている間に外した（外す要求が先に着いた）なら、外し直す
            if isCurrent(), store.owner == owner, !store.contains(key) {
                _ = try? await service.unsave(key)
            }
        }
    }
}
