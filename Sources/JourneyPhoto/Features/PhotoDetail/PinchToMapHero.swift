import SwiftUI
import CoreLocation
import MapKit

/// 写真の詳細の大きな写真。**押すと大きく見る・2本指でつまんで縮めると地図**（2026-11-12 札 #543・`PinchToMap`）。
///
/// つまむ値（`@GestureState`）は**この部品の中だけ**で持つ。写真の詳細の画面に置くと、指が動くたびに
/// 画面の全体（題・撮影情報・コメント…）が描き直されていた（2026-11-12 確かめ役）
struct PinchToMapHero<Content: View>: View {

    let item: Photo
    let height: CGFloat
    /// 押した（大きく見る）
    let onOpen: () -> Void
    /// つまんで離した・読み上げの「地図で見る」（「地図で見る ›」と同じ地図）
    let onOpenMap: () -> Void
    @ViewBuilder let content: () -> Content

    /// つまんで縮めている量（1 = 等倍）。取り消されたら自動で戻る
    @GestureState private var pinch: Double = 1

    private var hasPlace: Bool { item.coords != nil }

    var body: some View {
        Button(action: onOpen) {
            // 🔴 **写真は重ね（overlay）に置く。** 引き伸ばした写真（fill）を直に
            // `.frame(maxWidth: .infinity)` で包むと、横長の写真では包みの幅が
            // 写真の幅（画面より広い）になり、`.clipped()` は見た目を切るだけなので
            // 下の本文まで画面より広く組まれていた（説明・撮影情報・操作の列が
            // 右端で切れる。実機の絵で見つかった）。重ねは親の幅を変えない
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    content()
                        // つまんで縮めると小さくなる（撮影地が無ければ段で止まる）
                        .scaleEffect(PinchToMap.displayScale(scale: pinch, hasPlace: hasPlace))
                        .clipShape(RoundedRectangle(cornerRadius: pinch < 1 ? JPRadius.l : 0))
                }
                // 縮めるほど撮影地の地図が引いてくる（後ろ）
                .background { map }
                .overlay { hint }
                .overlay(alignment: .bottomLeading) { place }
                .clipped()
                .contentShape(Rectangle())
                .accessibilityLabel(item.accessibilityText)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("拡大して見る", "Opens the photo full screen"))
        // UI テストがつまむ所（つまむと地図の絵）
        .accessibilityIdentifier("detail.hero")
        // 2本指でつまんで縮めると地図（広げる向きは今までどおり押して大きく見る）
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    if PinchToMap.opensMap(endScale: value.magnification, hasPlace: hasPlace) { onOpenMap() }
                }
        )
        // 段を越えて**進んだときだけ**軽く振動（戻すときは鳴らさない・`PinchToMap.buzzes`）
        .sensoryFeedback(.impact(weight: .light), trigger: PinchToMap.passedStep(scale: pinch)) { old, new in
            PinchToMap.buzzes(wasPast: old, isPast: new)
        }
        .accessibilityAction(named: L("地図で見る", "View on map")) {
            if hasPlace { onOpenMap() }
        }
    }

    /// つまんでいる間の後ろの地図（撮影地の無い写真・つまんでいないときは描かない）
    @ViewBuilder
    private var map: some View {
        if pinch < 1, let coords = item.coords {
            let point = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            Map(position: .constant(.region(MKCoordinateRegion(
                center: point, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))) {
                Annotation("", coordinate: point) {
                    Circle().fill(WebTheme.accent).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: JPStroke.emphasis))
                }
            }
            .opacity(PinchToMap.progress(scale: pinch))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 地図が引いてきたら、撮影地の名前と「広げると写真へ」（戻り方が見て分かる）
    @ViewBuilder
    private var place: some View {
        if let label = PinchToMap.placeLabel(location: item.location, scale: pinch, hasPlace: hasPlace) {
            VStack(alignment: .leading, spacing: 2) {
                if !label.place.isEmpty {
                    Text(label.place)
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.foreground)
                }
                Text(label.back)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
            .jpPhotoTextShadow()
            .padding(JPSpace.m)
            .allowsHitTesting(false)
            .accessibilityIdentifier("detail.pinchPlace")
        }
    }

    /// 段を越えたら「さらに縮めると地図」（撮影地が無ければ「撮影地がありません」）。写真の上なので白・ガラス
    @ViewBuilder
    private var hint: some View {
        if PinchToMap.passedStep(scale: pinch) {
            Text(!hasPlace ? L("撮影地がありません", "No place for this photo")
                 : pinch <= PinchToMap.openScale ? L("離すと地図", "Release for the map")
                 : L("さらに縮めると地図", "Pinch more for the map"))
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, JPSpace.s)
                .padding(.vertical, JPSpace.xs)
                .jpGlass(in: Capsule())
                .allowsHitTesting(false)
                .accessibilityIdentifier("detail.pinchHint")
        }
    }
}
