import SwiftUI

struct SimilarPhotosView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var isScanning = true
    @State private var similarGroups: [SimilarGroup] = []
    
    var body: some View {
        Group {
            if isScanning && similarGroups.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在寻找相似照片...")
                        .font(.headline)
                    Text("这可能需要一点时间，具体取决于您的图库大小。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !isScanning && similarGroups.isEmpty {
                EmptyStateView(
                    title: "未发现重复照片",
                    message: "您的相册看起来很整洁！",
                    actionTitle: "返回",
                    action: { viewModel.exitSimilarMode() }
                )
            } else {
                VStack {
                    if isScanning {
                        ProgressView("正在后台继续扫描...")
                            .padding(.vertical, 8)
                            .transition(.move(edge: .top))
                    }
                    
                    List {
                        ForEach($similarGroups) { $group in
                            SimilarGroupRow(group: $group)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        ignoreGroup(group)
                                    } label: {
                                        Label("忽略", systemImage: "eye.slash")
                                    }
                                    .tint(.gray)
                                }
                        }
                    }
                    .listStyle(.plain)
                    
                    VStack {
                        let totalToDelete = similarGroups.reduce(0) { $0 + $1.assetsToDelete.count }
                        
                        Button(action: {
                            deleteSelected()
                        }) {
                            Text("删除 \(totalToDelete) 张未选中的照片")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(totalToDelete > 0 ? Color.red : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(totalToDelete == 0)
                    }
                    .padding()
                    .background(Color(.systemBackground).shadow(radius: 5, y: -5))
                }
            }
        }
        .navigationTitle("相似照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isScanning {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        viewModel.exitSimilarMode()
                    }
                }
            }
        }
        .task {
            await scanForSimilars()
        }
    }
    
    private func scanForSimilars() async {
        let service = SimilarityService()
        // Use stream to get results progressively
        for await groups in await service.findSimilarGroupsStream(from: viewModel.assets) {
            await MainActor.run {
                if isScanning { isScanning = false } // Hide initial full screen loader once we have first data
                self.similarGroups.append(contentsOf: groups)
            }
        }
        await MainActor.run {
            self.isScanning = false
        }
    }
    
    private func ignoreGroup(_ group: SimilarGroup) {
        withAnimation {
            IgnoredGroupsService.shared.ignoreGroup(assets: group.assets)
            if let index = similarGroups.firstIndex(where: { $0.id == group.id }) {
                similarGroups.remove(at: index)
            }
        }
    }
    
    private func deleteSelected() {
        let assetsToDelete = similarGroups.flatMap { $0.assetsToDelete }
        viewModel.deleteSpecificAssets(assetsToDelete) {
            // After delete, reload or just remove groups
            withAnimation {
                similarGroups.removeAll()
                viewModel.exitSimilarMode()
            }
        }
    }
}

struct SimilarGroupRow: View {
    @Binding var group: SimilarGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let date = group.assets.first?.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                NavigationLink(destination: SimilarGroupDetailView(group: $group)) {
                    Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .padding(6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(group.assets) { asset in
                        let isMarkedForDelete = group.selectedForDelete.contains(asset.id)
                        
                        ZStack(alignment: .bottomTrailing) {
                            PhotoThumbnailView(asset: asset)
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isMarkedForDelete ? Color.red : Color.clear, lineWidth: 3)
                                )
                                .opacity(isMarkedForDelete ? 0.6 : 1.0)
                            
                            if isMarkedForDelete {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(.white))
                                    .offset(x: 5, y: 5)
                            }
                        }
                        .onTapGesture {
                            withAnimation {
                                if isMarkedForDelete {
                                    group.selectedForDelete.remove(asset.id)
                                } else {
                                    group.selectedForDelete.insert(asset.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SimilarGroupDetailView: View {
    @Binding var group: SimilarGroup
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        SwipeContainerView(
            assets: group.assets,
            onSwipeUp: { asset in
                // Swipe Up = Delete (Select for deletion)
                group.selectedForDelete.insert(asset.id)
            },
            onSwipeLeft: { asset in
                // Swipe Left = Keep (Unselect from deletion)
                group.selectedForDelete.remove(asset.id)
            },
            onUndo: {
                // Not strictly necessary here as user can just swipe back if SwipeContainer supports it
            },
            onFinished: {
                dismiss()
            }
        )
        .navigationTitle("检查详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
