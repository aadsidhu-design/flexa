import Foundation
import Combine

/// Manages persistence and retrieval of user-created custom exercises
class CustomExerciseManager: ObservableObject {
    static let shared = CustomExerciseManager()
    
    @Published private(set) var customExercises: [CustomExercise] = []
    @Published private(set) var latestAnalysis: (analysis: AIExerciseAnalysis, prompt: String)?
    
    private let userDefaultsKey = "com.flexa.customExercises"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        loadExercises()
    }
    
    // MARK: - Public API
    
    /// Add a new custom exercise
    func addExercise(_ exercise: CustomExercise) {
        customExercises.append(exercise)
        saveExercises()
        FlexaLog.lifecycle.info("✅ [CustomExercise] Added '\(exercise.name)' (ID: \(exercise.id.uuidString, privacy: .public))")
    }

    /// Persist latest AI analysis details for instruction surfaces
    func storeLatestAnalysis(_ analysis: AIExerciseAnalysis, prompt: String) {
        latestAnalysis = (analysis, prompt)
        FlexaLog.lifecycle.info("🧠 [CustomExercise] Stored latest AI analysis for \(analysis.exerciseName, privacy: .public)")
    }
    
    /// Update an existing exercise (e.g., after completion)
    func updateExercise(_ exercise: CustomExercise) {
        if let index = customExercises.firstIndex(where: { $0.id == exercise.id }) {
            customExercises[index] = exercise
            saveExercises()
            FlexaLog.lifecycle.info("📝 [CustomExercise] Updated '\(exercise.name)'")
        }
    }
    
    /// Remove a custom exercise
    func deleteExercise(id: UUID) {
        customExercises.removeAll { $0.id == id }
        saveExercises()
        FlexaLog.lifecycle.info("🗑️ [CustomExercise] Deleted exercise \(id.uuidString, privacy: .public)")
    }
    
    /// Record completion of a custom exercise with session data
    func recordCompletion(for exerciseId: UUID, rom: Double, sparc: Double) {
        guard let index = customExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        
        var exercise = customExercises[index]
        exercise.timesCompleted += 1
        
        // Update running averages
        if let avgROM = exercise.averageROM {
            exercise.averageROM = (avgROM * Double(exercise.timesCompleted - 1) + rom) / Double(exercise.timesCompleted)
        } else {
            exercise.averageROM = rom
        }
        
        if let avgSPARC = exercise.averageSPARC {
            exercise.averageSPARC = (avgSPARC * Double(exercise.timesCompleted - 1) + sparc) / Double(exercise.timesCompleted)
        } else {
            exercise.averageSPARC = sparc
        }
        
        customExercises[index] = exercise
        saveExercises()
        
        FlexaLog.lifecycle.info("🎉 [CustomExercise] Recorded completion #\(exercise.timesCompleted) for '\(exercise.name)'")
    }
    
    /// Get exercise by ID
    func getExercise(id: UUID) -> CustomExercise? {
        return customExercises.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private func saveExercises() {
        do {
            let data = try encoder.encode(customExercises)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            FlexaLog.lifecycle.debug("💾 [CustomExercise] Saved \(self.customExercises.count) exercises")
        } catch {
            FlexaLog.lifecycle.error("❌ [CustomExercise] Failed to save: \(error.localizedDescription)")
        }
    }
    
    private func loadExercises() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            FlexaLog.lifecycle.info("📂 [CustomExercise] No saved exercises found")
            return
        }
        
        do {
            customExercises = try decoder.decode([CustomExercise].self, from: data)
            FlexaLog.lifecycle.info("📂 [CustomExercise] Loaded \(self.customExercises.count) exercises")
        } catch {
            FlexaLog.lifecycle.error("❌ [CustomExercise] Failed to load: \(error.localizedDescription)")
        }
    }
}

extension CustomExerciseManager {
    var latestGuidanceSummary: String? {
        guard let record = latestAnalysis else { return nil }
        let reasoning = record.analysis.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasoning.isEmpty { return reasoning }
        let prompt = record.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }
}
