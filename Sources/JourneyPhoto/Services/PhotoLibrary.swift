import Foundation
import SwiftUI
import UIKit
import Photos
import PhotosUI
import CoreLocation

/// 端末の写真ライブラリ（PhotoKit）を読む口。「旅の写真からまとめて」で使う。
///
/// **写真はどこにも送らない。** 旅を探すのは端末の中だけ（`LibraryTrips`）。
/// 外へ出るのは、地名を引くためのおおよその位置（約1km・Apple の地図）だけで、
/// 本体は本人が選んで「下書きに入れる」を押した写真だけを読む。
///
/// 普段の投稿の写真選び（`PhotosPicker`）は許可が要らない。こちらはライブラリを
/// 自分で見て回るので許可が要る——**一部だけの許可（`.limited`）でも動かす**
/// （許された写真の中から探すだけ）。
enum PhotoLibrary {

    /// 遡る年数。全部を見ると数万枚になり、古い旅はもう投稿したか忘れている
    static let lookbackYears = 3

    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 許可を尋ねる（まだ決まっていないときだけダイアログが出る）
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// 読める段か。**一部だけの許可も読める**
    static func canRead(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    /// 一部だけ許可した人が、許可する写真を選び足す画面を出す（閉じるまで待つ）。
    /// 起動ごとの iOS の案内は止めている（Info.plist の
    /// `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`）ので、選び足す口はここだけ
    /// - Returns: 選び足す画面を出せたか。**出せなかったら false**（呼び手は探し直さない）
    @MainActor
    static func presentLimitedPicker() async -> Bool {
        guard let top = topController() else { return false }
        _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
        return true
    }

    /// いちばん上に出ている画面（全画面の流れの上に出す）
    @MainActor
    private static func topController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                var top = window.rootViewController
                while let next = top?.presentedViewController { top = next }
                return top
            }
        }
        return nil
    }

    /// 直近 `lookbackYears` 年の画像を、新しい順に `LibraryShot` へ写す。
    /// **重いので画面の処理（MainActor）の外で**——数万枚を1枚ずつ見る
    static func shots(now: Date = Date()) async -> [LibraryShot] {
        await Task.detached(priority: .userInitiated) {
            fetchShots(now: now)
        }.value
    }

    private static func fetchShots(now: Date) -> [LibraryShot] {
        let since = Calendar(identifier: .gregorian).date(byAdding: .year, value: -lookbackYears, to: now) ?? now
        let options = PHFetchOptions()
        // 絞り込みと並べ替えは PhotoKit に任せる。Linux の Foundation では
        // キー文字列の並べ替えが作れないので、模型の型検査からは外す
        // （下の `since` の見張りは両方で効く）
        #if canImport(Darwin)
        options.predicate = NSPredicate(format: "creationDate >= %@", since as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #endif
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var shots: [LibraryShot] = []
        shots.reserveCapacity(result.count)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            // **スクリーンショットは旅に入れない。** 旅先で見た地図や予約の画面は旅の写真ではなく、
            // 位置の無い写真として期間に紛れ込む
            if asset.mediaSubtypes.contains(.photoScreenshot) { continue }
            // 撮影日時の無い写真は旅に並べられない
            guard let date = asset.creationDate, date >= since else { continue }
            let coordinate = asset.location?.coordinate
            shots.append(LibraryShot(id: asset.localIdentifier, date: date,
                                     lat: coordinate?.latitude, lng: coordinate?.longitude))
        }
        return shots
    }

    /// 写真の本体（元のファイルの中身）。**iCloud にしか無い写真も落とす。**
    /// 落とせなかった（通信が無い・消された）ときは nil
    static func imageData(for id: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        // 1回だけ呼ばれる形（`.opportunistic` は粗い版と本番で2回呼ばれる）
        options.deliveryMode = .highQualityFormat
        options.version = .current
        // **取り消せるようにする**（「やめる」・画面を離れた）。iCloud から落とす読み込みには
        // 時間の上限が無いので、取り消しで PhotoKit の要求も止める。
        // 続きは箱が**一度だけ**再開する——取り消しの口からも nil で再開するので、PhotoKit が
        // 結果の口を呼ばなくても仕事が残らない（結果の口があとで呼ばれても二度目は捨てる）
        let manager = PHImageManager.default()
        let request = ImageRequestBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.begin(continuation) else { return }
                let id = manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    request.finish(data)
                }
                if request.set(id) { manager.cancelImageRequest(id) }
            }
        } onCancel: {
            if let id = request.cancel() { manager.cancelImageRequest(id) }
        }
    }

    /// 要求の続き・番号・「取り消された」印を、取り消しの口（別の糸で走る）と分け合う箱。
    /// **続きは一度だけ再開する**
    private final class ImageRequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data?, Never>?
        private var id: PHImageRequestID?
        private var cancelled = false

        /// 続きを預ける。**もう取り消されていたら nil で再開して false**（要求は出さない）
        func begin(_ continuation: CheckedContinuation<Data?, Never>) -> Bool {
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(returning: nil)
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        /// 番号を控える。**もう取り消されていたら true**（呼び手がすぐ止める）
        func set(_ id: PHImageRequestID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            self.id = id
            return cancelled
        }

        /// 結果で再開する（二度目以降は捨てる）
        func finish(_ data: Data?) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: data)
        }

        /// 取り消す。待っている続きは nil で再開し、番号が分かっていればそれを返す
        func cancel() -> PHImageRequestID? {
            lock.lock()
            cancelled = true
            let waiting = continuation
            continuation = nil
            let known = id
            lock.unlock()
            waiting?.resume(returning: nil)
            return known
        }
    }

    /// 地名（市区町村、無ければ都道府県）。旅の名前と日ごとの見出しに使う。
    ///
    /// **座標は約1km に丸めてから渡す**（`LibraryTrips.roundedForLookup`）——Apple の地図に
    /// 細かい位置を渡さない。引けなければ nil（画面は日付だけを出す）
    static func placeName(near coords: Photo.Coords) async -> String? {
        let rounded = LibraryTrips.roundedForLookup(coords)
        let location = CLLocation(latitude: rounded.lat, longitude: rounded.lng)
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let mark = marks.first else { return nil }
        for name in [mark.locality, mark.administrativeArea] {
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        }
        return nil
    }
}

/// 写真ライブラリのサムネイル。**1つの管理役を使い回す**（`PHCachingImageManager` は
/// 作るたびに縮小の控えが空になる）
@MainActor
final class LibraryThumbnails {

    static let shared = LibraryThumbnails()

    private let manager = PHCachingImageManager()
    /// id から引いた写真（毎回引き直さない）
    private var assets: [String: PHAsset] = [:]

    /// `pixels` は一辺のピクセル数
    func image(for id: String, pixels: CGFloat) async -> UIImage? {
        guard let asset = asset(for: id) else { return nil }
        let options = PHImageRequestOptions()
        // 1回だけ呼ばれる形。iCloud にしか無い写真も縮小を落とす
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: pixels, height: pixels)
        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func asset(for id: String) -> PHAsset? {
        if let known = assets[id] { return known }
        let found = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        assets[id] = found
        return found
    }
}

/// 写真ライブラリの1枚のサムネイル。読めるまでは面の色。**大きさは置く側が決める**
/// （`side` は読み込む縮小の一辺・pt）
struct LibraryThumbView: View {

    let id: String
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        WebTheme.surface
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: id) {
                // 画面の倍率は3倍で見積もる（2倍の機種では少し大きく取るだけ）
                image = await LibraryThumbnails.shared.image(for: id, pixels: side * 3)
            }
    }
}
