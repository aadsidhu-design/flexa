import SwiftUI

struct ContentViewRefactored: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var motionService: SimpleMotionService
    @EnvironmentObject var backendService: BackendService
    
    var body: some View {
        TabView(selection: $navigationManager.currentTab) {
            HomeView()
                .tag(0)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            GamesView()
                .tag(1)
                .tabItem {
                    Label("Games", systemImage: "gamecontroller.fill")
                }
            
            EnhancedProgressViewFixed()
                .tag(2)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            SettingsView()
                .tag(3)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.green)
    }
}

#Preview {
    ContentViewRefactored()
        .environmentObject(NavigationManager())
        .environmentObject(SimpleMotionService.shared)
        .environmentObject(BackendService())
}
