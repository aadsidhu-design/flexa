# Game Uniformity Guide

## Uniform Structure
All games MUST use the same:
1. **Navigation Flow**: Instructions → Game → Analyzing → Results → Post Survey
2. **Results Page**: UnifiedResultsView 
3. **Analyzing Page**: AnalyzingView
4. **Survey Components**: PostSurveyView

## What Can Differ
ONLY these can be different between games:
1. **Game Mechanics**: The actual game logic/gameplay
2. **Game UI**: Scoring displays, game-specific overlays (some games may not have scores)
3. **Instruction Text**: Game-specific instructions
4. **Instruction Images**: Game-specific demonstration images

## Implementation
All games must use `UniformGameTemplate` which provides:
- Standardized state management
- Uniform navigation flow
- Consistent UI overlays
- Same results/survey flow

## Example Usage
```swift
UniformGameTemplate(exerciseType: "Fruit Slicer") { score, reps, rom in
    // ONLY game-specific content here
    FruitSlicerGameContent(score: score, reps: reps, rom: rom)
}
```
