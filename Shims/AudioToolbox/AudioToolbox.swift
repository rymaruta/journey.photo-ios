// 端末の短い効果音（旅のトランクの貼る・ハンドルの目盛り・カプセルが落ちる・2026-10-17）。
// 本物は iOS の AudioToolbox。ここは型検査のための形だけ（音は鳴らない）
import Foundation

public typealias SystemSoundID = UInt32

public func AudioServicesPlaySystemSound(_ inSystemSoundID: SystemSoundID) {}

// アプリに同梱した音のファイルを効果音として読む（カプセルが開く・硬貨・`SoundEffects`・2026-11-25）。
// Linux の Foundation には `CFURL`・`OSStatus` が無いので、本物と同じ書き方（`url as CFURL`・`== 0`）が通る形だけ置く
public typealias OSStatus = Int32
public typealias CFURL = URL

public func AudioServicesCreateSystemSoundID(_ inFileURL: CFURL,
                                             _ outSystemSoundID: UnsafeMutablePointer<SystemSoundID>) -> OSStatus {
    outSystemSoundID.pointee = 0
    return -1
}
