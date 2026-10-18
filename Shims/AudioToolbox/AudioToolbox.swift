// 端末の短い効果音（旅のトランクの貼る・ハンドルの目盛り・カプセルが落ちる・2026-10-17）。
// 本物は iOS の AudioToolbox。ここは型検査のための形だけ（音は鳴らない）
public typealias SystemSoundID = UInt32

public func AudioServicesPlaySystemSound(_ inSystemSoundID: SystemSoundID) {}
