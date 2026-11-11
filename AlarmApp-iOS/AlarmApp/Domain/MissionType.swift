import Foundation

/// 알람당 정확히 1개. id는 `assets_catalog.json`의 missions[].id와 같다.
nonisolated enum MissionType: String, CaseIterable, Codable, Sendable {
    case shake
    case transcription
}

/// 기획서 데이터 모델 이름과 맞추기 위한 별칭. 미디어·소리는 번들 카탈로그가 원본이라 SwiftData에 저장하지 않는다.
typealias MediaAsset = AssetCatalog.Media
typealias SoundAsset = AssetCatalog.Sound
