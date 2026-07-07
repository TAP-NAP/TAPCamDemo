//
//  CameraRouteStore.swift
//  TAPCamDemo
//

import Combine
import Foundation

enum CameraRoutePreferences {
    // Keep the original stored key so existing installs do not lose the user's toggle.
    static let returnToCameraOnForegroundKey = "CameraRouteForceCameraOnForegroundAfterDelay"
    static let defaultReturnToCameraOnForeground = false

    static func returnToCameraOnForeground(
        in userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: returnToCameraOnForegroundKey) as? Bool
            ?? defaultReturnToCameraOnForeground
    }
}

/// Owns the camera module's in-memory navigation state.
///
/// `CameraView` still owns the visible `NavigationStack`, but this store makes
/// route decisions explicit and testable: the app can return to camera when it
/// foregrounds, while the TAP Library keeps enough album state to restore the
/// last selected or visible item across route changes and app launches.
@MainActor
final class CameraRouteStore: ObservableObject {
    enum Destination: Equatable {
        case camera
        case depthAlbum
    }

    struct AlbumState: Equatable {
        var selectedItemID: String?
        var scrollAnchorItemID: String?

        var restoreAnchorID: String? {
            scrollAnchorItemID ?? selectedItemID
        }
    }

    @Published private(set) var destination: Destination = .camera
    @Published private(set) var albumState = AlbumState()
    @Published private(set) var pendingLockedImportReason: String?
    @Published private(set) var isAwaitingLockedCaptureImport = false

    private let contextStore: any CameraRouteContextPersisting
    private var selectedItemAnchor: CameraRouteAlbumAnchor?
    private var scrollAnchorItem: CameraRouteAlbumAnchor?
    private var persistedContext: CameraRouteContext

    init(contextStore: any CameraRouteContextPersisting = CameraRouteFileContextStore()) {
        self.contextStore = contextStore
        self.persistedContext = contextStore.loadContext()
    }

    var isDepthAlbumPresented: Bool {
        destination == .depthAlbum
    }

    var depthAlbumRestoreAnchorID: String? {
        albumState.restoreAnchorID
    }

    func setDepthAlbumPresented(_ isPresented: Bool) {
        if isPresented {
            presentDepthAlbum()
        } else {
            returnToCamera()
        }
    }

    func presentDepthAlbum(
        lockedImportReason: String? = nil,
        awaitingLockedCaptureImport: Bool = false
    ) {
        if let lockedImportReason {
            pendingLockedImportReason = lockedImportReason
        }
        if awaitingLockedCaptureImport {
            isAwaitingLockedCaptureImport = true
        }
        destination = .depthAlbum
    }

    func returnToCamera() {
        persistAlbumState()
        pendingLockedImportReason = nil
        isAwaitingLockedCaptureImport = false
        destination = .camera
    }

    func finishAwaitingLockedCaptureImport() {
        isAwaitingLockedCaptureImport = false
    }

    func consumePendingLockedImportReason() -> String? {
        defer {
            pendingLockedImportReason = nil
        }
        return pendingLockedImportReason
    }

    func restoreCameraOnForeground() {
        destination = .camera
    }

    func recordVisibleDepthAlbumItem(_ anchor: CameraRouteAlbumAnchor) {
        scrollAnchorItem = anchor
        albumState.scrollAnchorItemID = anchor.itemID
    }

    func openDepthAlbumItem(_ anchor: CameraRouteAlbumAnchor) {
        selectedItemAnchor = anchor
        scrollAnchorItem = anchor
        albumState.selectedItemID = anchor.itemID
        albumState.scrollAnchorItemID = anchor.itemID
        persistAlbumState()
    }

    func recordVisibleDepthAlbumItem(id: String) {
        guard let anchor = CameraRouteAlbumAnchor(itemID: id) else {
            return
        }
        recordVisibleDepthAlbumItem(anchor)
    }

    func openDepthAlbumItem(id: String) {
        guard let anchor = CameraRouteAlbumAnchor(itemID: id) else {
            return
        }
        openDepthAlbumItem(anchor)
    }

    func validDepthAlbumRestoreAnchorID(availableItems: [CameraRouteAlbumAnchor]) -> String? {
        guard !availableItems.isEmpty else {
            return nil
        }

        let availableItemIDs = Set(availableItems.map(\.itemID))
        if let anchorID = depthAlbumRestoreAnchorID,
           availableItemIDs.contains(anchorID) {
            return anchorID
        }

        if let persistedAnchor = restoreAnchor(from: availableItems) {
            scrollAnchorItem = persistedAnchor
            albumState.scrollAnchorItemID = persistedAnchor.itemID
            return persistedAnchor.itemID
        }

        pruneUnavailableAlbumAnchors(availableItemIDs: availableItemIDs)
        clearPersistedContext()
        return nil
    }

    func validDepthAlbumRestoreAnchorID(availableItemIDs: Set<String>) -> String? {
        validDepthAlbumRestoreAnchorID(
            availableItems: availableItemIDs.compactMap { CameraRouteAlbumAnchor(itemID: $0) }
        )
    }

    private func pruneUnavailableAlbumAnchors(availableItemIDs: Set<String>) {
        let nextAlbumState = AlbumState(
            selectedItemID: albumState.selectedItemID.flatMap { availableItemIDs.contains($0) ? $0 : nil },
            scrollAnchorItemID: albumState.scrollAnchorItemID.flatMap { availableItemIDs.contains($0) ? $0 : nil }
        )
        guard nextAlbumState != albumState else {
            return
        }
        albumState = nextAlbumState
        selectedItemAnchor = selectedItemAnchor.flatMap { availableItemIDs.contains($0.itemID) ? $0 : nil }
        scrollAnchorItem = scrollAnchorItem.flatMap { availableItemIDs.contains($0.itemID) ? $0 : nil }
    }

    private func persistAlbumState() {
        guard let anchor = scrollAnchorItem ?? selectedItemAnchor else {
            clearPersistedContext()
            return
        }

        persistedContext = CameraRouteContext(
            restoreAnchorTokens: tokens(for: anchor)
        )
        contextStore.saveContext(persistedContext)
    }

    private func clearPersistedContext() {
        persistedContext = CameraRouteContext()
        contextStore.saveContext(persistedContext)
    }

    private func restoreAnchor(from anchors: [CameraRouteAlbumAnchor]) -> CameraRouteAlbumAnchor? {
        guard persistedContext.isFresh(),
              !persistedContext.restoreAnchorTokens.isEmpty else {
            return nil
        }
        let persistedTokens = Set(persistedContext.restoreAnchorTokens)
        return anchors.first { anchor in
            !persistedTokens.isDisjoint(with: tokens(for: anchor))
        }
    }

    private func tokens(for anchor: CameraRouteAlbumAnchor) -> [String] {
        anchor.tokenInputs.map { contextStore.token(for: $0) }
    }
}
