import Foundation

actor IgnoredGroupsService {
    static let shared = IgnoredGroupsService()
    private let key = "IgnoredSimilarGroups"
    
    private var ignoredSignatures: Set<String>
    
    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        self.ignoredSignatures = Set(saved)
    }
    
    func isIgnored(assets: [PhotoAsset]) -> Bool {
        let signature = generateSignature(for: assets)
        return ignoredSignatures.contains(signature)
    }
    
    func ignoreGroup(assets: [PhotoAsset]) {
        let signature = generateSignature(for: assets)
        ignoredSignatures.insert(signature)
        save()
    }
    
    private func generateSignature(for assets: [PhotoAsset]) -> String {
        return assets.map { $0.id }.sorted().joined(separator: "|")
    }
    
    private func save() {
        UserDefaults.standard.set(Array(ignoredSignatures), forKey: key)
    }
}
