import Foundation
import ImageIO

nonisolated enum PhotoDeviceMetadata {
    static func text(from imageData: Data) -> String? {
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

}
