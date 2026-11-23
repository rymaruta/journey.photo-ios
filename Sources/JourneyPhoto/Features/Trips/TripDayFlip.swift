import SwiftUI

/// 開いた一冊の日のページを左右でめくる（札 #714・決まりは `TripBookPageFlip`）。
/// 一冊の `ScrollView` に付ける。投稿した一冊（`TripBookView`）と端末の一冊（`DeviceTripBookView`）で同じ動き。
///
/// - 横に払うと次の日・前の日の見出しへ送る（縦に読むのはそのまま。左の端からの払いは「戻る」に任せる）
/// - 読み上げでは「次の日」「前の日」の操作で送れる
/// - 動きを減らす設定では、すぐその日へ移る
struct TripDayFlip: ViewModifier {
    /// 日の見出しの行の id（並びの順。`ForEach` の id と同じもの）
    let dayIDs: [String]
    /// 読む線を過ぎた見出しの id（`tripDayMark`）
    let passed: Set<String>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard let direction = TripBookPageFlip.direction(dx: value.translation.width,
                                                                             dy: value.translation.height,
                                                                             startX: value.startLocation.x) else { return }
                            flip(direction, proxy: proxy)
                        }
                )
                .accessibilityAction(named: L("次の日", "Next day")) { flip(1, proxy: proxy) }
                .accessibilityAction(named: L("前の日", "Previous day")) { flip(-1, proxy: proxy) }
        }
    }

    private func flip(_ direction: Int, proxy: ScrollViewProxy) {
        guard let id = TripBookPageFlip.targetID(dayIDs: dayIDs, passed: passed, direction: direction) else { return }
        if reduceMotion {
            proxy.scrollTo(id, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: TripBookPageFlip.duration)) { proxy.scrollTo(id, anchor: .top) }
        }
    }
}

extension View {
    /// 日の見出しに付ける。見出しが読む線（画面の上から `TripBookPageFlip.readingLine`）を過ぎたかを `passed` に書く。
    /// 値は真偽だけなので、送るたびに描き直さない
    func tripDayMark(id: String, passed: Binding<Set<String>>) -> some View {
        onGeometryChange(for: Bool.self) {
            Double($0.frame(in: .scrollView).minY) <= TripBookPageFlip.readingLine
        } action: { isPast in
            if isPast { passed.wrappedValue.insert(id) } else { passed.wrappedValue.remove(id) }
        }
    }
}
