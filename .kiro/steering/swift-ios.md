# Swift iOS Development Guidelines

## Project Context
This is a **Swift iOS application** called FlexaSwiftUI - a healthcare fitness app for Apple iOS devices.

## Development Standards
When writing, reviewing, or modifying code in this project, always follow these guidelines:

### Language & Platform
- **Language**: Swift 5.0+
- **Platform**: iOS (minimum deployment target: iOS 16.0)
- **UI Framework**: SwiftUI with dark mode preference
- **Architecture**: MVVM with ObservableObject services

### Swift Best Practices
- Follow Apple's Swift API Design Guidelines
- Use proper Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Leverage Swift's type safety and optional handling
- Use proper optional chaining (`?.`) and nil-coalescing (`??`) operators
- Prefer `guard` statements for early returns
- Use `@Published` properties for reactive UI updates
- Follow SwiftUI view composition patterns

### iOS-Specific Considerations
- Use iOS-native frameworks (ARKit, Vision, CoreMotion, AVFoundation)
- Follow iOS app lifecycle patterns
- Implement proper memory management
- Use iOS-appropriate design patterns (Delegate, Observer, Singleton where appropriate)
- Consider iOS accessibility guidelines
- Handle iOS permissions properly (camera, motion sensors)

### Code Quality
- Write self-documenting code with clear variable and function names
- Add inline comments for complex algorithms or business logic
- Use Swift's built-in error handling (`throws`, `try`, `catch`)
- Prefer immutable data structures when possible
- Use dependency injection for testability

### Apple Ecosystem Integration
- Follow Apple Human Interface Guidelines
- Use Apple's recommended app architecture patterns
- Integrate properly with iOS system features
- Consider Apple's privacy and security guidelines

### Important
- Make sure your Swift code is perfect and runs without any errors
- Use proper Swift linting tools (e.g., SwiftLint, SwiftGen)
- Follow the [Swift iOS Development Guidelines](XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX)