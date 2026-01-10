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
                        title: "需要访问照片",
                        message: "允许访问您的照片库以加载照片进行整理。",
                        actionTitle: "允许访问"
                    ) {
                        viewModel.requestPermissionAndLoad()
                    }
                case .denied, .restricted:
                    EmptyStateView(
                        title: "照片访问已禁用",
                        message: "在设置中开启照片访问权限以继续。",
                        actionTitle: "打开设置"
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                case .authorized, .limited:
                    if viewModel.isShowingSimilar {
                        SimilarPhotosView(viewModel: viewModel)
                    } else if viewModel.isLoading {
                        ProgressView("正在加载照片...")
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
                            title: viewModel.batchManager.hasMorePhotos ? "本批次完成" : "全部完成！",
                            message: viewModel.batchManager.hasMorePhotos ? "准备好加载下一批照片了吗？" : "您已经整理了所有照片。太棒了！",
                            actionTitle: viewModel.batchManager.hasMorePhotos ? "下一批" : "重新加载"
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
                            onUndo: viewModel.batchManager.undo,
                            onFinished: viewModel.finishBatchInteraction
                        )
                        .overlay {
                            if viewModel.isDeleting {
                                ZStack {
                                    Color.black.opacity(0.3).ignoresSafeArea()
                                    ProgressView("正在删除照片...")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("CleanPhoto")
            .toolbar {
                if !viewModel.isShowingSimilar && !viewModel.isReviewingBatch && !viewModel.isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.enterSimilarMode()
                        } label: {
                            Image(systemName: "square.on.square.dashed")
                            Text("相似")
                        }
                    }
                }
            }
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
