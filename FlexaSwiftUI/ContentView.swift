import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @State private var selectedTab = 0
    @State private var showingCalibrationIntro = false
    
    var body: some View {
        NavigationStack(path: $navigationCoordinator.path) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tag(0)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                
                GamesView()
                    .tag(1)
                    .tabItem {
                        Image(systemName: "gamecontroller.fill")
                        Text("Games")
                    }
                
                EnhancedProgressViewFixed()
                    .tag(2)
                    .tabItem {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Progress")
                    }
                
                SettingsView()
                    .tag(3)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
            }
            .accentColor(.green)
            .navigationDestination(for: NavigationPath.self) { path in
                path
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToTab"))) { note in
            if let idx = note.userInfo?["tabIndex"] as? Int {
                selectedTab = idx
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToGamesTab"))) { _ in
            selectedTab = 1 // Games tab
        }
        .onAppear {
            // Check if user needs to complete ROM calibration on app launch
            let hasCompletedCalibration = UserDefaults.standard.bool(forKey: "hasCompletedROMCalibration")
            if !hasCompletedCalibration {
                showingCalibrationIntro = true
                print("🎯 User has not completed ROM calibration, showing intro screen on app launch")
            }
        }
        .fullScreenCover(isPresented: $showingCalibrationIntro) {
            CalibrationIntroView()
        }
    }
}


struct ContentStatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActivityCard: View {
    let gameName: String
    let duration: String
    let reps: Int
    let rom: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(gameName)
                    .font(.headline)
                
                Text(duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(reps) reps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(rom)° ROM")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    ContentView()
}
