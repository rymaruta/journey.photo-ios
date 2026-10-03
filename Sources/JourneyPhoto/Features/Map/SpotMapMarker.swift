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
struct SpotMapMarker: View {

    let photoURL: URL?

    var body: some View {
        if let photoURL {
            // 写真の丸・真鍮の縁（デザイン 07「写真あり」）。**縁を真鍮にして**
            // Apple の名所（白い縁の丸）とユーザーの写真のピン（角丸の四角）から見分ける。
            // 読めなかったときは真鍮の地が見える（空の枠にしない）
            RemoteImage(url: photoURL)
                .frame(width: 40, height: 40)
                .background(WebTheme.accent)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: 3))
                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(width: 32, height: 32)
                .background(WebTheme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
                .accessibilityHidden(true)
        }
    }
}
