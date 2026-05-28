import SwiftUI

struct SettingView: View {
    @Binding var apiKey: String
    @Environment(\.dismiss) var dismiss
    @State private var draftAPIKey: String

    init(apiKey: Binding<String>) {
        _apiKey = apiKey
        _draftAPIKey = State(initialValue: apiKey.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API 配置") {
                    SecureField("粘贴 sk- 开头的密钥", text: $draftAPIKey)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .keyboardType(.asciiCapable)
                }

                Section {
                    Button(role: .destructive) {
                        draftAPIKey = ""
                        apiKey = ""
                        KeychainStore.deleteAPIKey()
                    } label: {
                        Label("清除密钥", systemImage: "trash")
                    }
                    .disabled(draftAPIKey.isEmpty)
                } footer: {
                    Text("密钥保存在本机 Keychain。正式发布前建议改为后端代理调用 OpenAI，避免用户密钥留在客户端。")
                }
            }
            .navigationTitle("API 设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        apiKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        KeychainStore.saveAPIKey(apiKey)
                        dismiss()
                    }
                }
            }
        }
    }
}
