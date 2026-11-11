import SwiftUI

/// 미션 문장 고르기: 카테고리 탭 + 탭별 전체 선택 + 문장별 체크. 하나도 안 고르면 확인 불가.
/// 결과는 `PromptSelection.normalize`로 저장값(전부면 빈 배열 = 전체)으로 바꿔 돌려준다.
struct PromptPickerView: View {
    let prompts: TranscriptionPrompts
    let onConfirm: ([String]) -> Void

    @Environment(Strings.self) private var strings
    @Environment(\.dismiss) private var dismiss

    @State private var checked: Set<String>
    @State private var categoryID: String

    init(prompts: TranscriptionPrompts, selected: [String], onConfirm: @escaping ([String]) -> Void) {
        self.prompts = prompts
        self.onConfirm = onConfirm
        _checked = State(initialValue: PromptSelection.checkedIDs(selected, in: prompts))
        _categoryID = State(initialValue: prompts.categories.first?.id ?? "")
    }

    private var category: PromptCategory? { prompts.categories.first { $0.id == categoryID } }
    private var visible: [TranscriptionPrompt] { category.map(prompts.prompts(in:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    selectAllRow
                    ForEach(visible) { prompt in
                        checkRow(prompt.text(for: strings.language), isOn: checked.contains(prompt.id)) { toggle(prompt.id) }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["prompt_picker_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(strings["edit_cancel"]) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(strings["common_ok"]) {
                    onConfirm(PromptSelection.normalize(checked, in: prompts))
                    dismiss()
                }
                .disabled(checked.isEmpty) // 출제할 문장이 하나는 있어야 한다
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: checked)
    }

    // MARK: 탭

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(prompts.categories) { item in
                    tab(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private func tab(_ item: PromptCategory) -> some View {
        let isSelected = item.id == categoryID
        let count = prompts.prompts(in: item).filter { checked.contains($0.id) }.count
        return Button {
            categoryID = item.id
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(item.name(for: strings.language))
                        .font(Theme.rounded(16, weight: isSelected ? .heavy : .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                    if count > 0 {
                        Text("\(count)")
                            .font(Theme.rounded(13, weight: .heavy))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isSelected ? Theme.chipOn : Theme.chipOff, in: Capsule())
                            .contentTransition(.numericText())
                    }
                }
                Capsule()
                    .fill(isSelected ? Theme.sun : .clear)
                    .frame(height: 3)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: 행

    private var selectAllRow: some View {
        let ids = visible.map(\.id)
        let allOn = !ids.isEmpty && ids.allSatisfy(checked.contains)
        return checkRow(strings["prompt_select_all"], isOn: allOn, isHeader: true) {
            if allOn { checked.subtract(ids) } else { checked.formUnion(ids) }
        }
    }

    private func checkRow(_ title: String, isOn: Bool, isHeader: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.sunDeep : Theme.textMuted.opacity(0.5))
                Text(title)
                    .font(Theme.rounded(17, weight: isHeader ? .heavy : .bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(isHeader ? Color.clear : (isOn ? Theme.chipOn : Color.white),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isHeader ? .clear : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }
}

#if DEBUG
#Preview {
    PreviewHost { _ in
        NavigationStack {
            PromptPickerView(prompts: try! TranscriptionPrompts.load(from: AssetCatalog.load()), selected: []) { _ in }
        }
    }
}
#endif
