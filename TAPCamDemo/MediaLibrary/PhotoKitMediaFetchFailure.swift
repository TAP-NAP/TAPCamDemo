//
//  PhotoKitMediaFetchFailure.swift
//  TAPCamDemo
//

import Foundation
@preconcurrency import Photos

nonisolated struct PhotoKitNetworkAccessRequired: Error {}

nonisolated enum PhotoKitMediaFetchFailure {
    static func resourceError(_ error: Error) -> any Error {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.networkAccessRequired.rawValue {
            return PhotoKitNetworkAccessRequired()
        }
        return map(error)
    }

    static func map(_ error: Error) -> MediaFetchFailure {
        if let failure = error as? MediaFetchFailure {
            return failure
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorTimedOut:
                return .offline
            default:
                return .download
            }
        }
        if nsError.domain == PHPhotosErrorDomain {
            switch nsError.code {
            case PHPhotosError.accessUserDenied.rawValue,
                 PHPhotosError.accessRestricted.rawValue:
                return .permission
            case PHPhotosError.networkError.rawValue,
                 PHPhotosError.libraryVolumeOffline.rawValue:
                return .offline
            case PHPhotosError.identifierNotFound.rawValue,
                 PHPhotosError.missingResource.rawValue:
                return .assetRemoved
            default:
                return .download
            }
        }
        return .download
    }
}
