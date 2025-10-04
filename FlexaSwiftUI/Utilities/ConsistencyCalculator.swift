import Foundation

// Helper function for consistency calculation
func calculateConsistency(romData: [Double]) -> Double {
    guard romData.count > 1 else { return 1.0 }
    
    let mean = romData.reduce(0, +) / Double(romData.count)
    let variance = romData.map { pow($0 - mean, 2) }.reduce(0, +) / Double(romData.count)
    let standardDeviation = sqrt(variance)
    let coefficientOfVariation = mean > 0 ? standardDeviation / mean : 0
    
    return max(0, 1.0 - min(coefficientOfVariation, 1.0)) // 0-1 scale, higher = more consistent
}
