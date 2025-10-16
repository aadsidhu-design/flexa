//
//  TestROMProcessor.swift
//  FlexaSwiftUI
//
//  Created by Copilot on 10/6/25.
//
//  🔬 Utility helpers for ROM testing harness.
//  Takes a stream of ARKit transforms, fits a best-fit plane, and projects to 2D.
//

import Foundation
import simd

enum TestROMPattern: String, CaseIterable, Identifiable {
    case circle
    case arc

    var id: String { rawValue }
}

struct TestROMProjectionResult {
    let centroid: SIMD3<Float>
    let normal: SIMD3<Float>
    let basisX: SIMD3<Float>
    let basisY: SIMD3<Float>
    let projectedPoints: [SIMD2<Float>]
}

struct TestROMMetrics {
    let projection: TestROMProjectionResult
    let averageRadius: Double
    let radiusStdDev: Double
    let coverageDegrees: Double
    let pattern: TestROMPattern
}

/// Lightweight math helpers to analyse ROM trajectories for debug/testing.
final class TestROMProcessor {
    func process(points: [SIMD3<Float>], pattern: TestROMPattern) -> TestROMMetrics? {
        guard points.count >= 3 else { return nil }
        let projection = fitAndProject(points: points)
        let radii = projection.projectedPoints.map { Double(simd_length($0)) }
        guard !radii.isEmpty else { return nil }

        let averageRadius = radii.reduce(0, +) / Double(radii.count)
        let radiusVariance = radii.reduce(0.0) { partial, radius in
            let diff = radius - averageRadius
            return partial + diff * diff
        } / Double(max(radii.count - 1, 1))
        let radiusStdDev = sqrt(max(radiusVariance, 0.0))

        let coverageDegrees: Double
        switch pattern {
        case .circle:
            coverageDegrees = estimateAngularCoverage(points: projection.projectedPoints)
        case .arc:
            coverageDegrees = estimateAngularCoverage(points: projection.projectedPoints)
        }

        return TestROMMetrics(
            projection: projection,
            averageRadius: averageRadius,
            radiusStdDev: radiusStdDev,
            coverageDegrees: coverageDegrees,
            pattern: pattern
        )
    }

    private func fitAndProject(points: [SIMD3<Float>]) -> TestROMProjectionResult {
        let centroid = points.reduce(SIMD3<Float>(repeating: 0)) { $0 + $1 } / Float(points.count)

        let zeroRow = SIMD3<Double>(repeating: 0)
        var covariance = simd_double3x3(rows: [zeroRow, zeroRow, zeroRow])
        for p in points {
            let diff = SIMD3<Double>(Double(p.x - centroid.x), Double(p.y - centroid.y), Double(p.z - centroid.z))
            covariance += matrix_double3x3(outerProduct: diff)
        }
        let normalizationFactor = Double(points.count)
        let scale = 1.0 / normalizationFactor
        covariance = simd_double3x3(
            columns: (
                covariance.columns.0 * scale,
                covariance.columns.1 * scale,
                covariance.columns.2 * scale
            )
        )

        let eigen = covariance.symmetricEigenDecomposition()
        let eigenPairs: [(value: Double, vector: SIMD3<Double>)] = [
            (eigen.values.x, eigen.vectors.columns.0),
            (eigen.values.y, eigen.vectors.columns.1),
            (eigen.values.z, eigen.vectors.columns.2)
        ].sorted { $0.value > $1.value }

        let axisXRaw = SIMD3<Float>(eigenPairs[0].vector)
        let axisYRaw = SIMD3<Float>(eigenPairs[1].vector)
        let normalRaw = SIMD3<Float>(eigenPairs[2].vector)

        let axisX = axisXRaw.normalizedOrFallback(fallback: SIMD3<Float>(1, 0, 0))
        let axisY = axisYRaw.normalizedOrFallback(fallback: SIMD3<Float>(0, 1, 0))
        var normal = normalRaw.normalizedOrFallback(fallback: SIMD3<Float>(0, 0, 1))

        // Ensure right-handed basis (axisX × axisY should point along normal)
        let crossCheck = simd_cross(axisX, axisY)
        if simd_dot(crossCheck, normal) < 0 {
            normal *= -1
        }

        let projectedPoints = points.map { point -> SIMD2<Float> in
            let relative = point - centroid
            let x = simd_dot(relative, axisX)
            let y = simd_dot(relative, axisY)
            return SIMD2<Float>(x, y)
        }

        return TestROMProjectionResult(
            centroid: centroid,
            normal: normal,
            basisX: axisX,
            basisY: axisY,
            projectedPoints: projectedPoints
        )
    }

