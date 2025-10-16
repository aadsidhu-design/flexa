# FlexaSwiftUI Performance Optimization Guide

## 🚨 Critical Memory & CPU Issues Found

### **HIGHEST PRIORITY - MEMORY LEAKS & EXCESSIVE USAGE**

#### 1. **Timer Management Crisis**
**Location**: All game views (11+ files)
**Issue**: Multiple `Timer` objects created without proper cleanup
**Memory Impact**: HIGH - Timers retain strong references, causing memory leaks
**Files Affected**:
- `ArmRaisesGameView.swift` - 3 timers (game, incorrect message, motion)
- `WallClimbersGameView.swift` - 2 timers 
- `FanOutTheFlameGameView.swift` - 2 timers + CMMotionManager
- `ConstellationMakerGameView.swift` - 1 timer
- `MakeYourOwnGameView.swift` - 2 timers + CMMotionManager
- `OptimizedFruitSlicerGameView.swift` - Multiple timers
- `OptimizedWitchBrewGameView.swift` - Game timers

**Fix Strategy**:
```swift
// BAD - Current pattern
@State private var gameTimer: Timer?
gameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    updateGame()
}

// GOOD - Use Combine or async/await
import Combine
private var cancellables = Set<AnyCancellable>()

Timer.publish(every: 0.1, on: .main, in: .common)
    .autoconnect()
    .sink { _ in updateGame() }
    .store(in: &cancellables)
```

#### 2. **Array Growth Without Bounds**
**Location**: Motion tracking services
**Issue**: Arrays continuously growing without size limits
**Memory Impact**: CRITICAL - Can cause app crashes
**Files Affected**:
- `SimpleMotionService.swift` - 67 array operations
- `OptimizedFruitSlicerGameView.swift` - 49 array operations
- `SPARCCalculationService.swift` - 40 array operations

**Current Problems**:
```swift
// BAD - Unbounded growth
angleHistory.append(currentROM)
accelTimeline.append(accelMagnitude)
romPerRep.append(romValue)
```

**Fix Strategy**:
```swift
// GOOD - Bounded arrays with circular buffers
private let maxHistorySize = 600
angleHistory.append(currentROM)
if angleHistory.count > maxHistorySize {
    angleHistory.removeFirst()
}

// BETTER - Use circular buffer class
class CircularBuffer<T> {
    private var buffer: [T]
    private let maxSize: Int
    // Implementation with O(1) operations
}
```

#### 3. **AVCaptureSession & Camera Resource Management**
**Location**: Camera-based games and services
**Issue**: Multiple camera sessions, improper cleanup
**Memory Impact**: CRITICAL - Camera resources are expensive
**Files Affected**:
- `SimpleMotionService.swift` - AVCaptureSession management
- `LiveCameraWithSkeletonView.swift` - Camera preview
- All camera games (Wall Climbers, Balloon Pop, Constellation Maker)

**Problems**:
- Camera sessions not properly stopped
- Multiple simultaneous camera access attempts
- Preview layers accumulating

#### 4. **Core Motion Manager Instances**
**Location**: Multiple services creating CMMotionManager
**Issue**: Multiple motion managers running simultaneously
**Memory Impact**: HIGH - Each manager consumes significant resources
**Files Affected**:
- `FanOutTheFlameGameView.swift` - Creates own CMMotionManager
- `MakeYourOwnGameView.swift` - Creates own CMMotionManager
- `SimpleMotionService.swift` - Main motion manager
- `IMU3DROMTracker.swift` - Additional motion tracking

### **CPU INTENSIVE OPERATIONS**

#### 1. **High-Frequency Timer Updates**
**Issue**: 60Hz+ update loops in games
**CPU Impact**: CRITICAL - Constant main thread usage
**Examples**:
```swift
// BAD - 60Hz updates
Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true)

// BAD - 10Hz updates in games
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true)
```

#### 2. **Real-Time Motion Processing**
**Location**: Motion services and game updates
**CPU Impact**: HIGH - Complex calculations every frame
**Operations**:
- SPARC calculations (FFT operations)
- ROM angle calculations (trigonometry)
- Pose estimation (Apple Vision)
- Skeleton drawing (UIBezierPath operations)

