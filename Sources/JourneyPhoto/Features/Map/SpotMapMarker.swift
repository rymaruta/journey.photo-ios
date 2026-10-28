import SwiftUI

/// 撮影スポットの地図の印（デザイン 07・2026-09-26）。地図のタブ（`PhotoMapView`）と
/// 「行きたい場所」の地図（`SavedSpotsMapView`）で**同じものを使う**（写しを作らない）。2種類:
///
///     写真あり  写真の丸 40pt・真鍮の縁 3pt（写真は Wikimedia Commons。
///               owner が確かめた行だけ索引に載る）
///     写真なし  真鍮の丸 32pt・墨のカメラ・白い縁 2pt
///
/// 以前は灰色の丸（地 rgba(40,40,44,0.92)）で、緑の地図に沈んで見つけにくかった
/// （owner の指摘）。**地図のピンは真鍮**（owner の好み・CLAUDE.md）。
/// 押せる範囲（44pt）と読み上げ名は呼ぶ側のボタンが付ける（ここは絵だけ）
///
/// **影は付けない**（2026-10-28 判断・重さの直し・owner 承認）。板は影 14 / 55% だが、`.shadow` はピン1つごとに
/// 画面の外で形をぼかす描き足しが要り、地図を動かすたびにピンの数だけ描き直す。見分けは縁（真鍮・白）で付く。
/// みんなの写真のピン（`PhotoMapView.photoPinFrame`）も同じ
struct SpotMapMarker: View {

    let photoURL: URL?
    /// `photoURL` が読めなかったときに一度だけ切り替える先（撮影スポットの縮小版 → 元の画像・
    /// `SpotThumbImage`）。撮影地の写真のピンは nil（切り替えない）
    var fallbackURL: URL? = nil
    /// 選んでいる（札を出している）ピン。**v2 の板 SpotPinOptions「選んだとき」**:
    /// 1.27 倍 ＋ 真鍮 16% の光の輪（外へ 10）。ばねは 0.3 秒・触覚1回は呼ぶ側（`PhotoMapView`）。
    /// 付けるのは `.selected(_:)`（作る口の形 `SpotMapMarker(photoURL:fallbackURL:)` は変えない）
    var isSelected = false

    /// 選んでいる形にした写し
    func selected(_ on: Bool) -> SpotMapMarker {
        var copy = self
        copy.isSelected = on
        return copy
    }

    /// 写真の丸の大きさ。**40 のまま**（板 v2 は 44 の案だが、owner の決まり「ピンは今の 40」・
    /// 押せる 44 は呼ぶ側のボタンが取る）
    nonisolated static let photoSize: CGFloat = 40
    /// 写真の無い真鍮の丸の大きさ（板 32pt）
    nonisolated static let plainSize: CGFloat = 32
    /// 選んだときの倍率（板 1.27 倍）
    nonisolated static let selectedScale: CGFloat = 1.27
    /// 選んだときの光の輪の幅と濃さ（板 `box-shadow: 0 0 0 10px rgba(201,166,107,.16)`）
    nonisolated static let haloWidth: CGFloat = 10
    nonisolated static let haloOpacity = 0.16

    var body: some View {
        marker
            // 光の輪は丸の外へ広げる（丸の中の写真・印を覆わない）。選んでいないときは描かない
            .background {
                if isSelected {
                    Circle()
                        .fill(WebTheme.accent.opacity(Self.haloOpacity))
                        .padding(-Self.haloWidth)
                }
            }
            .scaleEffect(isSelected ? Self.selectedScale : 1)
    }

    @ViewBuilder
    private var marker: some View {
        if let photoURL {
            // 写真の丸・真鍮の縁（デザイン 07「写真あり」）。**縁を真鍮にして**
            // Apple の名所（白い縁の丸）とユーザーの写真のピン（角丸の四角）から見分ける。
            // 読めなかったときは真鍮の地が見える（空の枠にしない）
            SpotThumbImage(url: photoURL, fallbackURL: fallbackURL)
                .frame(width: Self.photoSize, height: Self.photoSize)
                .background(WebTheme.accent)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.ringGap))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(width: Self.plainSize, height: Self.plainSize)
                .background(WebTheme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: JPStroke.emphasis))
                .accessibilityHidden(true)
        }
    }
}
