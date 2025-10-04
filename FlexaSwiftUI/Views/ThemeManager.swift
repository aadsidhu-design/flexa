import SwiftUI
import UIKit

class ThemeManager: ObservableObject {
    @Published var isDarkMode: Bool
    private var appearanceObserver: NSObjectProtocol?
    
    init() {
        // Follow system appearance
        self.isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        
        // Listen for system appearance changes
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTheme()
        }
    }

    deinit {
        if let token = appearanceObserver {
            NotificationCenter.default.removeObserver(token)
            appearanceObserver = nil
        }
    }
    
    private func updateTheme() {
        let newIsDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        if newIsDarkMode != isDarkMode {
            isDarkMode = newIsDarkMode
        }
    }
    
    var backgroundColor: Color {
        isDarkMode ? .black : Color(.systemBackground)
    }
    
    var primaryTextColor: Color {
        isDarkMode ? .white : Color(.label)
    }
    
    var secondaryTextColor: Color {
        isDarkMode ? .gray : Color(.secondaryLabel)
    }
    
    var cardBackgroundColor: Color {
        isDarkMode ? Color.gray.opacity(0.1) : Color(.secondarySystemBackground)
    }
    
    var overlayBackgroundColor: Color {
        isDarkMode ? Color.black.opacity(0.9) : Color.white.opacity(0.95)
    }
    
    var borderColor: Color {
        isDarkMode ? Color.gray.opacity(0.3) : Color(.separator)
    }
    
    var gameBackgroundColor: Color {
        isDarkMode ? .black : Color(.systemGray6)
    }
    
    var accentColor: Color {
        .green // Keep consistent across themes
    }
    
    var warningBackgroundColor: Color {
        isDarkMode ? Color.black.opacity(0.9) : Color.white.opacity(0.95)
    }
}

// Environment key for theme
struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeManager()
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
