import SwiftUI

/// 旅行プランの行の番号の丸の右の写真（札 #710 の案3・`TripPlanPhotos.thumb`）。44pt・角 10
/// （AI が作っている途中の行 `TripAIViews.row` と同じ形）。自分の写真か、無ければ観光スポットの写真
struct TripStopThumbView: View {
    let thumb: TripStopThumb

    static let side: CGFloat = 44

    var body: some View {
        Group {
            switch thumb {
            case .mine(let photo):
                DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                       aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                       assumedRatioLimit: PhotoFrame.assumedRatioLimit)
            case .spot(let image):
                SpotThumbImage(image: image, assumedRatioLimit: 2)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
        .accessibilityHidden(true)
        .accessibilityIdentifier(thumb.isMine ? "tripPlan.stopPhoto" : "tripPlan.stopSpotPhoto")
    }
}

/// 行の右の点線の「＋」（札 #710 の案3）。**今日の、まだ自分の写真の無い観光スポットだけ**。
/// 行の写真（観光スポットの写真）には重ねず、行の右に置く。真鍮（黒地の上の合図）・押すと投稿の画面
struct TripStopPhotoSlot: View {
    let invites: Bool
    let name: String
    let onInvite: () -> Void

    static let side: CGFloat = 44

    var body: some View {
        if invites {
            Button(action: onInvite) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(WebTheme.accent)
                    .frame(width: Self.side, height: Self.side)
                    .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                        .strokeBorder(WebTheme.accent.opacity(0.7),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(name) で撮った写真を載せる", "Post a photo you took at \(name)"))
            .accessibilityIdentifier("tripPlan.stopInvite")
        }
    }
}

/// 行の下の一行（「あなたの1枚　8:12」か、真鍮の「ここで撮った1枚を載せる」）
struct TripStopPhotoLine: View {
    let photo: Photo?
    let invites: Bool

    var body: some View {
        if let photo {
            Text(TripPlanPhotos.line(photo))
                .font(JPFont.mono(JPTypeScale.caption, relativeTo: .caption))
                .foregroundStyle(WebTheme.text3)
        } else if invites {
            Text(TripPlanPhotos.inviteLine)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.accent)
        }
    }
}

/// 点線の枠から開く投稿の行き先（`sheet(item:)` に渡す）
struct TripStopPostTarget: Identifiable {
    let id = UUID()
    let spot: UploadSpotTarget
}
