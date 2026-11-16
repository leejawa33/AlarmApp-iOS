import Foundation

/// 번들에서 카탈로그를 읽는 I/O. 타입 정의는 `Domain/Value/AssetCatalog.swift`.
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
