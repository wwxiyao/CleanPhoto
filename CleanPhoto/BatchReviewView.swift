import SwiftUI
import Photos

struct BatchReviewView: View {
    let assets: [PhotoAsset]
    let onRecover: (PhotoAsset) -> Void
    let onDeleteAll: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack {
            if assets.isEmpty {
                EmptyStateView(
                    title: "Nothing to Delete",
                    message: "You kept all photos in this batch.",
                    actionTitle: "Next Batch",
                    action: onSkip
                )
            } else {
                List {
                    Section(header: Text("Items to Delete (\(assets.count))")) {
                        ForEach(assets) { asset in
                            HStack {
                                PhotoThumbnailView(asset: asset)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                
                                Spacer()
                                
                                Button("Recover") {
                                    onRecover(asset)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    Button(action: onDeleteAll) {
                        Text("Confirm and Delete \(assets.count) Photos")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("Skip for Now", action: onSkip)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Review Batch")
    }
}
