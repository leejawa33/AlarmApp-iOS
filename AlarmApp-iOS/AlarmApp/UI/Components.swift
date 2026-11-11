import SwiftUI
import UIKit

/// 시안의 흰 카드 블록 (라벨 + 내용)
struct Block<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(Theme.rounded(12, weight: .bold))
                .foregroundStyle(Theme.textMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

/// 선택 칩 (미션·미디어·소리)
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 8)
                .background(isSelected ? Theme.chipOn : Theme.chipOff, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.sun : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 미션 시작·저장 등 CTA: 누르면 스프링으로 살짝 줄어든다.
struct CTAButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(16, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? Theme.ctaPress : Theme.cta, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.cta.opacity(0.35), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 흰 배경 보조 버튼 (미리보기 등)
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(15, weight: .heavy))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// "알람" + "천국"(sun-deep). 공백이 있으면 마지막 단어, 없으면 뒤쪽 절반을 강조한다.
struct Wordmark: View {
    let name: String

    var body: some View {
        let split = name.lastIndex(of: " ").map { name.index(after: $0) }
            ?? name.index(name.startIndex, offsetBy: name.count / 2)
        (Text(name[..<split]).foregroundStyle(Theme.text) + Text(name[split...]).foregroundStyle(Theme.sunDeep))
            .font(Theme.rounded(26, weight: .heavy))
    }
}

/// 권한 `설정 열기` 버튼 (메인 배너·설정 화면 공용). 동작은 `AlarmService.handleOpenSettingsTap()`.
struct OpenSettingsButton<Label: View>: View {
    @Environment(AlarmService.self) private var service
    @Environment(\.openURL) private var openURL
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            Task {
                if await service.handleOpenSettingsTap(),
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } label: {
            label
        }
    }
}
