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
        store.set(key, wanted: wanted)
        guard let owner, !owner.isEmpty, SavedSpotService.canSend(key) else {
            return .local(wanted: wanted)
        }
        store.beginSending(key)
        defer { store.endSending(key) }
        do {
            if wanted {
                try await service.save(key)
            } else {
                try await service.unsave(key)
            }
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
        case .ignored:
            return nil
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
