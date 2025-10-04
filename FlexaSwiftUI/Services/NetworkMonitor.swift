import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType = .other
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else {
                    self?.connectionType = .other
                }
                
                print("Network status: \(self?.isConnected == true ? "Connected" : "Disconnected") via \(String(describing: self?.connectionType))")
            }
        }
        
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
