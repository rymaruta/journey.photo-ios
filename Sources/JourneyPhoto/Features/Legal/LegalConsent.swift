import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

/// 規約への同意。
///
/// **審査要件（1.2 / UGC）。** 利用者が作った内容を載せるアプリは、
/// 「不適切な内容を許さない」ことを含む規約に**使う前に同意させる**必要が
/// ある。Web 版には `/terms` と `/privacy` があるので、文面はそちらに寄せ、
/// アプリは同意の記録だけを持つ。
@MainActor
final class LegalConsent: ObservableObject {

    /// 規約を変えたら上げる。上げると全員にもう一度出る。
    nonisolated static let currentVersion = 1

    /// この画面が求める版。**テストから差し替えるために開けてある。**
    ///
    /// 開けていないと、`currentVersion` が 1 のあいだは
    /// 「古い版に同意済み」が 0（＝既定値）としか書けず、
    /// **`< ` を `== 0` に変えても落ちないテスト**しか書けない
    /// （実際そう書いてしまい、変異で当てて気づいた）。
    let requiredVersion: Int

    private static let key = "legal.consent.version"

    @Published private(set) var acceptedVersion: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, requiredVersion: Int = LegalConsent.currentVersion) {
        self.defaults = defaults
        self.requiredVersion = requiredVersion
        self.acceptedVersion = defaults.integer(forKey: Self.key)
    }

    var needsConsent: Bool { acceptedVersion < requiredVersion }

    func accept() {
        defaults.set(requiredVersion, forKey: Self.key)
        acceptedVersion = requiredVersion
    }

    /// 規約とプライバシーポリシーの場所。サイトと同じ文面を出す
    /// （2か所に置くと必ず食い違う）。
    static var termsURL: URL { AppConfig.siteBaseURL.appendingPathComponent("terms") }
    static var privacyURL: URL { AppConfig.siteBaseURL.appendingPathComponent("privacy") }

    /// 問い合わせ先。
    ///
    /// **審査で要る。** 利用者が作った内容を載せるアプリは、通報の受け皿に
    /// 連絡が取れる必要がある（ガイドライン 1.2）。サイトの規約ページと
    /// 同じ宛先を使う（`.github/workflows/deploy.yml` の `contactEmail`）。
    /// 2か所に別の宛先を書くと、どちらかが必ず死ぬ。
    static let contactEmail = "journey.photo.official@gmail.com"

    static var contactURL: URL? {
        URL(string: "mailto:\(contactEmail)?subject=" +
            ("Journey Photo（iOS）について".addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? ""))
    }
}