    private func estimateAngularCoverage(points: [SIMD2<Float>]) -> Double {
        guard points.count >= 2 else { return 0.0 }
        let angles = points.map { Double(atan2($0.y, $0.x)) }.sorted()
        guard let first = angles.first else { return 0.0 }
        var maxGap = 0.0
        for idx in 1..<angles.count {
            let gap = angles[idx] - angles[idx - 1]
            if gap > maxGap { maxGap = gap }
        }
        // Also consider wrap-around gap between last and first + 2π
        if let last = angles.last {
            let wrapGap = (first + 2 * .pi) - last
            if wrapGap > maxGap { maxGap = wrapGap }
        }
        // Coverage is 360° minus largest empty gap (converted to degrees)
        let coverageRadians = (2 * Double.pi) - maxGap
        return max(min(coverageRadians * 180.0 / .pi, 360.0), 0.0)
    }
}

private extension matrix_double3x3 {
    init(outerProduct v: SIMD3<Double>) {
        self.init(rows: [
            SIMD3<Double>(v.x * v.x, v.x * v.y, v.x * v.z),
            SIMD3<Double>(v.y * v.x, v.y * v.y, v.y * v.z),
            SIMD3<Double>(v.z * v.x, v.z * v.y, v.z * v.z)
        ])
    }
}

private extension SIMD3 where Scalar == Float {
    init(_ vector: SIMD3<Double>) {
        self.init(Float(vector.x), Float(vector.y), Float(vector.z))
    }

    func normalizedOrFallback(fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(self)
        guard length > 0 else { return fallback }
        return self / length
    }
}

private extension simd_double3x3 {
    func symmetricEigenDecomposition(maxIterations: Int = 32, epsilon: Double = 1e-10) -> (values: SIMD3<Double>, vectors: simd_double3x3) {
        var a = [
            [self.columns.0.x, self.columns.1.x, self.columns.2.x],
            [self.columns.0.y, self.columns.1.y, self.columns.2.y],
            [self.columns.0.z, self.columns.1.z, self.columns.2.z]
        ]

        var v = [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
        ]

        guard maxIterations > 0 else {
            return (
                SIMD3<Double>(a[0][0], a[1][1], a[2][2]),
                simd_double3x3(columns: (
                    SIMD3<Double>(v[0][0], v[1][0], v[2][0]),
                    SIMD3<Double>(v[0][1], v[1][1], v[2][1]),
                    SIMD3<Double>(v[0][2], v[1][2], v[2][2])
                ))
            )
        }

        for _ in 0..<maxIterations {
            var p = 0
            var q = 1
            var maxOffDiagonal = abs(a[0][1])

            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    let value = abs(a[i][j])
                    if value > maxOffDiagonal {
                        maxOffDiagonal = value
                        p = i
                        q = j
                    }
                }
            }

            if maxOffDiagonal < epsilon {
                break
            }

            let app = a[p][p]
            let aqq = a[q][q]
            let apq = a[p][q]

            let tau = (aqq - app) / (2.0 * apq)
            let tDenominator = tau >= 0 ? tau + sqrt(1.0 + tau * tau) : tau - sqrt(1.0 + tau * tau)
            let t = 1.0 / tDenominator
            let c = 1.0 / sqrt(1.0 + t * t)
            let s = t * c

            for i in 0..<3 {
                if i == p || i == q { continue }
                let aip = a[i][p]
                let aiq = a[i][q]
                a[i][p] = aip * c - aiq * s
                a[p][i] = a[i][p]
                a[i][q] = aip * s + aiq * c
                a[q][i] = a[i][q]
            }

            let appNew = c * c * app - 2.0 * s * c * apq + s * s * aqq
            let aqqNew = s * s * app + 2.0 * s * c * apq + c * c * aqq
            a[p][p] = appNew
            a[q][q] = aqqNew
            a[p][q] = 0.0
            a[q][p] = 0.0

            for i in 0..<3 {
                let vip = v[i][p]
                let viq = v[i][q]
                v[i][p] = vip * c - viq * s
                v[i][q] = vip * s + viq * c
            }
        }

        let values = SIMD3<Double>(a[0][0], a[1][1], a[2][2])
        let vectors = simd_double3x3(columns: (
            SIMD3<Double>(v[0][0], v[1][0], v[2][0]),
            SIMD3<Double>(v[0][1], v[1][1], v[2][1]),
            SIMD3<Double>(v[0][2], v[1][2], v[2][2])
        ))

        return (values, vectors)
    }
}
