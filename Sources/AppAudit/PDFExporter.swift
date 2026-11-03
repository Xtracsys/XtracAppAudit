import Foundation
import AuditCore

@MainActor final class PDFExporter {
    private var task: Task<Void, Never>?
    func export(snapshot: AuditSnapshot, baseline: AuditSnapshot?, policy: AuditPolicy, to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        task = Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) { try PDFReport.data(snapshot, baseline: baseline, policy: policy) }.value
                try data.write(to: url, options: .atomic)
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }
}
