import Foundation
import PLaMoKit

/// Small delegate-based downloader: URLSession's async `download(from:)` does
/// not expose progress, which matters for a 486 MB model.
final class ModelDownloader: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var isFinished = true
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func download(
        _ variant: ModelVariant,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if isDownloading {
            throw URLError(.resourceUnavailable)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("kotoba-\(UUID().uuidString)-\(variant.fileName)")

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            self.destination = destination
            self.progressHandler = progress
            self.isFinished = false
            lock.unlock()

            session.downloadTask(with: variant.downloadURL).resume()
        }
    }

    private var isDownloading: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isFinished
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        progressHandler = nil
        lock.unlock()

        switch result {
        case let .success(url): continuation.resume(returning: url)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let value: Double
        if totalBytesExpectedToWrite > 0 {
            value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            value = 0
        }

        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(min(max(value, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }

        lock.lock()
        let destination = destination
        lock.unlock()

        guard let destination else {
            finish(.failure(URLError(.badURL)))
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            // didFinishDownloadingTo normally wins this race; resuming here
            // prevents a hung continuation if the server returned no body.
            finish(.failure(URLError(.cannotParseResponse)))
        }
    }
}
