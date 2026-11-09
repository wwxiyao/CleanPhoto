import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CleanPhotoLogic

struct PhotoDeviceMetadataTests {
    @Test func readsCameraFromRealJPEGMetadata() throws {
        let bytes = Data([128])
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
                                        bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                                        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        let properties = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"]] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
        #expect(PhotoDeviceMetadata.text(from: output as Data) == "Apple iPhone")
    }

    @Test func absentOrInvalidImageMetadataHasNoCameraLabel() {
        #expect(PhotoDeviceMetadata.text(from: Data()) == nil)
    }
}
