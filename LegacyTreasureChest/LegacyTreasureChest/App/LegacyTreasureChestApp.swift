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

    // MARK: - Monetization
    // @Observable service held with @State (not @StateObject -- it isn't
    // an ObservableObject) so SwiftUI preserves its identity across App
    // re-evaluations. Injected via .environment() below; begins loading
    // the Full Catalog Access product and refreshing entitlement
    // asynchronously as soon as it's constructed, without blocking launch.
    @State private var purchaseManager = PurchaseManager()

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

        // Capture the LTC 1.0 → 1.1 migration baseline exactly once, using
        // the actual persisted LTCItem count (not a screen's filtered
        // result). Safe to call on every launch — a no-op after the first.
        CatalogMigrationCoordinator.captureBaselineIfNeeded(modelContext: serviceContext)

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
                .environment(purchaseManager)
                .onAppear {
                    print("LegacyTreasureChestApp loaded.")
                }
        }
    }
}
