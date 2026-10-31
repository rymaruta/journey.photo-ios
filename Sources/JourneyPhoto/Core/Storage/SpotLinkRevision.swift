import Foundation
import Combine

/// **自動の結びをこの端末で変えた回数**（2026-10-31・journey.photo-ios#425 の確かめの指摘）。
///
/// 写真の詳細で「外す」「元に戻す」が通ると、`OfficialSpotService.noteSpotAuto` が表に重ねる分を変える。
/// サービスは actor で画面から見張れないので、ここで回数を上げて知らせる。開いたままの撮影スポットの頁
/// （`OfficialSpotView`）と地図（`PhotoMapView`）は、この値を `.task(id:)` の鍵に入れて表を読み直す
/// （表は控えから返るので通信しない）。値そのものに意味は無い
@MainActor
final class SpotLinkRevision: ObservableObject {
    static let shared = SpotLinkRevision()

    @Published private(set) var value = 0

    func bump() { value += 1 }
}
