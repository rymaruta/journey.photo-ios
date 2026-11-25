import AudioToolbox
import Foundation

/// アプリに同梱した短い効果音（2026-11-25・カプセルが開く、硬貨を入れる）。
///
/// 音は `Tools/make-sounds.py` で自分で合成した物（他人の音源は使わない）。
/// ファイルは `Resources/Sounds/<rawValue>.caf`（リニア PCM・16 bit・32 kHz・1つ 50KB 未満）
enum SoundEffect: String, CaseIterable, Sendable {
    /// カプセルのふたが外れる瞬間。「ポンッ」と弾けて、上へきらっと続く（0.62 秒・いちばん大きい所 -3 dBFS）
    case capsuleOpen = "capsule-open"
    /// 硬貨が入れ口に入る小さな「ちゃりん」（0.30 秒・-9 dBFS で控えめ）
    case coinIn = "coin-in"

    static let fileExtension = "caf"

    /// UI テストが渡す起動の引数（`XCUIApplication.jp()`）。これがあると鳴らさない
    static let muteArgument = "-JPNoSounds"

    /// 鳴らしてよいか。UI テスト（`-JPNoSounds`・見本の利用者 `-JPPreviewUserId`）、
    /// Xcode のプレビュー、単体テストの間は鳴らさない
    static func allowed(environment: [String: String], arguments: [String]) -> Bool {
        if arguments.contains(muteArgument) || arguments.contains("-" + PreviewSession.defaultsKey) { return false }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil { return false }
        return true
    }

    /// 束の中の音のファイル（無ければ nil）
    func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: rawValue, withExtension: Self.fileExtension)
            ?? bundle.url(forResource: rawValue, withExtension: Self.fileExtension, subdirectory: "Sounds")
    }
}

/// 効果音を鳴らす1か所の部品（2026-11-25 判断）。
///
/// **鳴らし方は端末の効果音（`AudioServicesPlaySystemSound`）にした。** キーボードの「こつ」と同じ道で、
/// - 消音スイッチがオンなら鳴らない（`.ambient` と同じ）
/// - ほかのアプリの音楽も、このアプリの曲の試聴（`MusicPreviewPlayer` の `.playback`）も止めない・小さくしない
///   （`.mixWithOthers` と同じ）。**音の場（`AVAudioSession`）に一切触らない**——カプセルのために場を `.ambient` に
///   替えると、試聴中の曲が消音スイッチで黙ってしまう
/// - 読み込みは `prepare` で先に済ませ、押した瞬間は番号を渡すだけ（遅れが出ない）
/// - 大きさは端末の「着信音と通知音」の大きさに従う。旅のトランクの目盛りの音（`TrunkSound`）と同じ道なので、つり合う
///
/// 設定の切り替えは置かない（CLAUDE.md「既定で正しく動く」。止めたい人は消音スイッチで止められる）。
/// UI テスト・プレビュー・単体テストの間は鳴らさない（`SoundEffect.allowed`）
@MainActor
enum SoundEffects {
    static let isAllowed = SoundEffect.allowed(environment: ProcessInfo.processInfo.environment,
                                   arguments: ProcessInfo.processInfo.arguments)

    /// 読み込んだ音の番号（一度読んだらアプリが終わるまで持つ。小さいので捨てない）
    private static var loaded: [SoundEffect: SystemSoundID] = [:]

    /// 先に読み込む（画面が出たとき）。鳴らさない場面では何もしない
    static func prepare(_ effects: [SoundEffect]) {
        guard isAllowed else { return }
        for effect in effects where loaded[effect] == nil {
            guard let url = effect.url() else { continue }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == 0 {
                loaded[effect] = id
            }
        }
    }

    /// 鳴らす。読み込みがまだなら、ここで読んでから鳴らす
    static func play(_ effect: SoundEffect) {
        guard isAllowed else { return }
        prepare([effect])
        guard let id = loaded[effect] else { return }
        AudioServicesPlaySystemSound(id)
    }
}
