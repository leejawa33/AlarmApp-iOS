import Foundation

/// 번들에서 따라쓰기 문구를 읽는 I/O. 타입 정의는 `Domain/Value/TranscriptionPrompts.swift`.
nonisolated extension TranscriptionPrompts {
    static func load(from catalog: AssetCatalog, bundle: Bundle = .main) throws -> TranscriptionPrompts {
        guard let path = catalog.missions.first(where: { $0.id == MissionType.transcription.rawValue })?.promptsFile,
              let url = AssetCatalog.resourceURL(for: path, in: bundle)
        else { throw AssetCatalog.LoadError.catalogNotFound }
        return try JSONDecoder().decode(TranscriptionPrompts.self, from: Data(contentsOf: url))
    }
}
