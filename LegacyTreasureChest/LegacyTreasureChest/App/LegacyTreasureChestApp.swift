//
//  LegacyTreasureChestApp.swift
//  LegacyTreasureChest
//
//  App entry point.
//  Initializes SwiftData and Authentication,
//  and switches between AuthenticationView and HomeView.
//

import SwiftUI
import SwiftData

@main
struct LegacyTreasureChestApp: App {
    
    // MARK: - Core Persistence
    let modelContainer: ModelContainer
    
    // MARK: - ViewModels
    @StateObject private var authViewModel: AuthenticationViewModel
    
    // MARK: - Init
    init() {
        // Initialize SwiftData container
        do {
            modelContainer = try ModelContainer.makeContainer()
            print("✅ ModelContainer created successfully")
        } catch {
            fatalError("❌ Failed to create ModelContainer: \(error)")
        }
        
        // Create a ModelContext just for services
        let serviceContext = ModelContext(modelContainer)
        
        // Create the authentication service as a LOCAL value
        let authService = AuthenticationService(modelContext: serviceContext)
        
        // Initialize the @StateObject without capturing `self`
        _authViewModel = StateObject(
            wrappedValue: AuthenticationViewModel(authService: authService)
        )
    }
    
    // MARK: - Scene
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: authViewModel)
                .modelContainer(modelContainer)   // ← REQUIRED
                .onAppear {
                    print("LegacyTreasureChestApp loaded.")
                }
        }
    }
}
