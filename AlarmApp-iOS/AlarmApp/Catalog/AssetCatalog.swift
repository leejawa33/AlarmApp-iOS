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

nonisolated extension AssetCatalog {
    enum LoadError: Error, Equatable {
        case catalogNotFound
    }

    static let fileName = "assets_catalog.json"

    static func load(from bundle: Bundle = .main) throws -> AssetCatalog {
        guard let url = resourceURL(for: fileName, in: bundle) else { throw LoadError.catalogNotFound }
        return try JSONDecoder().decode(AssetCatalog.self, from: Data(contentsOf: url))
    }

    /// 카탈로그의 `file` 경로(예: `Media/media_puppy_crack.mp4`)를 번들 URL로 바꾼다.
    /// Xcode 동기화 폴더는 리소스를 번들 루트로 평탄화해 복사하므로 파일명으로 찾는다.
    static func resourceURL(for path: String, in bundle: Bundle = .main) -> URL? {
        let name = (path as NSString).lastPathComponent
        return bundle.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension
        )
    }
}
