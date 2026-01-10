import Foundation
import Vision

actor SimilarityCacheManager {
    static let shared = SimilarityCacheManager()
    private let fileURL: URL
    
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.fileURL = caches.appendingPathComponent("featurePrints.cache")
    }
    
    func save(prints: [String: VNFeaturePrintObservation]) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: prints, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save feature prints: \(error)")
        }
    }
    
    func load() -> [String: VNFeaturePrintObservation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            if let prints = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, VNFeaturePrintObservation.self], from: data) as? [String: VNFeaturePrintObservation] {
                return prints
            }
        } catch {
            print("Failed to load feature prints: \(error)")
        }
        return [:]
    }
}
