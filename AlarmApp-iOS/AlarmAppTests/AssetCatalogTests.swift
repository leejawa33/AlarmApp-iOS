import Foundation
import Testing
@testable import AlarmApp

/// 리소스 번들링과 카탈로그 규칙 검증. 호스트 앱 테스트라 `Bundle.main`은 AlarmApp.app이다.
struct AssetCatalogTests {
    @Test func catalogLoadsFromAppBundle() throws {
        let catalog = try AssetCatalog.load()
        #expect(catalog.appDisplayName == "알람천국")
    }

    @Test func defaultMediaIsFullscreenPuppyVideo() throws {
        let catalog = try AssetCatalog.load()
        #expect(catalog.media.filter(\.isDefault).count == 1)
        let media = try #require(catalog.defaultMedia)
        #expect(media.id == "media_puppy_crack")
        #expect(media.type == .video)
        #expect(media.layout == .fullscreen)
        #expect(media.muted == true)
        #expect(media.loop == true)
    }

    @Test func everyMediaIsMutedLoopingFullscreenVideo() throws {
        let catalog = try AssetCatalog.load()
        #expect(catalog.media.map(\.id) == ["media_puppy_crack", "media_cat_push", "media_shaking_clock"])
        #expect(Set(catalog.media.map(\.id)).count == catalog.media.count)
        for media in catalog.media {
            #expect(media.type == .video, "\(media.id)")
            #expect(media.layout == .fullscreen, "\(media.id)")
            #expect(media.muted == true, "\(media.id)")
            #expect(media.loop == true, "\(media.id)")
        }
    }

    @Test func defaultSoundHasKoreanName() throws {
        let catalog = try AssetCatalog.load()
        #expect(catalog.sounds.filter(\.isDefault).count == 1)
        #expect(catalog.defaultSound?.displayName == "아침이 왔다잖아")
    }

    @Test func shakeMissionDefaultsToTen() throws {
        let catalog = try AssetCatalog.load()
        #expect(catalog.missions.first { $0.id == "shake" }?.defaultCount == 10)
    }

    @Test func everyCatalogFileIsBundled() throws {
        let catalog = try AssetCatalog.load()
        let paths = catalog.media.map(\.file) + catalog.sounds.map(\.file) + catalog.missions.compactMap(\.promptsFile)
        for path in paths {
            #expect(AssetCatalog.resourceURL(for: path) != nil, "번들에 없음: \(path)")
        }
        for copy in ["Copy/ui_strings_ko.json", "Copy/ui_strings_en.json"] {
            #expect(AssetCatalog.resourceURL(for: copy) != nil, "번들에 없음: \(copy)")
        }
    }

    @Test func referenceScreenshotIsNotBundled() {
        #expect(AssetCatalog.resourceURL(for: "Media/IMG_6265.PNG") == nil)
        #expect(AssetCatalog.resourceURL(for: "README.md") == nil)
    }
}
