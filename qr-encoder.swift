import Foundation

// MARK: - Error Types
enum QREncoderError: Error {
    case dataOverflow(String)
    case invalidVersion(String)
    case invalidMode(String)
    case invalidErrorLevel(String)
    case invalidMask(String)
}

// MARK: - Constants
enum QRConstants {
    static let VERSION_M1 = 0
    static let VERSION_M2 = -1
    static let VERSION_M3 = -2
    static let VERSION_M4 = -3
    
    static let ERROR_LEVEL_L = 0
    static let ERROR_LEVEL_M = 1
    static let ERROR_LEVEL_Q = 2
    static let ERROR_LEVEL_H = 3
    
    static let MODE_NUMERIC = 1
    static let MODE_ALPHANUMERIC = 2
    static let MODE_BYTE = 4
    static let MODE_KANJI = 8
    static let MODE_ECI = 7
    static let MODE_HANZI = 13
    static let MODE_STRUCTURED_APPEND = 3
    
    static let DEFAULT_BYTE_ENCODING = "iso-8859-1"
    static let KANJI_ENCODING = "shift-jis"
    static let HANZI_ENCODING = "gb2312"
    
    static let MICRO_VERSIONS = [VERSION_M1, VERSION_M2, VERSION_M3, VERSION_M4]
    
    static let ALPHANUMERIC_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
}

// MARK: - Core Data Structures
struct Segment {
    let bits: [UInt8]
    let charCount: Int
    let mode: Int
    let encoding: String?
}

struct Code {
    let matrix: [[UInt8]]
    let version: Int
    let error: Int
    let mask: Int
    let segments: [Segment]
}

// MARK: - Main Encoder Class
class QREncoder {
    // MARK: - Public Interface
    static func encode(content: String,
                      error: Int? = nil,
                      version: Int? = nil,
                      mode: Int? = nil,
                      mask: Int? = nil,
                      encoding: String? = nil,
                      eci: Bool = false,
                      micro: Bool? = nil,
                      boostError: Bool = true) throws -> Code {
        
        let normalizedVersion = try normalizeVersion(version)
        let normalizedError = try normalizeErrorLevel(error, acceptNone: true)
        let normalizedMode = try normalizeMode(mode)
        let normalizedMask = try normalizeMask(mask, isMicro: normalizedVersion < 1)
        
        // Validate parameters
        if !micro && micro != nil && QRConstants.MICRO_VERSIONS.contains(normalizedVersion) {
            throw QREncoderError.invalidVersion("Micro QR Code version provided but micro parameter is false")
        }
        
        if micro && normalizedVersion != nil && !QRConstants.MICRO_VERSIONS.contains(normalizedVersion) {
            throw QREncoderError.invalidVersion("Invalid Micro QR Code version")
        }
        
        // Prepare data segments
        let segments = try prepareData(content: content, mode: normalizedMode, encoding: encoding)
        
        // Find appropriate version if not specified
        let guessedVersion = try findVersion(segments: segments,
                                           error: normalizedError,
                                           eci: eci,
                                           micro: micro)
        
        let finalVersion = normalizedVersion ?? guessedVersion
        
        if guessedVersion > finalVersion {
            throw QREncoderError.dataOverflow("Data does not fit into version \(getVersionName(finalVersion))")
        }
        
        // Set error level for non-M1 versions if not specified
        var finalError = normalizedError
        if finalError == nil && finalVersion != QRConstants.VERSION_M1 {
            finalError = QRConstants.ERROR_LEVEL_L
        }
        
        // Encode the QR code
        return try encodeInternal(segments: segments,
                                error: finalError,
                                version: finalVersion,
                                mask: normalizedMask,
                                eci: eci,
                                boostError: boostError)
    }
    
    // MARK: - Private Helper Methods
    private static func normalizeVersion(_ version: Int?) throws -> Int {
        guard let version = version else { return 0 }
        
        if version < 1 || (version > 40 && !QRConstants.MICRO_VERSIONS.contains(version)) {
            throw QREncoderError.invalidVersion("Invalid version number")
        }
        
        return version
    }
    
