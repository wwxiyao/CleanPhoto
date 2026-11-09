//
//  CleanPhotoApp.swift
//  CleanPhoto
//
//  Created by 阿哞 on 2026/1/9.
//

import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

@main
struct CleanPhotoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    for scene in UIApplication.shared.connectedScenes {
                        (scene as? UIWindowScene)?.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 600)
                    }
                }
                #endif
        }
    }
}
