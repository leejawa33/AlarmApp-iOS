import Foundation

/// `Resources/assets_catalog.json` — 미디어·소리·미션 목록의 기준. 코드에 하드코딩하지 않는다.
nonisolated struct AssetCatalog: Decodable, Sendable {
    let appDisplayName: String
    let media: [Media]
    let sounds: [Sound]
    let missions: [Mission]

    nonisolated struct Media: Decodable, Sendable, Identifiable, Hashable {
        enum Kind: String, Decodable, Sendable { case video, image }
        enum Layout: String, Decodable, Sendable { case fullscreen, center }

        let id: String
        let file: String
        let displayName: String
        let type: Kind
        let isDefault: Bool
        let layout: Layout?
        let loop: Bool?
        let muted: Bool?

        enum CodingKeys: String, CodingKey {
            case id, file, displayName, type, layout, loop, muted
            case isDefault = "default"
        }
    }

    nonisolated struct Sound: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let file: String
        /// 한국어 표시명(기본값). 화면에는 `Strings.soundName`이 앱 언어에 맞는 이름을 돌려준다.
        let displayName: String
        let isDefault: Bool
        let format: String
        /// AlarmKit 알람 소리 파일(.caf). 없으면 시스템 기본음.
        let alarmFile: String?

        enum CodingKeys: String, CodingKey {
            case id, file, displayName, format, alarmFile
            case isDefault = "default"
        }
    }

    nonisolated struct Mission: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let defaultCount: Int?
        let promptsFile: String?
    }

    var defaultMedia: Media? { media.first(where: \.isDefault) }
    var defaultSound: Sound? { sounds.first(where: \.isDefault) }
}
