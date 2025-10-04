import Foundation
import Combine

class OfflineUploadQueue: ObservableObject {
    @Published var pendingUploads: Int = 0
    @Published var isProcessing = false
    
    private var queuedSessions: [ComprehensiveSessionData] = []
    private let queueKey = "offline_upload_queue"
    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadQueueFromStorage()
        setupNetworkObserver()
    }
    
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func queueForUpload(_ session: ComprehensiveSessionData) {
        queuedSessions.append(session)
        saveQueueToStorage()
        updatePendingCount()
        FlexaLog.backend.info("OfflineUploadQueue: queued session for offline upload exercise=\(session.exerciseName) id=\(session.id)")

        // Try immediate upload if connected
        if networkMonitor.isConnected {
            Task {
                await processQueue()
            }
        }
    }
    
    @MainActor
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        
        FlexaLog.backend.info("Starting to process offline upload queue - \(self.queuedSessions.count) items")
        
        let sessionsToProcess = Array(self.queuedSessions.prefix(5)) // Process up to 5 items at a time
        
        for session in sessionsToProcess {
            // Validate data before upload
            let validation = session.validateData()
            if !validation.isValid {
                FlexaLog.backend.error("Session data validation failed: \(validation.errors.joined(separator: ", "))")
                // Remove invalid session from queue
                removeFromQueue(session)
                continue
            }
            FlexaLog.backend.info("Session data validation passed for session \(session.id)")
            
            uploadSession(session)
        }
        
        isProcessing = false
    }
    
    private func removeFromQueue(_ session: ComprehensiveSessionData) {
        queuedSessions.removeAll { $0.id == session.id }
        saveQueueToStorage()
        updatePendingCount()
        FlexaLog.backend.info("Removed session \(session.id) from upload queue")
    }
    
    private func uploadSession(_ session: ComprehensiveSessionData) {
        FlexaLog.backend.info("Uploading session data for user \(session.userID), exercise: \(session.exerciseName)")
        
        // Log data structure info
        let dataDict = session.toDictionary()
        FlexaLog.backend.info("Session data structure - keys: \(dataDict.keys.sorted().joined(separator: ", "))")
        
        let uploadService = SessionUploadService()
        uploadService.uploadSessionData(session) { result in
            switch result {
            case .success:
                FlexaLog.backend.info("Successfully uploaded session data with \(session.totalReps) reps")
                Task { @MainActor in
                    self.removeFromQueue(session)
                }
            case .failure(let error):
                FlexaLog.backend.error("Failed to upload session data: \(error)")
                
                // Log specific error details
                if let nsError = error as NSError? {
                    FlexaLog.backend.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                    FlexaLog.backend.error("Error description: \(nsError.localizedDescription)")
                }
                
                // Keep session in queue for retry
                FlexaLog.backend.info("Session will remain in queue for retry")
            }
        }
    }
    
    private func loadQueueFromStorage() {
        if let data = UserDefaults.standard.data(forKey: queueKey) {
            do {
                let sessions = try JSONDecoder().decode([ComprehensiveSessionData].self, from: data)
                queuedSessions = sessions
            } catch {
                FlexaLog.backend.error("OfflineUploadQueue: corrupted cache detected — clearing queue error=\(error.localizedDescription)")
                queuedSessions.removeAll()
                UserDefaults.standard.removeObject(forKey: queueKey)
            }
        }

        updatePendingCount()
    }
    
    private func saveQueueToStorage() {
        do {
            let encoded = try JSONEncoder().encode(queuedSessions)
            UserDefaults.standard.set(encoded, forKey: queueKey)
        } catch {
            FlexaLog.backend.error("OfflineUploadQueue: failed to persist queue error=\(error.localizedDescription)")
        }
    }
    
    private func updatePendingCount() {
        DispatchQueue.main.async {
            self.pendingUploads = self.queuedSessions.count
        }
    }
}
