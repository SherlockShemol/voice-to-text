import SwiftUI

struct TranscriptionPopupView: View {
    @EnvironmentObject var appState: AppState
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(minHeight: 40, maxHeight: 280)

            HStack {
                Spacer()
                Button("复制") {
                    appState.copyToClipboard(text)
                    appState.dismissTranscriptionPopup()
                }
                .buttonStyle(.borderedProminent)
                Button("关闭") {
                    appState.dismissTranscriptionPopup()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}
