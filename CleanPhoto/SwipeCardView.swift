import SwiftUI
import Photos
import CoreLocation
import ImageIO

struct SwipeCardView: View {
    let asset: PhotoAsset
    let progressText: String?
    let onSwipeUp: () -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: (() -> Void)? // Optional, because only available if history exists
    
    @State private var offset: CGSize = .zero
    @State private var image: UIImage?
    @State private var metadata: PhotoMetadata?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .shadow(radius: 5)
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ProgressView()
            }

            if let progressText {
                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }

            if let metadata, !metadata.lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metadata.lines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(12)
            }
            
            // Visual indicators for swipe direction
            VStack {
                if offset.height < -50 {
                    Image(systemName: "trash")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .padding()
                        .background(Circle().fill(.white.opacity(0.8)))
                        .transition(.scale)
                }
                Spacer()
                if offset.width < -50 {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                        .padding()
                        .background(Circle().fill(.white.opacity(0.8)))
                        .transition(.scale)
                }
            }
            .padding(40)
            
            // Right swipe (Back) indicator
            HStack {
                if offset.width > 50 {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                        .padding()
                        .background(Circle().fill(.white.opacity(0.8)))
                        .transition(.scale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                }
            }
        }
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    // Limit right swipe if no callback provided
                    if gesture.translation.width > 0 && onSwipeRight == nil {
                        offset = CGSize(width: gesture.translation.width * 0.1, height: gesture.translation.height)
                    } else {
                        offset = gesture.translation
                    }
                }
                .onEnded { gesture in
                    handleDragEnded(gesture)
                }
        )
        .task(id: asset.id) {
            loadProgressiveImage()
            metadata = await loadMetadata()
        }
    }
    
    private func handleDragEnded(_ gesture: DragGesture.Value) {
        let horizontalThreshold: CGFloat = 150
        let verticalThreshold: CGFloat = -150
        
        if gesture.translation.height < verticalThreshold {
            // Swipe Up -> Delete
            withAnimation(.spring()) {
                offset = CGSize(width: 0, height: -1000)
            }
            onSwipeUp()
        } else if gesture.translation.width < -horizontalThreshold {
            // Swipe Left -> Keep
            withAnimation(.spring()) {
                offset = CGSize(width: -1000, height: 0)
            }
            onSwipeLeft()
        } else if gesture.translation.width > horizontalThreshold, let onSwipeRight {
            // Swipe Right -> Back/Undo
            withAnimation(.spring()) {
                offset = CGSize(width: 1000, height: 0)
            }
            onSwipeRight()
        } else {
            // Reset
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }
    
    private func loadProgressiveImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset.asset,
            targetSize: CGSize(width: 1000, height: 1000),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }

    private func loadMetadata() async -> PhotoMetadata? {
        let dateText = asset.creationDate.map { Self.dateFormatter.string(from: $0) }
        
        var locationText: String?
        if let location = asset.location {
            locationText = await resolveLocationName(location)
        }
        
        let deviceText = await requestDeviceModel()

        guard dateText != nil || locationText != nil || deviceText != nil else { return nil }
        return PhotoMetadata(dateText: dateText, locationText: locationText, deviceText: deviceText)
    }

    private func resolveLocationName(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            guard let placemark = placemarks.first else { return nil }
            return placemark.locality ?? placemark.administrativeArea ?? placemark.country
        } catch {
            return nil
        }
    }

    private func requestDeviceModel() async -> String? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            var didResume = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset.asset,
                options: options
            ) { data, _, _, _ in
                guard !didResume else { return }
                didResume = true
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.deviceText(from: data))
            }
        }
    }

    private static func deviceText(from imageData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else {
            return nil
        }

        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = [make, model].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct PhotoMetadata {
    let dateText: String?
    let locationText: String?
    let deviceText: String?

    var lines: [String] {
        var items: [String] = []
        if let dateText {
            items.append("日期: \(dateText)")
        }
        if let locationText {
            items.append("地点: \(locationText)")
        }
        if let deviceText {
            items.append("设备: \(deviceText)")
        }
        return items
    }
}
