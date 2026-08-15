import Foundation
import SwiftLlama

@MainActor
final class LocalAI {
    static let shared = LocalAI()

    private var service: LlamaService?
    private var loadError: String?

    private func loadIfNeeded() -> LlamaService? {
        if let service { return service }
        guard let modelUrl = Bundle.main.url(forResource: "model", withExtension: "gguf") else {
            loadError = "Model file missing from app bundle."
            return nil
        }
        let newService = LlamaService(modelUrl: modelUrl, config: .init(batchSize: 256, maxTokenCount: 4096, useGPU: true))
        service = newService
        return newService
    }

    func answer(question: String, relevantNotes: [Note]) async -> String {
        guard let service = loadIfNeeded() else {
            return loadError ?? "The local AI model couldn't be loaded."
        }

        let messages = [
            LlamaChatMessage(role: .system, content: AIProtocol.systemPrompt(notes: relevantNotes)),
            LlamaChatMessage(role: .user, content: question)
        ]

        do {
            let stream = try await service.streamCompletion(of: messages, samplingConfig: .init(temperature: 0.4, seed: 42))
            var result = ""
            for try await token in stream { result += token }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "The local AI ran into an error: \(error.localizedDescription)"
        }
    }
}
