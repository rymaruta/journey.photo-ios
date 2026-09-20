import Foundation

/// 規約への同意。
///
/// **審査要件（1.2 / UGC）。** 利用者が作った内容を載せるアプリは、
/// 「不適切な内容を許さない」ことを含む規約に**使う前に同意させる**必要が
/// ある。Web 版には `/terms` と `/privacy` があるので、文面はそちらに寄せ、
/// アプリは同意の記録だけを持つ。
@MainActor
final class LegalConsent: ObservableObject {

    /// 規約を変えたら上げる。上げると全員にもう一度出る。
    static let currentVersion = 1

    private static let key = "legal.consent.version"

    @Published private(set) var acceptedVersion: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.acceptedVersion = defaults.integer(forKey: Self.key)
    }

    var needsConsent: Bool { acceptedVersion < Self.currentVersion }

    func accept() {
        defaults.set(Self.currentVersion, forKey: Self.key)
        acceptedVersion = Self.currentVersion
    }

    /// 規約とプライバシーポリシーの場所。サイトと同じ文面を出す
    /// （2か所に置くと必ず食い違う）。
    static var termsURL: URL { AppConfig.siteBaseURL.appendingPathComponent("terms") }
    static var privacyURL: URL { AppConfig.siteBaseURL.appendingPathComponent("privacy") }
}
