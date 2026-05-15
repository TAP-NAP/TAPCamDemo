//
//  StartupPermissionCoordinatorTests.swift
//  TAPCamDemoTests
//

import Photos
import Testing
@testable import TAPCamDemo

struct StartupPermissionCoordinatorTests {
    @Test func limitedPhotoLibraryAccessCountsAsGranted() {
        #expect(StartupPermissionCoordinator.photoLibraryStatus(from: .limited) == .granted)
    }
}
