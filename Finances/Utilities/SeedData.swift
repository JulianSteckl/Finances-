import Foundation
import SwiftData

enum SeedData {
    /// Creates the base money plan on first launch.
    static func ensureDefaults(in context: ModelContext) {
        let existingPlans = (try? context.fetch(FetchDescriptor<IncomePlan>())) ?? []
        guard existingPlans.isEmpty else { return }

        let plan = IncomePlan()
        plan.payFrequency = .weekly
        context.insert(plan)
        do {
            try context.save()
        } catch {
            assertionFailure("Could not save the starting plan: \(error)")
        }
    }
}
