import SwiftUI

/// 撮影スポットの1行（地図の「スポット」の札と、探すの撮影スポットの一覧で同じ部品・札 #524 で
/// `PhotoMapView` から切り出した。見た目は前と同じ）。
///
/// **v2（2026-10-14・板 MapList の `.sr`）**: 高さ 64・名前は明朝 18（板 17 は明朝の下限 18 に上げた）・
/// 「1 km 以内 · 写真 N枚」は 12 の text-3 の等幅数字・行の下に白 8% の線。札に入れず黒地に直に並べる。
/// 左の 40pt の丸（写真の丸・真鍮の縁）は地図のピンと同じ見分け方なので残す（板の行には無い）。
/// 右の矢印も残す（行き先がある行・板は「行きたい」の旗の位置）
///
/// **2026-11-13 判断（デザインの点検「観光スポットの一覧の丸い印が真鍮の塗り」）**: 写真の無いスポットの丸を、
/// 40pt の真鍮の塗り＋墨のカメラから、surface-3 の地＋text-3 のカメラ＋真鍮 2pt の縁に替えた。板 04
/// 「10px 以上の塗りの丸に真鍮を使わない」——一覧の半分ほどが真鍮の丸になり、未読の点・件数の合図と紛れていた。
/// 撮影スポットの見分けは写真の丸と同じ**真鍮の縁**に残す。写真の丸の下地も同じ surface-3 にそろえた
/// （中の `DownsampledRemoteImage` が surface の地を敷くので、下地の真鍮はもともと読み込み中も見えていない）。
/// 地図の上のピン（`SpotMapMarker`）は板 SpotPinOptions の別の決まりなので替えない
struct OfficialSpotRow: View {

    let row: OfficialSpotList.Row
    /// 写真の数を言ってよいか（読み込み中・初回の失敗で手元が空なら「0枚」と言わない。
    /// 判定はスポットの画面と同じ `SpotScreen.photosKnown`）
    let photosKnown: Bool

    /// 左の丸の大きさ（40pt）と地（surface-3・**真鍮の塗りにしない**）
    nonisolated static let markSize: CGFloat = 40
    static let markFill = WebTheme.surface3

    var body: some View {
        HStack(spacing: JPSpace.s) {
            if let photo = row.spot.photo {
                // 写真があれば写真の丸・真鍮の縁（地図のピンと同じ見分け方）。40pt なので縮小版
                // （読めなければ元の画像・`SpotThumbImage`）
                SpotThumbImage(image: photo)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .background(Self.markFill)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis))
                    .accessibilityHidden(true)
            } else {
                // 写真の無いスポット: 灰の地に灰のカメラ、縁だけ真鍮（写真の丸と同じ縁で、撮影スポットと分かる）
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .background(Self.markFill, in: Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.spot.name)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                let sub = Self.subline(row, loaded: photosKnown)
                if !sub.isEmpty {
                    Text(sub)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, JPSpace.s)
        .frame(minHeight: JPHeight.tallRow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .contentShape(Rectangle())
    }

    /// 「約0.8km · 写真 3枚」。距離は**丸めた座標から測るので「約」を付ける**
    /// （`NearbyPhotos.label`）。起点が無ければ距離を出さない。
    /// 写真を読み込む前は枚数を省く（「写真 0枚」と言わない）。
    /// 読み終えて0枚なら、数の代わりに最初の1枚への誘い（`SpotScreen.firstPhotoInvite`・2026-10-21・run 609 の 13d）
    nonisolated static func subline(_ row: OfficialSpotList.Row, loaded: Bool) -> String {
        let distance = row.km.map { NearbyPhotos.label(km: $0) }
        guard loaded else { return distance ?? "" }
        let photos = row.photoCount == 0
            ? SpotScreen.firstPhotoInvite
            : L("写真 \(row.photoCount)枚", PhotoMapViewModel.photoCountLabel(row.photoCount))
        guard let distance else { return photos }
        return "\(distance)\u{2002}\(photos)"
    }
}
