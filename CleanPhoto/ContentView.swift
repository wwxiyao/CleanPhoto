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
                        systemImage: "lock.shield",
                        accent: AppPalette.primary,
                        actionTitle: "允许访问",
                        action: {
                        viewModel.requestPermissionAndLoad()
                        }
                    )
                case .denied, .restricted:
                    EmptyStateView(
                        title: "照片访问已禁用",
                        message: "在设置中开启照片访问权限以继续。",
                        systemImage: "xmark.shield",
                        accent: AppPalette.danger,
                        actionTitle: "打开设置",
                        action: {
                        #if targetEnvironment(macCatalyst)
                        let settingsURL = "x-apple.systempreferences:"
                        #else
                        let settingsURL = UIApplication.openSettingsURLString
                        #endif
                        if let url = URL(string: settingsURL) {
                            openURL(url)
                        }
                        }
                    )
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
                            systemImage: viewModel.batchManager.hasMorePhotos ? "sparkles.rectangle.stack" : "checkmark.seal",
                            accent: AppPalette.primary,
                            actionTitle: viewModel.batchManager.hasMorePhotos ? "下一批" : "重新整理",
                            action: {
                            if viewModel.batchManager.hasMorePhotos {
                                viewModel.startNextBatch()
                            } else {
                                viewModel.restartReview()
                            }
                            }
                        )
                    } else {
                        SwipeContainerView(
                            assets: viewModel.batchManager.currentBatch,
                            currentIndex: viewModel.batchManager.currentIndex,
                            viewModel: viewModel,
                            onSwipeUp: viewModel.batchManager.markAsDelete,
                            onSwipeLeft: viewModel.batchManager.markAsKeep,
                            onFinished: viewModel.finishBatchInteraction
                        )
                    }
                }
            }
            .navigationTitle("CleanPhoto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.accessState.canRead && viewModel.assets != nil && !viewModel.isShowingSimilar && !viewModel.isReviewingBatch && !viewModel.isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.enterSimilarMode()
                        } label: {
                            Image(systemName: "square.on.square.dashed")
                            Text("相似照片")
                        }
                        .font(.subheadline.weight(.medium))
                        .accessibilityLabel("整理相似照片")
                    }
                }
            }
        }
        .disabled(viewModel.isDeleting)
        .overlay {
            if viewModel.isDeleting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("正在删除照片...")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .onAppear {
            viewModel.reloadIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
        .alert(item: $viewModel.activeAlert) { alertState in
            Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
                dismissButton: .default(Text("确定"))
            )
        }
        .tint(AppPalette.primary)
    }
}

#Preview {
    ContentView()
}