    private static func normalizeErrorLevel(_ error: Int?, acceptNone: Bool) throws -> Int? {
        if error == nil && acceptNone {
            return nil
        }
        
        guard let error = error else {
            throw QREncoderError.invalidErrorLevel("Error level must be provided")
        }
        
        if error < 0 || error > 3 {
            throw QREncoderError.invalidErrorLevel("Invalid error correction level")
        }
        
        return error
    }
    
    private static func normalizeMode(_ mode: Int?) throws -> Int? {
        guard let mode = mode else { return nil }
        
        let validModes = [
            QRConstants.MODE_NUMERIC,
            QRConstants.MODE_ALPHANUMERIC,
            QRConstants.MODE_BYTE,
            QRConstants.MODE_KANJI,
            QRConstants.MODE_HANZI
        ]
        
        if !validModes.contains(mode) {
            throw QREncoderError.invalidMode("Invalid mode")
        }
        
        return mode
    }
    
    private static func normalizeMask(_ mask: Int?, isMicro: Bool) throws -> Int? {
        guard let mask = mask else { return nil }
        
        if isMicro {
            if mask < 0 || mask > 3 {
                throw QREncoderError.invalidMask("Invalid mask for Micro QR Code")
            }
        } else {
            if mask < 0 || mask > 7 {
                throw QREncoderError.invalidMask("Invalid mask")
            }
        }
        
        return mask
    }
    
    private static func getVersionName(_ version: Int) -> String {
        if version > 0 && version <= 40 {
            return String(version)
        }
        
        switch version {
        case QRConstants.VERSION_M1: return "M1"
        case QRConstants.VERSION_M2: return "M2"
        case QRConstants.VERSION_M3: return "M3"
        case QRConstants.VERSION_M4: return "M4"
        default: return "Unknown"
        }
    }
    
    // Implementation of other private methods would follow...
    // Including matrix generation, error correction, masking, etc.
}

// MARK: - Buffer Class
class Buffer {
    private var data: [UInt8]
    
    init() {
        data = []
    }
    
    func append(_ bits: [UInt8]) {
        data.append(contentsOf: bits)
    }
    
    func appendBits(_ value: Int, length: Int) {
        for i in stride(from: length - 1, through: 0, by: -1) {
            data.append(UInt8((value >> i) & 1))
        }
    }
    
    func getBits() -> [UInt8] {
        return data
    }
    
    func toInts() -> [Int] {
        var result: [Int] = []
        for i in stride(from: 0, to: data.count, by: 8) {
            let end = min(i + 8, data.count)
            let byte = data[i..<end]
            let bits = byte.map { String($0) }.joined()
            result.append(Int(bits, radix: 2) ?? 0)
        }
        return result
    }
    
    var count: Int {
        return data.count
    }
}

// MARK: - Matrix Generation
extension QREncoder {
    // MARK: - Matrix Creation
    static func makeMatrix(width: Int, height: Int, reserveRegions: Bool = true, addTiming: Bool = true) -> [[UInt8]] {
        let isSquare = width == height
        let isMicro = isSquare && width < 21
        
        // Initialize matrix with 0x2 (illegal value)
        var matrix = Array(repeating: Array(repeating: UInt8(2), count: width), count: height)
        
        if reserveRegions {
            // Reserve version pattern areas for QR Codes version 7 and larger
            if isSquare && width > 41 {
                for i in 0..<6 {
                    // Upper right
                    matrix[i][width - 11] = 0
                    matrix[i][width - 10] = 0
                    matrix[i][width - 9] = 0
                    
                    // Lower left
                    matrix[height - 11][i] = 0
                    matrix[height - 10][i] = 0
                    matrix[height - 9][i] = 0
                }
            }
            
            // Reserve format pattern areas
            for i in 0..<9 {
                // Upper left
                matrix[i][8] = 0
                // Upper bottom
                matrix[8][i] = 0
                
                if !isMicro {
                    // Bottom left
                    matrix[height - i - 1][8] = 0
                    // Upper right
                    matrix[8][width - i - 1] = 0
                }
            }
        }
        
        if addTiming {
            addTimingPattern(to: &matrix, isMicro: isMicro)
        }
        
        return matrix
    }
    
