import Foundation

/// 探すの0件の出口から語を受け取った地図が、**どこへ寄せるか**（`TabRouter.openMap(query:)`）。
///
/// 初めて地図の札を開いた回は、語を受け取った時点でまだ写真も索引も無く、
/// 寄せる先（`PhotoMapViewModel.frame`）が決まらない。そのうえ開いたときの
/// 自動の現在地が後から届いて `camera = .userLocation` に上書きし、語で絞った
/// ピンが画面の外になっていた。
///
/// - 受け取ったら「語で寄せる」印を立てる。写真・索引が届いて枠が決まった時点で一度だけ寄せる
/// - 印がある間は、**自動の**現在地で寄せない（ボタンで取った現在地は寄せる＝人の操作が勝つ）
/// - 人が地図を触ったら、あとから寄せ直さない
struct MapQueryFraming: Equatable {

    /// 枠が決まったら寄せる
    private(set) var waitingToFrame = false
    /// 自動の現在地で寄せない
    private(set) var holdsAgainstAutoLocate = false

    /// 探すから語を受け取った。**空の語は前の語を消すだけ**なので寄せ待ちを下ろす（`cleared()`）
    mutating func received(query: String) {
        guard !query.isEmpty else {
            cleared()
            return
        }
        waitingToFrame = true
        holdsAgainstAutoLocate = true
    }

    /// 枠が決まっていれば、一度だけそれを返す（寄せる先）。まだなら nil で待ち続ける。
    ///
    /// - Parameter settled: 写真も索引も取り終えたか。取り終えて枠が無い＝語が何にも
    ///   当たらなかった。**そのときは印を両方下ろす**——待ち続けると、あとで人が
    ///   触った語の変化や索引の読み直しで急に寄り、自動の現在地も抑えたままになる
    mutating func frameIfReady(_ frame: MapFraming.Frame?, settled: Bool) -> MapFraming.Frame? {
        guard waitingToFrame else { return nil }
        guard let frame else {
            if settled {
                waitingToFrame = false
                holdsAgainstAutoLocate = false
            }
            return nil
        }
        waitingToFrame = false
        return frame
    }

    /// 届いた現在地へ寄せるか。ボタンから取った回は寄せ、以後は語の寄せも待たない
    mutating func followsLocation(requestedByUser: Bool) -> Bool {
        if requestedByUser {
            waitingToFrame = false
            holdsAgainstAutoLocate = false
            return true
        }
        return !holdsAgainstAutoLocate
    }

    /// 語が空になった（探すから空の語が来た・欄を消した）。前の語の寄せ待ちも下ろす——残すと、
    /// 読み終えた時点で写真全体の枠へ「語で寄せた」扱いで寄り、自動の現在地も抑えたままになる
    mutating func cleared() {
        waitingToFrame = false
        holdsAgainstAutoLocate = false
    }

    /// 人が地図を動かした。見ている場所から引き戻さない
    mutating func userMovedCamera() {
        waitingToFrame = false
    }
}
