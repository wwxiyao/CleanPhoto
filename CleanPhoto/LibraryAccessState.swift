import Photos

enum LibraryAccessState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    init(status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .limited:
            self = .limited
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }

    var canRead: Bool {
        self == .authorized || self == .limited
    }
}
