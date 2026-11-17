import SwiftUI
import SwiftData
import OSLog

@main
struct FinancesApp: App {
    private static let schema = Schema([
        IncomePlan.self,
        BudgetCategory.self,
        MoneyEntry.self
    ])

    private let container: ModelContainer
    private let storageError: String?
    @State private var showingStorageError: Bool

    init() {
        do {
            container = try ModelContainer(for: Self.schema, configurations: [ModelConfiguration(schema: Self.schema)])
            storageError = nil
        } catch {
            // Keep the app usable instead of crashing, and tell the user nothing will be saved.
            Logger(subsystem: "Finances", category: "Storage").error("Could not open saved data: \(error.localizedDescription)")
            container = Self.temporaryContainer()
            storageError = error.localizedDescription
        }
        _showingStorageError = State(initialValue: storageError != nil)
    }

    private static func temporaryContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        } catch {
            fatalError("Could not create even a temporary data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert("Your saved data couldn't be opened", isPresented: $showingStorageError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("The app is running without saving, so anything you log now will be lost when you quit. Details: \(storageError ?? "")")
                }
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 820)
    }
}
