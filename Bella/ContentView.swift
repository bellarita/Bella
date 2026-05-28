import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var apiKey = KeychainStore.loadAPIKey()
    @State private var userInput = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var isRecording = false
    @State private var showSettings = false
    @State private var audioEngine = AVAudioEngine()
    @State private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var speechTask: SFSpeechRecognitionTask?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let client = OpenAIClient()

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    messageList
                    composer
                }
            }
            .navigationTitle("Bella")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        resetChat()
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .disabled(messages.isEmpty || isLoading)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingView(apiKey: $apiKey)
            }
            .onAppear {
                apiKey = KeychainStore.loadAPIKey()
                loadChatHistory()
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(.systemGroupedBackground)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("正在思考...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("今天想聊什么？")
                    .font(.title2.bold())
                Text("输入问题、长按语音，或让 Bella 帮你整理想法。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                PromptButton(title: "帮我规划今天的学习安排") {
                    userInput = "帮我规划今天的学习安排"
                }
                PromptButton(title: "把这段话润色得更自然") {
                    userInput = "把这段话润色得更自然："
                }
                PromptButton(title: "给我 3 个晚餐灵感") {
                    userInput = "给我 3 个晚餐灵感"
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 80)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    showSettings = true
                } label: {
                    Label("先填写 OpenAI API Key", systemImage: "key")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isRecording ? .red : .blue)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                TextField("输入消息...", text: $userInput, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        stopRecording()
        userInput = ""
        isLoading = true

        messages.append(Message(text: text, isUser: true))
        saveChatHistory()

        Task {
            do {
                let reply = try await client.send(messages: Array(messages.suffix(10)), apiKey: apiKey)
                messages.append(Message(text: reply, isUser: false))
            } catch {
                messages.append(Message(text: error.localizedDescription, isUser: false))
            }

            isLoading = false
            saveChatHistory()
        }
    }

    private func toggleVoiceInput() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    messages.append(Message(text: "请在系统设置中允许语音识别权限。", isUser: false))
                    return
                }

                do {
                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
                    try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                    try beginSpeechRecognition()
                } catch {
                    messages.append(Message(text: "录音启动失败：\(error.localizedDescription)", isUser: false))
                }
            }
        }
    }

    private func beginSpeechRecognition() throws {
        speechTask?.cancel()
        speechTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        speechRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        speechTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    userInput = result.bestTranscription.formattedString
                }

                if error != nil || result?.isFinal == true {
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        guard isRecording || audioEngine.isRunning else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechRequest = nil
        speechTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetChat() {
        stopRecording()
        messages.removeAll()
        saveChatHistory()
    }

    private func saveChatHistory() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: "chatHistory")
        }
    }

    private func loadChatHistory() {
        guard let data = UserDefaults.standard.data(forKey: "chatHistory"),
              let history = try? JSONDecoder().decode([Message].self, from: data) else {
            messages = []
            return
        }

        messages = history
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser {
                Spacer(minLength: 46)
            }

            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(message.isUser ? .white : .primary)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !message.isUser {
                Spacer(minLength: 46)
            }
        }
        .padding(.horizontal, 14)
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isUser {
            return AnyShapeStyle(Color.blue)
        }

        return AnyShapeStyle(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
    }
}

private struct PromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Message: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool

    init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
