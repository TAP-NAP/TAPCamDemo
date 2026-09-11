//
//  PhotoKitResourceRequest.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos

nonisolated protocol PhotoKitResourceSink: AnyObject, Sendable {
    associatedtype Output: Sendable

    func receive(_ chunk: Data) throws
    func finish() throws -> Output
    func discard()
}

nonisolated final class PhotoKitResourceDataSink: PhotoKitResourceSink, @unchecked Sendable {
    private var data = Data()

    func receive(_ chunk: Data) {
        data.append(chunk)
    }

    func finish() -> Data {
        let result = data
        data.removeAll(keepingCapacity: false)
        return result
    }

    func discard() {
        data.removeAll(keepingCapacity: false)
    }
}

nonisolated final class PhotoKitResourceFileSink: PhotoKitResourceSink, @unchecked Sendable {
    typealias WriteChunk = @Sendable (FileHandle, Data) throws -> Void
    typealias FinishFile = @Sendable (FileHandle) throws -> Void

    private let fileURL: URL
    private let writeChunk: WriteChunk
    private let finishFile: FinishFile
    private var fileHandle: FileHandle?

    init(
        fileURL: URL,
        writeChunk: @escaping WriteChunk = { fileHandle, chunk in
            try fileHandle.write(contentsOf: chunk)
        },
        finishFile: FinishFile? = nil
    ) throws {
        self.fileURL = fileURL
        self.writeChunk = writeChunk
        self.finishFile = finishFile ?? { try? $0.close() }
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
    }

    func receive(_ chunk: Data) throws {
        guard let fileHandle else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writeChunk(fileHandle, chunk)
    }

    func finish() throws {
        guard let fileHandle else {
            return
        }
        try finishFile(fileHandle)
        self.fileHandle = nil
    }

    func discard() {
        let fileHandle = self.fileHandle
        self.fileHandle = nil
        try? fileHandle?.close()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// One PhotoKit resource adapter serves data and file consumers;
/// only the sink differs.
nonisolated final class PhotoKitResourceRequestBridge<Sink: PhotoKitResourceSink>: @unchecked Sendable {
    typealias DataReceiver = @Sendable (Data) -> Void
    typealias Completion = @Sendable ((any Error)?) -> Void
    typealias RegisterRequest = @Sendable (
        _ dataReceiver: @escaping DataReceiver,
        _ completion: @escaping Completion
    ) -> PHAssetResourceDataRequestID

    private let manager: PHAssetResourceManager
    private let allowsNetworkAccess: Bool
    private let progress: @Sendable (Double?) -> Void
    private let mapError: @Sendable (any Error) -> any Error
    private let sink: Sink
    private let lifecycle: PhotoKitRequestLifecycle<PHAssetResourceDataRequestID, Sink.Output>

    init(
        sink: Sink,
        manager: PHAssetResourceManager = .default(),
        allowsNetworkAccess: Bool,
        progress: @escaping @Sendable (Double?) -> Void,
        mapError: @escaping @Sendable (any Error) -> any Error = PhotoKitMediaFetchFailure.resourceError,
        cancelRequest: (@Sendable (PHAssetResourceDataRequestID) -> Void)? = nil
    ) {
        self.sink = sink
        self.manager = manager
        self.allowsNetworkAccess = allowsNetworkAccess
        self.progress = progress
        self.mapError = mapError
        self.lifecycle = PhotoKitRequestLifecycle(
            cancelRequest: cancelRequest ?? { requestID in
                manager.cancelDataRequest(requestID)
            },
            onFinish: { result in
                switch result {
                case .success:
                    progress(1)
                case .failure:
                    sink.discard()
                }
            }
        )
    }

    func start(resource: PHAssetResource) async throws -> Sink.Output {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.progressHandler = { [weak self] value in
            self?.receiveProgress(value)
        }
        return try await startRequest { [manager] dataReceiver, completion in
            manager.requestData(
                for: resource,
                options: options,
                dataReceivedHandler: dataReceiver,
                completionHandler: completion
            )
        }
    }

    /// Separating callback registration from `PHAssetResource` keeps the
    /// shared stream/lifecycle behavior directly testable without a Photos
    /// library fixture.
    func startRequest(_ registerRequest: @escaping RegisterRequest) async throws -> Sink.Output {
        try await withCheckedThrowingContinuation { continuation in
            guard lifecycle.install(continuation: continuation) else {
                return
            }

            let requestID = registerRequest(
                { [weak self] chunk in
                    self?.receive(chunk)
                },
                { [weak self] error in
                    self?.finish(error: error)
                }
            )
            lifecycle.install(requestID: requestID)
        }
    }

    func cancel() {
        lifecycle.cancel()
    }

    private func receive(_ chunk: Data) {
        lifecycle.process(
            {
                try sink.receive(chunk)
            },
            mapError: mapError
        )
    }

    private func receiveProgress(_ value: Double) {
        lifecycle.reportProgress(value, to: progress)
    }

    private func finish(error: (any Error)?) {
        if let error {
            lifecycle.finish(.failure(mapError(error)))
        } else {
            lifecycle.finish(mapError: mapError) {
                try sink.finish()
            }
        }
    }
}