    // MARK: - Finder Patterns
    static func addFinderPatterns(to matrix: inout [[UInt8]], width: Int, height: Int) {
        let finderPattern: [[UInt8]] = [
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 0, 0, 0, 0, 1, 0],
            [0, 1, 0, 1, 1, 1, 0, 1, 0],
            [0, 1, 0, 1, 1, 1, 0, 1, 0],
            [0, 1, 0, 1, 1, 1, 0, 1, 0],
            [0, 1, 0, 0, 0, 0, 0, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0]
        ]
        
        let isSquare = width == height
        let corners: [(x: Int, y: Int)] = isSquare && width < 21
            ? [(0, 0)]  // Micro QR has only one finder pattern
            : [(0, 0), (0, height - 8), (width - 8, 0)]  // Regular QR has three finder patterns
        
        for (x, y) in corners {
            let xOffset = x == 0 ? 1 : 0
            let yOffset = y == 0 ? 1 : 0
            
            for i in 0..<8 {
                for j in 0..<8 {
                    matrix[y + i][x + j] = finderPattern[i + xOffset][j + yOffset]
                }
            }
        }
    }
    
    // MARK: - Timing Pattern
    static func addTimingPattern(to matrix: inout [[UInt8]], isMicro: Bool) {
        let (start, end) = isMicro ? (0, matrix.count) : (6, matrix.count - 8)
        var bit: UInt8 = 1
        
        for i in 8..<end {
            matrix[i][start] = bit
            matrix[start][i] = bit
            bit ^= 1
        }
    }
    
    // MARK: - Alignment Patterns
    static func addAlignmentPatterns(to matrix: inout [[UInt8]], width: Int, height: Int) {
        let isSquare = width == height
        let version = (width - 17) / 4  // Calculate version from matrix size
        
        // QR Codes version < 2 don't have alignment patterns
        guard isSquare && version >= 2 else { return }
        
        let pattern: [UInt8] = [
            1, 1, 1, 1, 1,
            1, 0, 0, 0, 1,
            1, 0, 1, 0, 1,
            1, 0, 0, 0, 1,
            1, 1, 1, 1, 1
        ]
        
        // Get alignment pattern positions based on version
        let positions = getAlignmentPatternPositions(version: version)
        let minPos = positions.first ?? 0
        let maxPos = positions.last ?? 0
        
        // Skip positions that would overlap with finder patterns
        let finderPositions = Set([
            (minPos, minPos),
            (minPos, maxPos),
            (maxPos, minPos)
        ])
        
        for x in positions {
            for y in positions {
                guard !finderPositions.contains((x, y)) else { continue }
                
                // Add alignment pattern centered at (x, y)
                let xStart = x - 2
                let yStart = y - 2
                
                for i in 0..<5 {
                    for j in 0..<5 {
                        matrix[yStart + i][xStart + j] = pattern[i * 5 + j]
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private static func getAlignmentPatternPositions(version: Int) -> [Int] {
        // This is a simplified version. In a complete implementation,
        // this would return the actual alignment pattern positions for each version
        guard version >= 2 && version <= 40 else { return [] }
        
        if version == 2 {
            return [6, 18]
        }
        
        // For versions > 2, calculate positions based on the QR code specification
        var positions: [Int] = []
        let step = version <= 6 ? 28 : (version <= 22 ? 26 : 28)
        let numAlign = (version / 7) + 2
        
        let start = 6
        let end = version * 4 + 10
        
        if numAlign == 2 {
            positions = [start, end]
        } else {
            let delta = (end - start) / (numAlign - 1)
            positions = (0..<numAlign).map { start + $0 * delta }
        }
        
        return positions
    }
    
    // MARK: - Matrix Size Calculation
    static func calculateMatrixSize(version: Int) -> Int {
        return version > 0 ? version * 4 + 17 : (version + 4) * 2 + 9
    }
    
    // MARK: - Matrix Validation
    static func isEncodingRegion(matrix: [[UInt8]], row: Int, col: Int) -> Bool {
        return matrix[row][col] > 0x1
    }
}

// MARK: - Matrix Utilities
extension Array where Element == [UInt8] {
    func copy() -> [[UInt8]] {
        return self.map { $0 }
    }
    
    mutating func setRegion(_ pattern: [[UInt8]], atRow row: Int, column: Int) {
        for (i, patternRow) in pattern.enumerated() {
            for (j, value) in patternRow.enumerated() {
                self[row + i][column + j] = value
            }
        }
    }
}
