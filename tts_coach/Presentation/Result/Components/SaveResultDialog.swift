//
//  SaveResultDialog.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Generic "name something and save it" dialog — matches mockup image 9.
/// Originally built for saving a practice result; now reused (per
/// revision) as the naming step at the end of Create Voice Reference.
/// `title` makes it flexible for both contexts.
///
/// No custom dimming/card chrome here — this is presented via a native
/// `.sheet()`, which already provides that. (Drawing both caused a
/// "floating/glitchy" double-modal look.)
struct SaveResultDialogView: View {
    let title: String
    @State private var name: String
    var onCancel: () -> Void = {}
    var onSave: (String) -> Void = { _ in }

    init(
        title: String = "Save this result as...",
        defaultName: String,
        onCancel: @escaping () -> Void = {},
        onSave: @escaping (String) -> Void = { _ in }
    ) {
        self.title = title
        _name = State(initialValue: defaultName)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .trailing], 16)

            VStack(spacing: 18) {
                Text(title)
                    .font(.title3.weight(.semibold))

                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Save") { onSave(name) }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
        }
        .frame(width: 380)
    }
}

#Preview {
    SaveResultDialogView(defaultName: "Lorem ipsum practice 1")
        .frame(width: 420)
}

#Preview("Naming a voice") {
    SaveResultDialogView(title: "Save this voice as...", defaultName: "My Voice")
        .frame(width: 420)
}
