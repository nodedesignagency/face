import CatFaceUI
import SwiftUI

@main
struct CatFaceApp: App {
    var body: some Scene {
        WindowGroup {
            CatFaceView()
            #if os(macOS)
                .frame(minWidth: 380, minHeight: 460)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 640)
        #endif
    }
}
