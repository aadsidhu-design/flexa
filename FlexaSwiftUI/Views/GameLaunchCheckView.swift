import SwiftUI

struct GameLaunchCheckView: View {
    let gameType: GameType
    let preSurveyData: PreSurveyData
    @StateObject private var calibrationCheckService = CalibrationCheckService.shared
    @State private var showingCalibrationIntro = false
    
    var body: some View {
        Group {
            if calibrationCheckService.isCalibrated {
                CleanGameHostView(gameType: gameType, preSurveyData: preSurveyData)
            } else {
                CalibrationIntroView()
            }
        }
        .onAppear {
            if !calibrationCheckService.isCalibrated {
                print("🎯 User has not completed ROM calibration, showing intro screen")
            }
        }
    }
}

#Preview {
    GameLaunchCheckView(
        gameType: .fruitSlicer,
        preSurveyData: PreSurveyData(painLevel: 0, timestamp: Date(), exerciseReadiness: nil, previousExerciseHours: nil) // painLevel kept for compatibility
    )
}
