//
//  ScriptTextBox.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

struct ScriptTextBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary.opacity(0.85))
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ScriptTextBox(text: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. \nThe rainbow is a division of white light into many beautiful colors.\nThese take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon.\nThere is, according to legend, a boiling pot of gold at one end.\nPeople look, but no one ever finds it.\nWhen a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow.\nThroughout history, the rainbow has been a symbol of hope and a sign of things to come.\nThe vibrant bands of red, orange, yellow, green, blue, and violet curve gracefully across the sky, reminding us of the calm that follows a storm.\nScientists observe these wavelengths to understand the physics of light, while artists simply try to capture their fleeting brilliance on canvas.")
        .padding()
        .frame(width: 380)
}
