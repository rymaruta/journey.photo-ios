import SwiftUI

/// 旅行プランの行の右の写真の枠（札 #710 の案3・`TripPlanPhotos`）。56pt・角 10（板「場所の札の写真 56、角 10」）。
///
/// - 自分の写真があれば、その写真（押すと写真の詳細）
/// - 今日の、まだ写真の無い観光スポットは、真鍮の点線の「＋」（黒地の上の合図・押すと投稿の画面）
/// - どちらでもなければ何も置かない（空き地を作らない）
struct TripStopPhotoSlot: View {
    let photo: Photo?
    let invites: Bool
    let name: String
    let onInvite: () -> Void

    static let side: CGFloat = 56

    var body: some View {
        if let photo {
            NavigationLink {
                // 自分の写真だけ（`TripPlanPhotos.mine`）。他人の写真はここに出さない
                PhotoDetailView(photo: photo, context: [photo])
            } label: {
                DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                       aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                       assumedRatioLimit: PhotoFrame.assumedRatioLimit)
                    .frame(width: Self.side, height: Self.side)
                    .background(WebTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(name) で撮ったあなたの写真", "Your photo at \(name)"))
            .accessibilityIdentifier("tripPlan.stopPhoto")
        } else if invites {
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
