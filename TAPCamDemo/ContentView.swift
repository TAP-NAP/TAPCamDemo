//
//  ContentView.swift
//  TAPCamDemo
//
//  Created by Harold on 2026/4/24.
//

import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var isShowingDepthAlbum = false

    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topStatusBar
                Spacer()
                VStack(spacing: 18) {
                    rearPhotoLensPicker
                    bottomControls
                }
            }
        }
        .background(Color.black)
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $isShowingDepthAlbum) {
            NavigationStack {
                DepthAlbumPickerView()
            }
        }
    }

    private var topStatusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(camera.depthStatusText, systemImage: camera.isDepthCaptureAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(camera.isDepthCaptureAvailable ? .green : .yellow)

                Spacer()

                Text(camera.cameraPositionText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }

            if let lastCaptureSummary = camera.lastCaptureSummary {
                Text(lastCaptureSummary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            } else {
                Text(camera.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.55))
    }

    private var bottomControls: some View {
        HStack {
            recentPhotoButton
                .frame(width: 78, height: 78)

            Spacer()

            Button {
                Task {
                    await camera.captureDepthPhoto()
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)

                    Circle()
                        .fill(camera.canCapture ? Color.white : Color.gray)
                        .frame(width: 62, height: 62)

                    if camera.isCapturing {
                        ProgressView()
                            .tint(.black)
                    }
                }
            }
            .disabled(!camera.canCapture)
            .accessibilityLabel("Capture depth photo")

            Spacer()

            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
            }
            .accessibilityLabel("Switch camera")
            .frame(width: 78, height: 78)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 34)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var recentPhotoButton: some View {
        Button {
            isShowingDepthAlbum = true
        } label: {
            if let thumbnail = camera.recentThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.8), lineWidth: 1.5)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.48))
                        .frame(width: 58, height: 58)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel("Open TAPCamDepth album")
    }

    @ViewBuilder
    private var rearPhotoLensPicker: some View {
        if camera.currentPosition == .back, camera.rearPhotoLensOptions.count > 1 {
            HStack(spacing: 8) {
                ForEach(camera.rearPhotoLensOptions) { lens in
                    Button {
                        camera.selectPhotoLens(lens)
                    } label: {
                        Text(lens.displayName)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .frame(minWidth: 66)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(lens.id == camera.selectedPhotoLensID ? Color.white : Color.black.opacity(0.48))
                            .foregroundStyle(lens.id == camera.selectedPhotoLensID ? Color.black : Color.white)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("Use \(lens.displayName)")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.48), in: Capsule())
            .padding(.horizontal, 18)
        }
    }
}
