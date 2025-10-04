# Project Structure

## Root Directory Organization
```
FlexaSwiftUI/                 # Main app source code
├── Assets.xcassets/          # App icons, images, and visual assets
├── Config/                   # Configuration files (environment keys, secure config)
├── Documentation/            # Technical documentation and guides
├── Games/                    # Game view implementations
├── Models/                   # Data models and structures
├── Navigation/               # Navigation management
├── Security/                 # Security utilities (KeychainManager)
├── Services/                 # Core business logic and data services
├── Utilities/                # Helper utilities and extensions
└── Views/                    # SwiftUI views and UI components
    └── Components/           # Reusable UI components

Config/                       # Build configuration
FlexaSwiftUI.xcodeproj/      # Xcode project files
InstructionsPhotos/          # Exercise instruction images
scripts/                     # Build and utility scripts
```

## Key Architectural Patterns

### Service Layer (`Services/`)
- **Singleton Services**: Core services use shared instances (e.g., `SimpleMotionService.shared`)
- **ObservableObject**: Services conform to ObservableObject for SwiftUI reactivity
- **Dependency Injection**: Services injected via environment objects in app root

### View Architecture (`Views/`)
- **Feature-based Organization**: Views grouped by functionality
- **Component Reusability**: Common UI elements in `Components/` subfolder
- **Environment Integration**: Views access services via `@EnvironmentObject`

### Models (`Models/`)
- **Data Structures**: Simple Swift structs for data representation
- **Session Data**: Comprehensive session tracking models
- **Body Tracking**: Skeleton and pose-related data models

## File Naming Conventions
- **Views**: Descriptive names ending with `View` (e.g., `CalibrationWizardView.swift`)
- **Services**: Descriptive names ending with `Service` (e.g., `SimpleMotionService.swift`)
- **Models**: Descriptive names for data structures (e.g., `SessionFile.swift`)
- **Games**: Game names ending with `GameView` (e.g., `BalloonPopGameView.swift`)

## Configuration Files
- **Info.plist**: Located in `Config/Info.plist` (custom location)
-- **GoogleService-Info.plist**: (removed) Previously used for Firebase; repo migrated to Appwrite. See Documentation/MIGRATION.md for details
- **Environment Keys**: Secure configuration in `Config/` directory

## Documentation Standards
- **Technical Docs**: Stored in `FlexaSwiftUI/Documentation/`
- **Code Comments**: Inline documentation for complex algorithms
- **API Documentation**: Service methods documented with usage examples
- **Architecture Decisions**: Major changes documented in summary files

## Asset Organization
- **App Icons**: Multiple sizes in `Assets.xcassets/AppIcon.appiconset/`
- **Instruction Images**: Exercise photos in dedicated `imageset` folders
- **Color Assets**: Accent colors and theme colors in asset catalog