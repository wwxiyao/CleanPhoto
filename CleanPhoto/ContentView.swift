//
//  ContentView.swift
//  CleanPhoto
//
//  Created by 阿哞 on 2026/1/9.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = LibraryViewModel(service: PhotoLibraryService())
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.accessState {
                case .notDetermined:
                    EmptyStateView(
                        title: "Photo Access Needed",
                        message: "Allow access to your library so we can load photos to review.",
                        actionTitle: "Allow Access"
                    ) {
                        viewModel.requestPermissionAndLoad()
                    }
                case .denied, .restricted:
                    EmptyStateView(
                        title: "Photo Access Disabled",
                        message: "Enable photo access in Settings to continue.",
                        actionTitle: "Open Settings"
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                case .authorized, .limited:
                    if viewModel.isLoading {
                        ProgressView("Loading Photos...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.isReviewingBatch {
                        BatchReviewView(
                            assets: Array(viewModel.batchManager.pendingDeleteAssets),
                            onRecover: viewModel.recoverAsset,
                            onDeleteAll: viewModel.confirmDeletion,
                            onSkip: viewModel.skipBatch
                        )
                    } else if viewModel.batchManager.currentBatch.isEmpty {
                        EmptyStateView(
                            title: viewModel.batchManager.hasMorePhotos ? "Batch Empty" : "All Done!",
                            message: viewModel.batchManager.hasMorePhotos ? "Something went wrong, try to load next batch." : "You've reviewed all your photos. Great job!",
                            actionTitle: viewModel.batchManager.hasMorePhotos ? "Next Batch" : "Reload All"
                        ) {
                            if viewModel.batchManager.hasMorePhotos {
                                viewModel.startNextBatch()
                            } else {
                                Task { await viewModel.loadAssets() }
                            }
                        }
                    } else {
                        SwipeContainerView(
                            assets: viewModel.batchManager.currentBatch,
                            onSwipeUp: viewModel.batchManager.markAsDelete,
                            onSwipeLeft: viewModel.batchManager.markAsKeep,
                            onFinished: viewModel.finishBatchInteraction
                        )
                        .overlay {
                            if viewModel.isDeleting {
                                ZStack {
                                    Color.black.opacity(0.3).ignoresSafeArea()
                                    ProgressView("Deleting Photos...")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("CleanPhoto")
        }
        .onAppear {
            viewModel.reloadIfNeeded()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}

#Preview {
    ContentView()
}
