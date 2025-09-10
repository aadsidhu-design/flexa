import SwiftUI

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
            
            VStack(spacing: 1) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            SettingsRowContent(
                icon: icon,
                title: title,
                subtitle: subtitle,
                isDestructive: isDestructive
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsRowContent: View {
    let icon: String
    let title: String
    let subtitle: String
    var isDestructive: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isDestructive ? .red : .green)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isDestructive ? .red : .white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.green)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .green))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsStatusRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.green)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(isGranted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(isGranted ? "Granted" : "Required")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isGranted ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct AboutUsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("About Flexa")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Revolutionizing Physiotherapy Rehabilitation")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                
                // Mission Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Our Mission")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Flexa combines cutting-edge technology with proven physiotherapy techniques to make rehabilitation engaging, effective, and accessible. Our machine learning-powered platform provides real-time feedback and personalized exercise programs to help patients recover faster and maintain long-term health.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                }
                
                // Features Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Key Features")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 12) {
                        FeatureRow(
                            icon: "camera.fill",
                            title: "ML Pose Detection",
                            description: "Advanced machine learning tracks your movements in real-time"
                        )
                        
                        FeatureRow(
                            icon: "brain.head.profile",
                            title: "ML Analysis & SPARC",
                            description: "Machine learning for ROM calculations and SPARC analysis"
                        )
                        
                        FeatureRow(
                            icon: "gamecontroller.fill",
                            title: "Gamified Exercises",
                            description: "Engaging games that make rehabilitation fun and motivating"
                        )
                        
                        FeatureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Progress Tracking",
                            description: "Comprehensive analytics to monitor your recovery journey"
                        )
                        
                        FeatureRow(
                            icon: "target",
                            title: "Goal Setting",
                            description: "Personalized goals and streak tracking for motivation"
                        )
                    }
                }
                
                // Technology Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Technology")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Built with SwiftUI for iOS, powered by machine learning for pose detection and ROM/SPARC calculations, Firebase for data management. Our platform ensures your data privacy while delivering cutting-edge rehabilitation technology.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                }
                
                // Contact Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contact Us")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.green)
                            Text("aadjotsidhu@gmail.com")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.green)
                            Text("justforeyes.net")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.green)
                            Text("Developer: Aadjot Sidhu")
                                .foregroundColor(.gray)
                        }
                        
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.green)
                            Text("Physician Mentor: Gloria Wu")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.green)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.gray)
                    .lineSpacing(2)
            }
        }
        .padding(.vertical, 4)
    }
}
