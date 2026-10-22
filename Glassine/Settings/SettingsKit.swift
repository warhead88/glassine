import SwiftUI

// Settings are laid out on paper: sections with a Fraunces title, cards of rows with a native
// control on the right. The system Form draws its own grey cards, so these stand in for it;
// the controls themselves stay native, tinted with the theme's accent.

/// One tab's content: paper behind a column of sections.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// A titled group: "Area capture", "Updates".
struct SettingsSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .textStyle(ThemeTokens.title)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            content
            if let note {
                SettingsNote(note)
            }
        }
    }
}

/// Rows on a card, with hairlines between them (put a `RowDivider` between rows).
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous).strokeBorder(Color.border))
    }
}

/// A setting: what it is on the left (with a line of detail), its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

extension SettingsRow where Control == SettingsToggle {
    /// A row that is just a switch.
    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.init(title: title, detail: detail) { SettingsToggle(isOn: isOn, label: title) }
    }
}

/// A switch without its own label (the row has one), still named for VoiceOver.
struct SettingsToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.rule).frame(height: 1)
    }
}

/// A small caps label over option cards: "SCREEN FRAME".
struct SettingsLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textStyle(ThemeTokens.label)
            .foregroundStyle(Color.ink3)
    }
}

/// A line of explanation under a card or section.
struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The tabs: a paper track with the selected one raised.
struct SettingsTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(title(tab))
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.ink : Color.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(Color.card)
                                    .overlay(Capsule().strokeBorder(Color.border))
                                    .shadow(color: Color.shadow.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.track.opacity(0.55)))
    }
}