#### 3. **Synchronous Firebase Operations**
**Location**: `FirebaseService.swift` (76 async operations)
**Issue**: Blocking operations on main thread
**CPU Impact**: MEDIUM - UI freezes during uploads

### **MEMORY OPTIMIZATION STRATEGIES**

#### 1. **Implement Lazy Loading**
```swift
// For large data structures
@Published private(set) var sessions: [ExerciseSessionData] = []
private var _allSessions: [ExerciseSessionData]?

var allSessions: [ExerciseSessionData] {
    if _allSessions == nil {
        _allSessions = loadSessionsFromDisk()
    }
    return _allSessions ?? []
}
```

#### 2. **Use Weak References for Delegates**
```swift
// BAD
var delegate: SomeDelegate?

// GOOD
weak var delegate: SomeDelegate?
```

#### 3. **Implement Object Pooling for Frequent Allocations**
```swift
class SKNodePool {
    private var availableNodes: [SKNode] = []
    
    func getNode() -> SKNode {
        return availableNodes.popLast() ?? SKNode()
    }
    
    func returnNode(_ node: SKNode) {
        node.removeFromParent()
        availableNodes.append(node)
    }
}
```

#### 4. **Use Value Types Instead of Reference Types**
```swift
// BAD - Reference type
class MotionData {
    var x: Double
    var y: Double
    var z: Double
}

// GOOD - Value type
struct MotionData {
    let x: Double
    let y: Double  
    let z: Double
}
```

### **CPU OPTIMIZATION STRATEGIES**

#### 1. **Background Queue Processing**
```swift
// Move heavy calculations off main thread
DispatchQueue.global(qos: .userInitiated).async {
    let result = heavyCalculation()
    DispatchQueue.main.async {
        self.updateUI(with: result)
    }
}
```

#### 2. **Reduce Update Frequencies**
```swift
// BAD - 60Hz updates
let updateInterval = 1.0/60.0

// GOOD - Adaptive frequency based on need
let updateInterval = isGameActive ? 1.0/30.0 : 1.0/10.0
```

#### 3. **Use Instruments Profiling**
- Time Profiler for CPU usage
- Allocations for memory usage
- Leaks for memory leaks
- Energy Log for battery impact

### **IMMEDIATE ACTION ITEMS**

#### Priority 1 (Critical - Do First):
1. **Fix Timer Leaks** - Replace all Timer usage with Combine publishers
2. **Implement Array Bounds** - Add size limits to all growing arrays
3. **Consolidate Motion Managers** - Use single shared CMMotionManager
4. **Fix Camera Session Management** - Proper start/stop lifecycle

#### Priority 2 (High):
1. **Background Processing** - Move SPARC/ROM calculations off main thread
2. **Reduce Update Frequencies** - Lower timer frequencies where possible
3. **Implement Object Pooling** - For SpriteKit nodes and frequent allocations
4. **Add Memory Warnings** - Handle low memory situations

#### Priority 3 (Medium):
1. **Lazy Loading** - For large data structures
2. **Weak References** - Fix retain cycles
3. **Value Types** - Convert appropriate classes to structs
4. **Caching Strategies** - Cache expensive calculations

### **MONITORING & TESTING**

#### Memory Monitoring:
```swift
// Add memory usage tracking
func logMemoryUsage() {
    let info = mach_task_basic_info()
    let resident = info.resident_size / 1024 / 1024 // MB
    print("Memory usage: \(resident) MB")
}
```

#### Performance Testing:
- Test on older devices (iPhone 12, iPhone SE)
- Monitor during extended gameplay sessions
- Check memory usage after multiple game sessions
- Verify proper cleanup when backgrounding app

### **ESTIMATED IMPACT**

**Memory Reduction**: 60-80% reduction in memory usage
**CPU Usage**: 40-60% reduction in CPU usage  
**Battery Life**: 20-30% improvement
**App Stability**: Eliminate memory-related crashes
**User Experience**: Smoother gameplay, faster app launches

### **FILES REQUIRING IMMEDIATE ATTENTION**

1. `SimpleMotionService.swift` - Core service, affects everything
2. `OptimizedFruitSlicerGameView.swift` - Heaviest game
3. `FirebaseService.swift` - Background operations
4. `SPARCCalculationService.swift` - CPU-intensive calculations
5. All game view files - Timer management

**Total Files Needing Optimization**: 78+ files identified with performance issues
