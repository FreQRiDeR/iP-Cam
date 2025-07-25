//
//  iP_CamApp.swift
//  iP-Cam
//
//  Created by terraMODA on 7/23/25.
//

import SwiftUI

@main
struct iP_CamApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
