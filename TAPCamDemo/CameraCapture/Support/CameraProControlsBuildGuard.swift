//
//  CameraProControlsBuildGuard.swift
//  TAPCamDemo
//

#if !DEBUG && TAP_ENABLE_PRO_CAMERA_CONTROLS
#error("TAP_ENABLE_PRO_CAMERA_CONTROLS must not be enabled in Release builds.")
#endif
