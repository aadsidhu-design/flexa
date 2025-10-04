import SwiftUI

struct CalibrationRequiredView: View {
    @EnvironmentObject var calibrationCheck: CalibrationCheckService
    @EnvironmentObject var motionService: SimpleMotionService
    @Environment(\.dismiss) private var dismiss
    @State private var showingCalibration = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Calibration Icon
                Image(systemName: "target")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                
                // Title
                Text("Calibration Required")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // Description
                VStack(spacing: 16) {
                    Text("To play this game, you need to calibrate your device first.")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    Text("This ensures accurate motion tracking and ROM measurement.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Calibration Button
                Button(action: {
                    showingCalibration = true
                }) {
                    Text("Start Calibration")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                // Skip Button (for testing)
                Button(action: {
                    calibrationCheck.markCalibrationCompleted()
                }) {
                    Text("Skip (Testing Only)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingCalibration) {
            CalibrationWizardView()
                .environmentObject(motionService)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalibrationCompleted"))) { _ in
                    showingCalibration = false
                    calibrationCheck.checkCalibrationStatus()
                    dismiss()
                }
        }
    }
}

#Preview {
    CalibrationRequiredView()
        .environmentObject(CalibrationCheckService.shared)
        .environmentObject(SimpleMotionService.shared)
}
