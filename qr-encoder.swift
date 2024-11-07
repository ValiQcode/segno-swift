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

// MARK: - Data Preparation and Encoding
extension QREncoder {
    // MARK: - Data Preparation
    static func prepareData(content: String, mode: Int?, encoding: String?) throws -> [Segment] {
        let segments = SegmentCollection()
        
        if let mode = mode {
            try segments.addSegment(makeSegment(content: content, mode: mode, encoding: encoding))
        } else {
            // Auto-detect mode if not specified
            let data = content.data(using: .utf8) ?? Data()
            let detectedMode = findMode(data: data)
            try segments.addSegment(makeSegment(content: content, mode: detectedMode, encoding: encoding))
        }
        
        return segments.segments
    }
    
    // MARK: - Mode Detection
    static func findMode(data: Data) -> Int {
        if isNumeric(data) {
            return QRConstants.MODE_NUMERIC
        }
        if isAlphanumeric(data) {
            return QRConstants.MODE_ALPHANUMERIC
        }
        if isKanji(data) {
            return QRConstants.MODE_KANJI
        }
        return QRConstants.MODE_BYTE
    }
    
    // MARK: - Mode Checking
    private static func isNumeric(_ data: Data) -> Bool {
        let numbers = Set("0123456789".utf8)
        return data.allSatisfy { numbers.contains($0) }
    }
    
    private static func isAlphanumeric(_ data: Data) -> Bool {
        let validChars = Set(QRConstants.ALPHANUMERIC_CHARS.utf8)
        return data.allSatisfy { validChars.contains($0) }
    }
    
    private static func isKanji(_ data: Data) -> Bool {
        guard data.count % 2 == 0 else { return false }
        
        var isValid = true
        data.withUnsafeBytes { ptr in
            let shorts = ptr.bindMemory(to: UInt16.self)
            for i in 0..<shorts.count {
                let code = shorts[i].bigEndian
                if !((0x8140...0x9FFC).contains(code) || (0xE040...0xEBBF).contains(code)) {
                    isValid = false
                    break
                }
            }
        }
        return isValid
    }
    
    // MARK: - Segment Creation
    static func makeSegment(content: String, mode: Int, encoding: String?) throws -> Segment {
        let buffer = Buffer()
        var charCount = 0
        
        switch mode {
        case QRConstants.MODE_NUMERIC:
            try encodeNumeric(content, into: buffer)
            charCount = content.count
            
        case QRConstants.MODE_ALPHANUMERIC:
            try encodeAlphanumeric(content, into: buffer)
            charCount = content.count
            
        case QRConstants.MODE_BYTE:
            let (data, count, finalEncoding) = try dataToBytes(content, encoding: encoding)
            try encodeByte(data, into: buffer)
            charCount = count
            return Segment(bits: buffer.getBits(), charCount: charCount, mode: mode, encoding: finalEncoding)
            
        case QRConstants.MODE_KANJI:
            try encodeKanji(content, into: buffer)
            charCount = content.count / 2
            
        default:
            throw QREncoderError.invalidMode("Unsupported mode")
        }
        
        return Segment(bits: buffer.getBits(), charCount: charCount, mode: mode, encoding: nil)
    }
    
    // MARK: - Mode-specific Encoding
    private static func encodeNumeric(_ content: String, into buffer: Buffer) throws {
        // Process groups of 3 digits
        var remaining = content
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(3))
            remaining = String(remaining.dropFirst(min(3, remaining.count)))
            
            guard let value = Int(chunk) else {
                throw QREncoderError.invalidMode("Invalid numeric data")
            }
            
            // Convert to binary with appropriate bit length
            let bitLength = chunk.count * 3 + 1
            buffer.appendBits(value, length: bitLength)
        }
    }
    
    private static func encodeAlphanumeric(_ content: String, into buffer: Buffer) throws {
        var remaining = content
        while !remaining.isEmpty {
            let chunk = remaining.prefix(2)
            remaining = String(remaining.dropFirst(min(2, remaining.count)))
            
            if chunk.count == 2 {
                // Process pairs of characters
                let first = try getAlphanumericValue(chunk.first!)
                let second = try getAlphanumericValue(chunk.last!)
                buffer.appendBits(first * 45 + second, length: 11)
            } else {
                // Process single character
                let value = try getAlphanumericValue(chunk.first!)
                buffer.appendBits(value, length: 6)
            }
        }
    }
    
    private static func encodeByte(_ data: Data, into buffer: Buffer) throws {
        for byte in data {
            buffer.appendBits(Int(byte), length: 8)
        }
    }
    
    private static func encodeKanji(_ content: String, into buffer: Buffer) throws {
        guard let data = content.data(using: .shiftJIS) else {
            throw QREncoderError.invalidMode("Invalid Kanji data")
        }
        
        var i = 0
        while i < data.count {
            let byte1 = Int(data[i])
            let byte2 = Int(data[i + 1])
            let code = (byte1 << 8) | byte2
            
            var diff: Int
            if (0x8140...0x9FFC).contains(code) {
                diff = code - 0x8140
            } else if (0xE040...0xEBBF).contains(code) {
                diff = code - 0xC140
            } else {
                throw QREncoderError.invalidMode("Invalid Kanji byte sequence")
            }
            
            let value = ((diff >> 8) * 0xC0) + (diff & 0xFF)
            buffer.appendBits(value, length: 13)
            i += 2
        }
    }
    
    // MARK: - Helper Methods
    private static func getAlphanumericValue(_ char: Character) throws -> Int {
        guard let index = QRConstants.ALPHANUMERIC_CHARS.firstIndex(of: char) else {
            throw QREncoderError.invalidMode("Invalid alphanumeric character: \(char)")
        }
        return QRConstants.ALPHANUMERIC_CHARS.distance(from: QRConstants.ALPHANUMERIC_CHARS.startIndex, to: index)
    }
    
    private static func dataToBytes(_ data: String, encoding: String?) throws -> (Data, Int, String) {
        // Try the specified encoding first
        if let encoding = encoding,
           let encodedData = data.data(using: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(encoding as CFString)))) {
            return (encodedData, encodedData.count, encoding)
        }
        
        // Try default encodings in order
        let encodings: [(String, String.Encoding)] = [
            (QRConstants.DEFAULT_BYTE_ENCODING, .isoLatin1),
            (QRConstants.KANJI_ENCODING, .shiftJIS),
            ("utf-8", .utf8)
        ]
        
        for (encodingName, encoding) in encodings {
            if let encodedData = data.data(using: encoding) {
                return (encodedData, encodedData.count, encodingName)
            }
        }
        
        throw QREncoderError.invalidMode("Unable to encode data with any supported encoding")
    }
}

// MARK: - Segment Collection
class SegmentCollection {
    private(set) var segments: [Segment] = []
    private(set) var bitLength: Int = 0
    private(set) var modes: [Int] = []
    
    func addSegment(_ segment: Segment) {
        if let lastSegment = segments.last,
           lastSegment.mode == segment.mode,
           lastSegment.encoding == segment.encoding {
            // Merge with previous segment
            var mergedBits = lastSegment.bits
            mergedBits.append(contentsOf: segment.bits)
            let mergedSegment = Segment(
                bits: mergedBits,
                charCount: lastSegment.charCount + segment.charCount,
                mode: segment.mode,
                encoding: segment.encoding
            )
            segments.removeLast()
            modes.removeLast()
            bitLength -= lastSegment.bits.count
            segments.append(mergedSegment)
        } else {
            segments.append(segment)
        }
        
        bitLength += segment.bits.count
        modes.append(segment.mode)
    }
}

// MARK: - Error Correction Types
extension QREncoder {
    struct ECInfo {
        let numTotal: Int
        let numData: Int
        let numBlocks: Int
    }
    
    struct Block {
        var data: [UInt8]
        var error: [UInt8]
    }
    
    // MARK: - Galois Field Operations
    private struct GaloisField {
        // Galois field log table for error correction calculations
        static let log: [Int] = [
            0xFF, 0x00, 0x01, 0x19, 0x02, 0x32, 0x1A, 0xC6, 0x03, 0xDF, 0x33, 0xEE, 0x1B, 0x68, 0xC7, 0x4B,
            0x04, 0x64, 0xE0, 0x0E, 0x34, 0x8D, 0xEF, 0x81, 0x1C, 0xC1, 0x69, 0xF8, 0xC8, 0x08, 0x4C, 0x71
            // ... Add complete log table
        ]
        
        // Galois field antilog (exponential) table
        static let exp: [Int] = [
            0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1D, 0x3A, 0x74, 0xE8, 0xCD, 0x87, 0x13, 0x26,
            0x4C, 0x98, 0x2D, 0x5A, 0xB4, 0x75, 0xEA, 0xC9, 0x8F, 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0
            // ... Add complete exp table
        ]
        
        // Generator polynomials for different error correction levels
        static let generatorPolynomials: [Int: [Int]] = [
            7:  [0, 87, 229, 146, 149, 238, 102, 21],
            10: [0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45],
            13: [0, 74, 152, 176, 100, 86, 100, 106, 104, 130, 218, 206, 140, 78],
            15: [0, 8, 183, 61, 91, 202, 37, 51, 58, 58, 237, 140, 124, 5, 99, 105],
            // ... Add other generator polynomials
        ]
    }
    
    // MARK: - Error Correction Generation
    static func makeFinalMessage(version: Int, error: Int, buffer: Buffer) throws -> Buffer {
        let codewords = buffer.toInts()
        let ecInfo = try getErrorCorrectionInfo(version: version, errorLevel: error)
        let (dataBlocks, errorBlocks) = try makeBlocks(ecInfo: ecInfo, codewords: codewords)
        
        // Create final message buffer
        let result = Buffer()
        
        // Interleave data blocks
        let maxDataLength = dataBlocks.map { $0.data.count }.max() ?? 0
        for i in 0..<maxDataLength {
            for block in dataBlocks where i < block.data.count {
                result.appendBits(Int(block.data[i]), length: 8)
            }
        }
        
        // Special handling for M1 and M3 versions (4-bit final codeword)
        if version == QRConstants.VERSION_M1 || version == QRConstants.VERSION_M3 {
            if let lastBlock = dataBlocks.last {
                result.appendBits(Int(lastBlock.data.last!) >> 4, length: 4)
            }
        }
        
        // Interleave error correction blocks
        let maxErrorLength = errorBlocks.map { $0.count }.max() ?? 0
        for i in 0..<maxErrorLength {
            for block in errorBlocks where i < block.count {
                result.appendBits(Int(block[i]), length: 8)
            }
        }
        
        // Add remainder bits if necessary
        let remainder: Int
        switch version {
        case 2...6:
            remainder = 7
        case 14...20, 28...34:
            remainder = 3
        case 21...27:
            remainder = 4
        default:
            remainder = 0
        }
        
        result.extend(Array(repeating: UInt8(0), count: remainder))
        
        return result
    }
    
    // MARK: - Block Generation
    private static func makeBlocks(ecInfo: [ECInfo], codewords: [Int]) throws -> (data: [Block], error: [[UInt8]]) {
        var dataBlocks: [Block] = []
        var errorBlocks: [[UInt8]] = []
        
        var codewordIndex = 0
        
        for info in ecInfo {
            let numErrorWords = info.numTotal - info.numData
            let generator = try getGeneratorPolynomial(numErrorWords: numErrorWords)
            
            for _ in 0..<info.numBlocks {
                // Extract data block
                let dataBlock = Array(codewords[codewordIndex..<(codewordIndex + info.numData)])
                    .map { UInt8($0) }
                codewordIndex += info.numData
                
                // Calculate error correction words
                let errorBlock = calculateErrorCorrection(
                    data: dataBlock,
                    generator: generator,
                    numErrorWords: numErrorWords
                )
                
                dataBlocks.append(Block(data: dataBlock, error: errorBlock))
                errorBlocks.append(errorBlock)
            }
        }
        
        return (dataBlocks, errorBlocks)
    }
    
    // MARK: - Error Correction Calculation
    private static func calculateErrorCorrection(data: [UInt8], generator: [Int], numErrorWords: Int) -> [UInt8] {
        var errorBlock = Array(data)
        errorBlock.append(contentsOf: Array(repeating: 0, count: numErrorWords))
        
        let dataLength = data.count
        
        // Polynomial division
        for i in 0..<dataLength {
            let coef = errorBlock[i]
            if coef != 0 {
                let logCoef = GaloisField.log[Int(coef)]
                
                for j in 0..<numErrorWords {
                    errorBlock[i + j + 1] ^= UInt8(
                        GaloisField.exp[(logCoef + generator[j]) % 255]
                    )
                }
            }
        }
        
        // Return only the error correction part
        return Array(errorBlock[dataLength...])
    }
    
    // MARK: - Helper Methods
    private static func getErrorCorrectionInfo(version: Int, errorLevel: Int) throws -> [ECInfo] {
        // This would contain the actual EC info lookup based on version and error level
        // For demonstration, returning a simple example
        switch (version, errorLevel) {
        case (1, QRConstants.ERROR_LEVEL_L):
            return [ECInfo(numTotal: 26, numData: 19, numBlocks: 1)]
        case (1, QRConstants.ERROR_LEVEL_M):
            return [ECInfo(numTotal: 26, numData: 16, numBlocks: 1)]
        // ... Add other version/error level combinations
        default:
            throw QREncoderError.invalidVersion("Unsupported version/error level combination")
        }
    }
    
    private static func getGeneratorPolynomial(numErrorWords: Int) throws -> [Int] {
        guard let polynomial = GaloisField.generatorPolynomials[numErrorWords] else {
            throw QREncoderError.invalidVersion("Unsupported error correction length")
        }
        return polynomial
    }
}

// MARK: - Buffer Extensions
extension Buffer {
    mutating func extend(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }
    
    func subBuffer(from: Int, length: Int) -> Buffer {
        let newBuffer = Buffer()
        newBuffer.extend(Array(data[from..<from + length]))
        return newBuffer
    }
}

// MARK: - Data Masking
extension QREncoder {
    // MARK: - Mask Pattern Application
    static func findAndApplyBestMask(matrix: [[UInt8]], width: Int, height: Int, proposedMask: Int?) throws -> (mask: Int, matrix: [[UInt8]]) {
        let isMicro = width == height && width < 21
        
        // Create matrix to check encoding regions
        var functionMatrix = makeMatrix(width: width, height: height)
        addFinderPatterns(to: &functionMatrix, width: width, height: height)
        addAlignmentPatterns(to: &functionMatrix, width: width, height: height)
        
        if !isMicro {
            functionMatrix[functionMatrix.count - 8][8] = 1
        }
        
        // Helper function to check if a position belongs to the encoding region
        let isEncodingRegion = { (row: Int, col: Int) -> Bool in
            functionMatrix[row][col] > 0x1
        }
        
        // If a mask is proposed, apply it and return
        if let proposedMask = proposedMask {
            var maskedMatrix = matrix
            applyMask(to: &maskedMatrix, mask: proposedMask, isMicro: isMicro, isEncodingRegion: isEncodingRegion)
            return (proposedMask, maskedMatrix)
        }
        
        // Try all masks and find the best one
        let masks = isMicro ? 4 : 8
        var bestScore = isMicro ? -1 : Int.max
        var bestMask = 0
        var bestMatrix: [[UInt8]]?
        
        let evaluator = isMicro ? evaluateMicroMask : evaluateMask
        let isBetter: (Int, Int) -> Bool = isMicro ? (>) : (<)
        
        for maskPattern in 0..<masks {
            var testMatrix = matrix
            applyMask(to: &testMatrix, mask: maskPattern, isMicro: isMicro, isEncodingRegion: isEncodingRegion)
            let score = evaluator(testMatrix, width, height)
            
            if bestMatrix == nil || isBetter(score, bestScore) {
                bestScore = score
                bestMask = maskPattern
                bestMatrix = testMatrix
            }
        }
        
        guard let finalMatrix = bestMatrix else {
            throw QREncoderError.invalidMask("Failed to find valid mask pattern")
        }
        
        return (bestMask, finalMatrix)
    }
    
    // MARK: - Mask Pattern Application
    private static func applyMask(to matrix: inout [[UInt8]],
                                mask: Int,
                                isMicro: Bool,
                                isEncodingRegion: (Int, Int) -> Bool) {
        let maskFunction = getMaskFunction(pattern: mask, isMicro: isMicro)
        
        for i in 0..<matrix.count {
            for j in 0..<matrix[i].count {
                if isEncodingRegion(i, j) {
                    matrix[i][j] ^= (maskFunction(i, j) ? 1 : 0)
                }
            }
        }
    }
    
    // MARK: - Mask Pattern Functions
    private static func getMaskFunction(pattern: Int, isMicro: Bool) -> (Int, Int) -> Bool {
        if isMicro {
            return getMicroMaskFunction(pattern: pattern)
        }
        return getQRMaskFunction(pattern: pattern)
    }
    
    private static func getQRMaskFunction(pattern: Int) -> (Int, Int) -> Bool {
        switch pattern {
        case 0:
            return { (i, j) in (i + j) % 2 == 0 }
        case 1:
            return { (i, _) in i % 2 == 0 }
        case 2:
            return { (_, j) in j % 3 == 0 }
        case 3:
            return { (i, j) in (i + j) % 3 == 0 }
        case 4:
            return { (i, j) in (i / 2 + j / 3) % 2 == 0 }
        case 5:
            return { (i, j) in
                let temp = i * j
                return (temp % 2 + temp % 3) == 0
            }
        case 6:
            return { (i, j) in
                let temp = i * j
                return ((temp % 2 + temp % 3) % 2) == 0
            }
        case 7:
            return { (i, j) in
                return ((i + j) % 2 + (i * j) % 3) % 2 == 0
            }
        default:
            return { _, _ in false }
        }
    }
    
    private static func getMicroMaskFunction(pattern: Int) -> (Int, Int) -> Bool {
        switch pattern {
        case 0:
            return { (i, _) in i % 2 == 0 }
        case 1:
            return { (i, j) in (i / 2 + j / 3) % 2 == 0 }
        case 2:
            return { (i, j) in
                let temp = i * j
                return ((temp % 2 + temp % 3) % 2) == 0
            }
        case 3:
            return { (i, j) in
                return ((i + j) % 2 + (i * j) % 3) % 2 == 0
            }
        default:
            return { _, _ in false }
        }
    }
    
    // MARK: - Mask Evaluation
    private static func evaluateMask(_ matrix: [[UInt8]], _ width: Int, _ height: Int) -> Int {
        // Calculate all penalty scores
        let n1 = calculateN1PenaltyScore(matrix)
        let n2 = calculateN2PenaltyScore(matrix)
        let n3 = calculateN3PenaltyScore(matrix)
        let n4 = calculateN4PenaltyScore(matrix)
        
        return n1 + n2 + n3 + n4
    }
    
    private static func evaluateMicroMask(_ matrix: [[UInt8]], _ width: Int, _ height: Int) -> Int {
        var sum1 = 0
        var sum2 = 0
        
        // Calculate sums for the last column and row (excluding first element)
        for i in 1..<height {
            sum1 += Int(matrix[i][width - 1])
        }
        
        for j in 1..<width {
            sum2 += Int(matrix[height - 1][j])
        }
        
        return sum1 <= sum2 ? (sum1 * 16 + sum2) : (sum2 * 16 + sum1)
    }
    
    // MARK: - Penalty Score Calculations
    private static func calculateN1PenaltyScore(_ matrix: [[UInt8]]) -> Int {
        var score = 0
        let size = matrix.count
        
        // Check horizontal runs
        for row in 0..<size {
            var runLength = 1
            var prevBit = matrix[row][0]
            
            for col in 1..<size {
                let bit = matrix[row][col]
                if bit == prevBit {
                    runLength += 1
                } else {
                    if runLength >= 5 {
                        score += runLength - 2
                    }
                    runLength = 1
                    prevBit = bit
                }
            }
            if runLength >= 5 {
                score += runLength - 2
            }
        }
        
        // Check vertical runs
        for col in 0..<size {
            var runLength = 1
            var prevBit = matrix[0][col]
            
            for row in 1..<size {
                let bit = matrix[row][col]
                if bit == prevBit {
                    runLength += 1
                } else {
                    if runLength >= 5 {
                        score += runLength - 2
                    }
                    runLength = 1
                    prevBit = bit
                }
            }
            if runLength >= 5 {
                score += runLength - 2
            }
        }
        
        return score
    }
    
    private static func calculateN2PenaltyScore(_ matrix: [[UInt8]]) -> Int {
        var score = 0
        let size = matrix.count
        
        for row in 0..<(size - 1) {
            for col in 0..<(size - 1) {
                let bit = matrix[row][col]
                if bit == matrix[row][col + 1] &&
                    bit == matrix[row + 1][col] &&
                    bit == matrix[row + 1][col + 1] {
                    score += 3
                }
            }
        }
        
        return score
    }
    
    private static func calculateN3PenaltyScore(_ matrix: [[UInt8]]) -> Int {
        var score = 0
        let size = matrix.count
        let pattern1: [UInt8] = [1, 0, 1, 1, 1, 0, 1]
        
        // Check horizontal patterns
        for row in 0..<size {
            let rowArray = Array(matrix[row])
            if let _ = findPattern(pattern1, in: rowArray) {
                score += 40
            }
        }
        
        // Check vertical patterns
        for col in 0..<size {
            let colArray = (0..<size).map { matrix[$0][col] }
            if let _ = findPattern(pattern1, in: colArray) {
                score += 40
            }
        }
        
        return score
    }
    
    private static func calculateN4PenaltyScore(_ matrix: [[UInt8]]) -> Int {
        let size = matrix.count
        var darkCount = 0
        let totalCount = size * size
        
        for row in matrix {
            darkCount += row.reduce(0) { $0 + Int($1) }
        }
        
        let percentage = Double(darkCount) * 100 / Double(totalCount)
        let previous20 = Int((percentage + 5) / 10) * 10 - 50
        let next20 = Int(previous20 + 10)
        
        return min(abs(previous20), abs(next20)) * 10
    }
    
    // MARK: - Helper Methods
    private static func findPattern(_ pattern: [UInt8], in array: [UInt8]) -> Int? {
        let patternLength = pattern.count
        for i in 0...(array.count - patternLength) {
            var matches = true
            for j in 0..<patternLength {
                if array[i + j] != pattern[j] {
                    matches = false
                    break
                }
            }
            if matches {
                return i
            }
        }
        return nil
    }
}

// MARK: - Format Information
extension QREncoder {
    // Format information bit masks for regular QR codes
    private static let FORMAT_INFO_MASK = 0x5412
    
    // Pre-calculated format information values
    private static let FORMAT_INFO: [Int: Int] = [
        // Format info for regular QR codes
        // Index: mask pattern + (error level << 3)
        0x00: 0x77C4,  // L,0
        0x01: 0x72F3,  // L,1
        0x02: 0x7DAA,  // L,2
        0x03: 0x789D,  // L,3
        0x04: 0x662F,  // L,4
        0x05: 0x6318,  // L,5
        0x06: 0x6C41,  // L,6
        0x07: 0x6976,  // L,7
        0x08: 0x5412,  // M,0
        0x09: 0x5125,  // M,1
        0x0A: 0x5E7C,  // M,2
        0x0B: 0x5B4B,  // M,3
        0x0C: 0x45F9,  // M,4
        0x0D: 0x40CE,  // M,5
        0x0E: 0x4F97,  // M,6
        0x0F: 0x4AA0,  // M,7
        0x10: 0x355F,  // Q,0
        0x11: 0x3068,  // Q,1
        0x12: 0x3F31,  // Q,2
        0x13: 0x3A06,  // Q,3
        0x14: 0x24B4,  // Q,4
        0x15: 0x2183,  // Q,5
        0x16: 0x2EDA,  // Q,6
        0x17: 0x2BED,  // Q,7
        0x18: 0x1689,  // H,0
        0x19: 0x13BE,  // H,1
        0x1A: 0x1CE7,  // H,2
        0x1B: 0x19D0,  // H,3
        0x1C: 0x0762,  // H,4
        0x1D: 0x0255,  // H,5
        0x1E: 0x0D0C,  // H,6
        0x1F: 0x083B,  // H,7
    ]
    
    // Pre-calculated format information for Micro QR codes
    private static let FORMAT_INFO_MICRO: [Int: Int] = [
        // Index: mask pattern + (error level << 2)
        0x00: 0x4445,  // M1, mask 0
        0x01: 0x4172,  // M1, mask 1
        0x02: 0x4E2B,  // M1, mask 2
        0x03: 0x4B1C,  // M1, mask 3
        0x04: 0x55AE,  // M2-L, mask 0
        0x05: 0x5099,  // M2-L, mask 1
        0x06: 0x5FC0,  // M2-L, mask 2
        0x07: 0x5AF7,  // M2-L, mask 3
        0x08: 0x6793,  // M2-M, mask 0
        0x09: 0x62A4,  // M2-M, mask 1
        0x0A: 0x6DFD,  // M2-M, mask 2
        0x0B: 0x68CA,  // M2-M, mask 3
        0x0C: 0x7678,  // M3-L, mask 0
        0x0D: 0x734F,  // M3-L, mask 1
        0x0E: 0x7C16,  // M3-L, mask 2
        0x0F: 0x7921,  // M3-L, mask 3
        0x10: 0x06DE,  // M3-M, mask 0
        0x11: 0x03E9,  // M3-M, mask 1
        0x12: 0x0CB0,  // M3-M, mask 2
        0x13: 0x0987,  // M3-M, mask 3
        0x14: 0x1735,  // M4-L, mask 0
        0x15: 0x1202,  // M4-L, mask 1
        0x16: 0x1D5B,  // M4-L, mask 2
        0x17: 0x186C,  // M4-L, mask 3
        0x18: 0x2508,  // M4-M, mask 0
        0x19: 0x203F,  // M4-M, mask 1
        0x1A: 0x2F66,  // M4-M, mask 2
        0x1B: 0x2A51,  // M4-M, mask 3
        0x1C: 0x34E3,  // M4-Q, mask 0
        0x1D: 0x31D4,  // M4-Q, mask 1
        0x1E: 0x3E8D,  // M4-Q, mask 2
        0x1F: 0x3BBA,  // M4-Q, mask 3
    ]
    
    /// Maps error correction levels to their micro QR format info values
    private static let ERROR_LEVEL_TO_MICRO_MAPPING: [Int: [Int: Int]] = [
        QRConstants.VERSION_M1: [0: 0],
        QRConstants.VERSION_M2: [QRConstants.ERROR_LEVEL_L: 1, QRConstants.ERROR_LEVEL_M: 2],
        QRConstants.VERSION_M3: [QRConstants.ERROR_LEVEL_L: 3, QRConstants.ERROR_LEVEL_M: 4],
        QRConstants.VERSION_M4: [QRConstants.ERROR_LEVEL_L: 5, QRConstants.ERROR_LEVEL_M: 6, QRConstants.ERROR_LEVEL_Q: 7],
    ]
    
    /// Calculate format information bits
    static func calculateFormatInfo(version: Int, errorLevel: Int, maskPattern: Int) throws -> Int {
        let isMicro = version < 1
        
        if isMicro {
            guard let versionMap = ERROR_LEVEL_TO_MICRO_MAPPING[version],
                  let errorMapping = versionMap[errorLevel] else {
                throw QREncoderError.invalidVersion("Invalid micro QR version/error level combination")
            }
            
            let formatIndex = maskPattern + (errorMapping << 2)
            guard let formatInfo = FORMAT_INFO_MICRO[formatIndex] else {
                throw QREncoderError.invalidMask("Invalid mask pattern for Micro QR")
            }
            return formatInfo
        } else {
            var fmt = maskPattern
            switch errorLevel {
            case QRConstants.ERROR_LEVEL_L:
                fmt += 0x08
            case QRConstants.ERROR_LEVEL_H:
                fmt += 0x10
            case QRConstants.ERROR_LEVEL_Q:
                fmt += 0x18
            case QRConstants.ERROR_LEVEL_M:
                break
            default:
                throw QREncoderError.invalidErrorLevel("Invalid error correction level")
            }
            
            guard let formatInfo = FORMAT_INFO[fmt] else {
                throw QREncoderError.invalidMask("Invalid mask pattern")
            }
            return formatInfo
        }
    }
    
    /// Add format information to the QR code matrix
    static func addFormatInfo(to matrix: inout [[UInt8]],
                            version: Int,
                            errorLevel: Int,
                            maskPattern: Int) throws {
        let formatInfo = try calculateFormatInfo(version: version,
                                               errorLevel: errorLevel,
                                               maskPattern: maskPattern)
        
        let isMicro = version < 1
        let vOffset = isMicro ? 1 : 0
        let hOffset = vOffset
        
        // Place format info bits
        for i in 0..<8 {
            let vBit = UInt8((formatInfo >> i) & 1)
            let hBit = UInt8((formatInfo >> (14 - i)) & 1)
            
            // Handle timing pattern for regular QR codes
            let (vIndex, hIndex) = if i == 6 && !isMicro {
                (i + 1, 1) // Skip timing pattern
            } else {
                (i, 0)
            }
            
            // Vertical bit placement in upper left
            matrix[vIndex + vOffset][8] = vBit
            
            // Horizontal bit placement in upper left
            matrix[8][hIndex + hOffset] = hBit
            
            // For regular QR codes, add redundant format info
            if !isMicro {
                // Horizontal placement in upper right
                matrix[8][matrix.count - 1 - i] = vBit
                
                // Vertical placement in bottom left
                matrix[matrix.count - 1 - i][8] = hBit
            }
        }
        
        // For regular QR codes, add the dark module
        if !isMicro {
            matrix[matrix.count - 8][8] = 1
        }
    }
    
    /// Add version information to QR code matrix (only for versions 7 and up)
    static func addVersionInfo(to matrix: inout [[UInt8]], version: Int) throws {
        guard version >= 7 else { return }
        
        // Version information lookup table
        let VERSION_INFO: [Int: Int] = [
            7: 0x07C94,
            8: 0x085BC,
            9: 0x09A99,
            10: 0x0A4D3,
            11: 0x0BBF6,
            12: 0x0C762,
            13: 0x0D847,
            14: 0x0E60D,
            15: 0x0F928,
            16: 0x10B78,
            17: 0x1145D,
            18: 0x12A17,
            19: 0x13532,
            20: 0x149A6,
            21: 0x15683,
            22: 0x168C9,
            23: 0x177EC,
            24: 0x18EC4,
            25: 0x191E1,
            26: 0x1AFAB,
            27: 0x1B08E,
            28: 0x1CC1A,
            29: 0x1D33F,
            30: 0x1ED75,
            31: 0x1F250,
            32: 0x209D5,
            33: 0x216F0,
            34: 0x228BA,
            35: 0x2379F,
            36: 0x24B0B,
            37: 0x2542E,
            38: 0x26A64,
            39: 0x27541,
            40: 0x28C69
        ]
        
        guard let versionInfo = VERSION_INFO[version] else {
            throw QREncoderError.invalidVersion("Invalid version number")
        }
        
        // Place version information bits
        for i in 0..<18 {
            let bit = UInt8((versionInfo >> i) & 1)
            let row = i / 3
            let col = i % 3
            
            // Place in bottom-left corner
            matrix[matrix.count - 11 + col][row] = bit
            
            // Place in upper-right corner
            matrix[row][matrix.count - 11 + col] = bit
        }
    }
}

// MARK: - Format Information Utility Extensions
extension QREncoder {
    /// Get version name (e.g., "1" for version 1, "M1" for Micro QR version M1)
    static func getVersionName(_ version: Int) -> String {
        if version > 0 {
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
    
    /// Get error level name (L, M, Q, or H)
    static func getErrorLevelName(_ errorLevel: Int) -> String {
        switch errorLevel {
        case QRConstants.ERROR_LEVEL_L: return "L"
        case QRConstants.ERROR_LEVEL_M: return "M"
        case QRConstants.ERROR_LEVEL_Q: return "Q"
        case QRConstants.ERROR_LEVEL_H: return "H"
        default: return "Unknown"
        }
    }
}

// MARK: - QR Code Final Assembly
extension QREncoder {
    /// Main encode function to create the final QR code
    static func encodeInternal(segments: [Segment],
                             error: Int?,
                             version: Int,
                             mask: Int?,
                             eci: Bool,
                             boostError: Bool,
                             structuredAppendInfo: StructuredAppendInfo? = nil) throws -> Code {
        
        let isMicro = version < 1
        let isStructuredAppend = structuredAppendInfo != nil
        
        // Step 1: Prepare data buffer
        let buffer = try prepareDataBuffer(
            segments: segments,
            version: version,
            error: error,
            eci: eci,
            structuredAppendInfo: structuredAppendInfo
        )
        
        // Step 2: Determine final error correction level
        let finalError = try determineFinalErrorLevel(
            version: version,
            error: error,
            segments: segments,
            eci: eci,
            boostError: boostError,
            isStructuredAppend: isStructuredAppend
        )
        
        // Step 3: Create final message with error correction
        let finalMessage = try makeFinalMessage(
            version: version,
            error: finalError,
            buffer: buffer
        )
        
        // Step 4: Create and initialize matrix
        let matrixSize = calculateMatrixSize(version: version)
        var matrix = makeMatrix(width: matrixSize, height: matrixSize)
        
        // Step 5: Add function patterns
        addFunctionPatterns(to: &matrix, version: version)
        
        // Step 6: Add codewords
        try addCodewords(to: &matrix, codewords: finalMessage, version: version)
        
        // Step 7: Find and apply best mask
        let (bestMask, maskedMatrix) = try findAndApplyBestMask(
            matrix: matrix,
            width: matrixSize,
            height: matrixSize,
            proposedMask: mask
        )
        
        // Step 8: Add format and version information
        var finalMatrix = maskedMatrix
        try addFormatInfo(
            to: &finalMatrix,
            version: version,
            errorLevel: finalError,
            maskPattern: bestMask
        )
        
        if version >= 7 {
            try addVersionInfo(to: &finalMatrix, version: version)
        }
        
        return Code(
            matrix: finalMatrix,
            version: version,
            error: finalError,
            mask: bestMask,
            segments: segments
        )
    }
    
    // MARK: - Helper Methods
    
    private static func prepareDataBuffer(segments: [Segment],
                                        version: Int,
                                        error: Int?,
                                        eci: Bool,
                                        structuredAppendInfo: StructuredAppendInfo?) throws -> Buffer {
        let buffer = Buffer()
        
        // Add structured append information if present
        if let saInfo = structuredAppendInfo {
            buffer.appendBits(QRConstants.MODE_STRUCTURED_APPEND, length: 4)
            buffer.appendBits(saInfo.symbolNumber, length: 4)
            buffer.appendBits(saInfo.totalSymbols, length: 4)
            buffer.appendBits(saInfo.parityData, length: 8)
        }
        
        // Add segments
        for segment in segments {
            try addSegmentToBuffer(
                segment,
                to: buffer,
                version: version,
                eci: eci
            )
        }
        
        // Add terminator and padding
        try addTerminatorAndPadding(
            to: buffer,
            version: version,
            error: error
        )
        
        return buffer
    }
    
    private static func addSegmentToBuffer(_ segment: Segment,
                                         to buffer: Buffer,
                                         version: Int,
                                         eci: Bool) throws {
        let isMicro = version < 1
        
        // Add ECI mode indicator and assignment number if needed
        if eci && segment.mode == QRConstants.MODE_BYTE &&
            segment.encoding != QRConstants.DEFAULT_BYTE_ENCODING {
            buffer.appendBits(QRConstants.MODE_ECI, length: 4)
            if let assignmentNumber = try? getECIAssignmentNumber(for: segment.encoding) {
                buffer.appendBits(assignmentNumber, length: 8)
            }
        }
        
        // Add mode indicator
        if version > QRConstants.VERSION_M1 {  // M1 has no mode indicator
            let modeIndicatorLength = isMicro ? version + 3 : 4
            let modeValue = isMicro ? getMicroModeValue(segment.mode) : segment.mode
            buffer.appendBits(modeValue, length: modeIndicatorLength)
        }
        
        // Add character count indicator
        let charCountLength = try getCharacterCountLength(
            mode: segment.mode,
            version: version
        )
        buffer.appendBits(segment.charCount, length: charCountLength)
        
        // Add data
        buffer.append(segment.bits)
    }
    
    private static func addTerminatorAndPadding(to buffer: Buffer,
                                              version: Int,
                                              error: Int?) throws {
        let capacity = try getSymbolCapacity(version: version, errorLevel: error)
        
        // Add terminator
        let terminator = try getTerminatorLength(version: version)
        let remainingBits = capacity - buffer.count
        let terminatorLength = min(remainingBits, terminator)
        buffer.extend(Array(repeating: 0, count: terminatorLength))
        
        // Add padding bits to meet codeword boundary
        if version != QRConstants.VERSION_M1 && version != QRConstants.VERSION_M3 {
            let paddingLength = 8 - (buffer.count % 8)
            if paddingLength < 8 {
                buffer.extend(Array(repeating: 0, count: paddingLength))
            }
        }
        
        // Add padding codewords if necessary
        var paddingBytes = capacity - buffer.count
        while paddingBytes >= 8 {
            buffer.appendBits(0xEC, length: 8)  // 236
            if paddingBytes >= 16 {
                buffer.appendBits(0x11, length: 8)  // 17
            }
            paddingBytes -= 16
        }
    }
    
    private static func addFunctionPatterns(to matrix: inout [[UInt8]], version: Int) {
        let size = matrix.count
        
        // Add finder patterns
        addFinderPatterns(to: &matrix, width: size, height: size)
        
        // Add alignment patterns for versions >= 2
        if version >= 2 {
            addAlignmentPatterns(to: &matrix, width: size, height: size)
        }
        
        // Add timing patterns
        let isMicro = version < 1
        addTimingPattern(to: &matrix, isMicro: isMicro)
    }
    
    private static func determineFinalErrorLevel(version: Int,
                                               error: Int?,
                                               segments: [Segment],
                                               eci: Bool,
                                               boostError: Bool,
                                               isStructuredAppend: Bool) throws -> Int {
        var finalError = error
        
        if version != QRConstants.VERSION_M1 && finalError == nil {
            finalError = QRConstants.ERROR_LEVEL_L
        }
        
        if boostError {
            finalError = try boostErrorLevel(
                version: version,
                error: finalError,
                segments: segments,
                eci: eci,
                isStructuredAppend: isStructuredAppend
            )
        }
        
        return finalError ?? 0
    }
    
    // MARK: - Utility Functions
    
    private static func getCharacterCountLength(mode: Int, version: Int) throws -> Int {
        let isMicro = version < 1
        let versionRange = isMicro ? version : getVersionRange(version)
        
        let cciBits: [Int: [Int: Int]] = [
            QRConstants.MODE_NUMERIC: [
                QRConstants.VERSION_M1: 3,
                QRConstants.VERSION_M2: 4,
                QRConstants.VERSION_M3: 5,
                QRConstants.VERSION_M4: 6,
                1: 10,  // Versions 1-9
                2: 12,  // Versions 10-26
                3: 14   // Versions 27-40
            ],
            // Add other modes...
        ]
        
        guard let modeBits = cciBits[mode],
              let length = modeBits[versionRange] else {
            throw QREncoderError.invalidVersion("Invalid version for character count indicator")
        }
        
        return length
    }
    
    private static func getVersionRange(_ version: Int) -> Int {
        if version <= 9 {
            return 1
        } else if version <= 26 {
            return 2
        } else {
            return 3
        }
    }
    
    private static func getMicroModeValue(_ mode: Int) -> Int {
        // Convert QR mode to Micro QR mode
        let microModeMapping: [Int: Int] = [
            QRConstants.MODE_NUMERIC: 0,
            QRConstants.MODE_ALPHANUMERIC: 1,
            QRConstants.MODE_BYTE: 2,
            QRConstants.MODE_KANJI: 3
        ]
        return microModeMapping[mode] ?? 0
    }
}

// MARK: - Supporting Types

struct StructuredAppendInfo {
    let symbolNumber: Int      // 0-15
    let totalSymbols: Int      // 1-16
    let parityData: Int
}

extension QREncoder {
    static func calculateStructuredAppendParity(for content: String) -> Int {
        var parity = 0
        for byte in content.utf8 {
            parity ^= Int(byte)
        }
        return parity
    }
}

// MARK: - Input Validation
extension QREncoder {
    /// Configuration options for QR code generation
    struct EncodingOptions {
        let version: Int?
        let errorLevel: Int?
        let mode: Int?
        let mask: Int?
        let encoding: String?
        let eci: Bool
        let micro: Bool?
        let boostError: Bool
        
        init(version: Int? = nil,
             errorLevel: Int? = nil,
             mode: Int? = nil,
             mask: Int? = nil,
             encoding: String? = nil,
             eci: Bool = false,
             micro: Bool? = nil,
             boostError: Bool = true) {
            self.version = version
            self.errorLevel = errorLevel
            self.mode = mode
            self.mask = mask
            self.encoding = encoding
            self.eci = eci
            self.micro = micro
            self.boostError = boostError
        }
    }
    
    /// Main validation and encoding entry point
    static func validateAndEncode(_ content: String, options: EncodingOptions) throws -> Code {
        // Step 1: Validate and normalize input parameters
        let validatedParams = try validateParameters(content: content, options: options)
        
        // Step 2: Validate content against chosen mode
        try validateContent(content, for: validatedParams.mode)
        
        // Step 3: Check version compatibility
        try validateVersionCompatibility(
            content: content,
            version: validatedParams.version,
            mode: validatedParams.mode,
            errorLevel: validatedParams.errorLevel,
            micro: validatedParams.micro
        )
        
        // Step 4: Perform the encoding
        return try encode(
            content: content,
            error: validatedParams.errorLevel,
            version: validatedParams.version,
            mode: validatedParams.mode,
            mask: validatedParams.mask,
            encoding: validatedParams.encoding,
            eci: validatedParams.eci,
            micro: validatedParams.micro,
            boostError: validatedParams.boostError
        )
    }
    
    // MARK: - Parameter Validation
    
    private struct ValidatedParameters {
        let version: Int?
        let errorLevel: Int?
        let mode: Int?
        let mask: Int?
        let encoding: String?
        let eci: Bool
        let micro: Bool?
        let boostError: Bool
    }
    
    private static func validateParameters(content: String, options: EncodingOptions) throws -> ValidatedParameters {
        // Validate content
        guard !content.isEmpty else {
            throw QREncoderError.invalidInput("Content cannot be empty")
        }
        
        // Validate version
        let version = try validateVersion(options.version, micro: options.micro)
        
        // Validate error level
        let errorLevel = try validateErrorLevel(
            options.errorLevel,
            version: version,
            micro: options.micro
        )
        
        // Validate mode
        let mode = try validateMode(
            options.mode,
            version: version,
            content: content
        )
        
        // Validate mask pattern
        let mask = try validateMask(
            options.mask,
            version: version
        )
        
        // Validate encoding
        let encoding = try validateEncoding(
            options.encoding,
            mode: mode,
            eci: options.eci
        )
        
        return ValidatedParameters(
            version: version,
            errorLevel: errorLevel,
            mode: mode,
            mask: mask,
            encoding: encoding,
            eci: options.eci,
            micro: options.micro,
            boostError: options.boostError
        )
    }
    
    // MARK: - Specific Validation Methods
    
    private static func validateVersion(_ version: Int?, micro: Bool?) throws -> Int? {
        guard let version = version else { return nil }
        
        if micro == true {
            guard QRConstants.MICRO_VERSIONS.contains(version) else {
                throw QREncoderError.invalidVersion("Invalid Micro QR version: \(version)")
            }
        } else if micro == false {
            guard (1...40).contains(version) else {
                throw QREncoderError.invalidVersion("QR version must be between 1 and 40")
            }
        }
        
        return version
    }
    
    private static func validateErrorLevel(_ errorLevel: Int?, version: Int?, micro: Bool?) throws -> Int? {
        guard let errorLevel = errorLevel else { return nil }
        
        // Validate error level range
        guard (0...3).contains(errorLevel) else {
            throw QREncoderError.invalidErrorLevel("Error level must be between 0 and 3")
        }
        
        // Validate error level for Micro QR
        if let version = version, version < 1 {
            // M1 only supports error level 0
            if version == QRConstants.VERSION_M1 && errorLevel != 0 {
                throw QREncoderError.invalidErrorLevel("M1 only supports error level 0")
            }
            
            // M2 only supports L and M
            if version == QRConstants.VERSION_M2 && errorLevel > QRConstants.ERROR_LEVEL_M {
                throw QREncoderError.invalidErrorLevel("M2 only supports error levels L and M")
            }
            
            // No Micro QR supports H
            if errorLevel == QRConstants.ERROR_LEVEL_H {
                throw QREncoderError.invalidErrorLevel("Micro QR does not support error level H")
            }
        }
        
        return errorLevel
    }
    
    private static func validateMode(_ mode: Int?, version: Int?, content: String) throws -> Int? {
        guard let mode = mode else { return nil }
        
        // Validate mode range
        let validModes = [
            QRConstants.MODE_NUMERIC,
            QRConstants.MODE_ALPHANUMERIC,
            QRConstants.MODE_BYTE,
            QRConstants.MODE_KANJI,
            QRConstants.MODE_HANZI
        ]
        
        guard validModes.contains(mode) else {
            throw QREncoderError.invalidMode("Invalid mode specified")
        }
        
        // Validate mode compatibility with version
        if let version = version {
            try validateModeVersionCompatibility(mode: mode, version: version)
        }
        
        // Validate content compatibility with mode
        try validateContentModeCompatibility(content: content, mode: mode)
        
        return mode
    }
    
    private static func validateMask(_ mask: Int?, version: Int?) throws -> Int? {
        guard let mask = mask else { return nil }
        
        if let version = version {
            let isMicro = version < 1
            if isMicro {
                guard (0...3).contains(mask) else {
                    throw QREncoderError.invalidMask("Micro QR mask must be between 0 and 3")
                }
            } else {
                guard (0...7).contains(mask) else {
                    throw QREncoderError.invalidMask("QR mask must be between 0 and 7")
                }
            }
        }
        
        return mask
    }
    
    private static func validateEncoding(_ encoding: String?, mode: Int?, eci: Bool) throws -> String? {
        guard let encoding = encoding else { return nil }
        
        // Validate encoding string
        if !String.availableStringEncodings.contains(where: {
            CFStringConvertEncodingToIANACharSetName($0.rawValue) as String? == encoding
        }) {
            throw QREncoderError.invalidEncoding("Unsupported encoding: \(encoding)")
        }
        
        // Validate ECI usage
        if eci && mode == QRConstants.MODE_BYTE && encoding != QRConstants.DEFAULT_BYTE_ENCODING {
            // Verify ECI assignment number exists
            try _ = getECIAssignmentNumber(for: encoding)
        }
        
        return encoding
    }
    
    // MARK: - Content Validation
    
    private static func validateContent(_ content: String, for mode: Int?) throws {
        guard let mode = mode else { return }
        
        switch mode {
        case QRConstants.MODE_NUMERIC:
            guard content.allSatisfy({ $0.isNumber }) else {
                throw QREncoderError.invalidContent("Content contains non-numeric characters")
            }
            
        case QRConstants.MODE_ALPHANUMERIC:
            let validChars = Set(QRConstants.ALPHANUMERIC_CHARS)
            guard content.allSatisfy({ validChars.contains($0) }) else {
                throw QREncoderError.invalidContent("Content contains invalid alphanumeric characters")
            }
            
        case QRConstants.MODE_KANJI:
            guard let data = content.data(using: .shiftJIS),
                  isKanji(data) else {
                throw QREncoderError.invalidContent("Content is not valid Kanji")
            }
            
        case QRConstants.MODE_HANZI:
            guard let data = content.data(using: .gb_18030_2000) else {
                throw QREncoderError.invalidContent("Content is not valid Hanzi")
            }
            // Additional Hanzi validation could be added here
            
        default:
            break // BYTE mode accepts any content
        }
    }
    
    // MARK: - Version Compatibility
    
    private static func validateVersionCompatibility(content: String,
                                                   version: Int?,
                                                   mode: Int?,
                                                   errorLevel: Int?,
                                                   micro: Bool?) throws {
        // Early return if no specific version is requested
        guard let version = version else { return }
        
        // Check if mode is supported by version
        if let mode = mode {
            try validateModeVersionCompatibility(mode: mode, version: version)
        }
        
        // Calculate required version for content
        let segments = try prepareData(content: content, mode: mode, encoding: nil)
        let requiredVersion = try findVersion(segments: segments,
                                            error: errorLevel,
                                            eci: false,
                                            micro: micro)
        
        // Verify content fits in specified version
        if requiredVersion > version {
            throw QREncoderError.dataOverflow(
                "Content too large for version \(getVersionName(version)). " +
                "Requires version \(getVersionName(requiredVersion))"
            )
        }
    }
    
    private static func validateModeVersionCompatibility(mode: Int, version: Int) throws {
        let isMicro = version < 1
        
        // M1 only supports numeric mode
        if version == QRConstants.VERSION_M1 && mode != QRConstants.MODE_NUMERIC {
            throw QREncoderError.invalidMode("M1 only supports numeric mode")
        }
        
        // M2 supports numeric and alphanumeric
        if version == QRConstants.VERSION_M2 &&
            ![QRConstants.MODE_NUMERIC, QRConstants.MODE_ALPHANUMERIC].contains(mode) {
            throw QREncoderError.invalidMode("M2 only supports numeric and alphanumeric modes")
        }
        
        // Verify mode is supported for Micro QR
        if isMicro && mode == QRConstants.MODE_KANJI {
            throw QREncoderError.invalidMode("Kanji mode is not supported in Micro QR")
        }
    }
}

// MARK: - QR Code Output Formats
extension QREncoder {
    /// Style configuration for QR code output
    public struct Style {
        /// Module (square) size in pixels/points
        public let moduleSize: CGFloat
        
        /// Quiet zone (white border) size in modules
        public let quietZone: Int
        
        /// Dark module color
        public let foregroundColor: Color
        
        /// Light module color
        public let backgroundColor: Color
        
        /// Optional data module shape customization
        public let dataShape: ModuleShape
        
        public init(
            moduleSize: CGFloat = 10,
            quietZone: Int = 4,
            foregroundColor: Color = .black,
            backgroundColor: Color = .white,
            dataShape: ModuleShape = .square
        ) {
            self.moduleSize = moduleSize
            self.quietZone = max(quietZone, 0)
            self.foregroundColor = foregroundColor
            self.backgroundColor = backgroundColor
            self.dataShape = dataShape
        }
    }
    
    /// Module shape options for QR code output
    public enum ModuleShape {
        case square
        case circle
        case roundedRect(cornerRadius: CGFloat)
    }
    
    /// Color representation (platform independent)
    public struct Color {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        
        public static let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
        public static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
        
        public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
        
        /// Initialize from hex string
        public init?(hex: String) {
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
            
            var rgb: UInt64 = 0
            guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
                return nil
            }
            
            self.red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            self.green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            self.blue = CGFloat(rgb & 0x0000FF) / 255.0
            self.alpha = 1.0
        }
        
        /// Convert to hex string
        var hexString: String {
            String(
                format: "#%02X%02X%02X",
                Int(red * 255),
                Int(green * 255),
                Int(blue * 255)
            )
        }
    }
    
    // MARK: - SVG Generation
    
    /// Generate SVG representation of the QR code
    static func toSVG(code: Code, style: Style = Style()) -> String {
        let matrix = code.matrix
        let quietZone = style.quietZone
        let moduleSize = style.moduleSize
        
        // Calculate dimensions
        let matrixSize = matrix.count
        let totalSize = (matrixSize + 2 * quietZone) * Int(moduleSize)
        
        // Start SVG document
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg width="\(totalSize)" height="\(totalSize)" version="1.1" xmlns="http://www.w3.org/2000/svg">
        """
        
        // Add background
        svg += """
        <rect width="100%" height="100%" fill="\(style.backgroundColor.hexString)"/>
        """
        
        // Generate modules
        for row in 0..<matrixSize {
            for col in 0..<matrixSize {
                if matrix[row][col] == 1 {
                    let x = (quietZone + col) * Int(moduleSize)
                    let y = (quietZone + row) * Int(moduleSize)
                    
                    switch style.dataShape {
                    case .square:
                        svg += """
                        <rect x="\(x)" y="\(y)" width="\(moduleSize)" height="\(moduleSize)" \
                        fill="\(style.foregroundColor.hexString)"/>
                        """
                        
                    case .circle:
                        let radius = moduleSize / 2
                        let cx = CGFloat(x) + radius
                        let cy = CGFloat(y) + radius
                        svg += """
                        <circle cx="\(cx)" cy="\(cy)" r="\(radius)" \
                        fill="\(style.foregroundColor.hexString)"/>
                        """
                        
                    case .roundedRect(let cornerRadius):
                        svg += """
                        <rect x="\(x)" y="\(y)" width="\(moduleSize)" height="\(moduleSize)" \
                        rx="\(cornerRadius)" ry="\(cornerRadius)" fill="\(style.foregroundColor.hexString)"/>
                        """
                    }
                }
            }
        }
        
        svg += "</svg>"
        return svg
    }
    
    // MARK: - PNG Data Generation
    
    /// Generate PNG data representation of the QR code
    static func toPNGData(code: Code, style: Style = Style()) -> Data? {
        let matrix = code.matrix
        let quietZone = style.quietZone
        let moduleSize = Int(style.moduleSize)
        
        // Calculate dimensions
        let matrixSize = matrix.count
        let totalSize = (matrixSize + 2 * quietZone) * moduleSize
        
        // Create bitmap context
        let bytesPerPixel = 4
        let bytesPerRow = totalSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: totalSize * bytesPerRow)
        
        // Fill background
        let bgRed = UInt8(style.backgroundColor.red * 255)
        let bgGreen = UInt8(style.backgroundColor.green * 255)
        let bgBlue = UInt8(style.backgroundColor.blue * 255)
        let bgAlpha = UInt8(style.backgroundColor.alpha * 255)
        
        for y in 0..<totalSize {
            for x in 0..<totalSize {
                let offset = (y * totalSize + x) * bytesPerPixel
                pixels[offset] = bgRed
                pixels[offset + 1] = bgGreen
                pixels[offset + 2] = bgBlue
                pixels[offset + 3] = bgAlpha
            }
        }
        
        // Draw modules
        let fgRed = UInt8(style.foregroundColor.red * 255)
        let fgGreen = UInt8(style.foregroundColor.green * 255)
        let fgBlue = UInt8(style.foregroundColor.blue * 255)
        let fgAlpha = UInt8(style.foregroundColor.alpha * 255)
        
        for row in 0..<matrixSize {
            for col in 0..<matrixSize {
                if matrix[row][col] == 1 {
                    let startX = (quietZone + col) * moduleSize
                    let startY = (quietZone + row) * moduleSize
                    
                    for y in startY..<(startY + moduleSize) {
                        for x in startX..<(startX + moduleSize) {
                            let offset = (y * totalSize + x) * bytesPerPixel
                            
                            // Apply shape masks if needed
                            var shouldDraw = true
                            switch style.dataShape {
                            case .circle:
                                let centerX = CGFloat(startX) + CGFloat(moduleSize) / 2
                                let centerY = CGFloat(startY) + CGFloat(moduleSize) / 2
                                let distance = sqrt(pow(CGFloat(x) - centerX, 2) + pow(CGFloat(y) - centerY, 2))
                                shouldDraw = distance <= CGFloat(moduleSize) / 2
                                
                            case .roundedRect(let cornerRadius):
                                let relX = CGFloat(x - startX)
                                let relY = CGFloat(y - startY)
                                let size = CGFloat(moduleSize)
                                
                                // Check if point is in corner regions
                                if relX < cornerRadius && relY < cornerRadius {
                                    // Top-left corner
                                    shouldDraw = sqrt(pow(cornerRadius - relX, 2) + pow(cornerRadius - relY, 2)) <= cornerRadius
                                } else if relX > (size - cornerRadius) && relY < cornerRadius {
                                    // Top-right corner
                                    shouldDraw = sqrt(pow(relX - (size - cornerRadius), 2) + pow(cornerRadius - relY, 2)) <= cornerRadius
                                } else if relX < cornerRadius && relY > (size - cornerRadius) {
                                    // Bottom-left corner
                                    shouldDraw = sqrt(pow(cornerRadius - relX, 2) + pow(relY - (size - cornerRadius), 2)) <= cornerRadius
                                } else if relX > (size - cornerRadius) && relY > (size - cornerRadius) {
                                    // Bottom-right corner
                                    shouldDraw = sqrt(pow(relX - (size - cornerRadius), 2) + pow(relY - (size - cornerRadius), 2)) <= cornerRadius
                                }
                                
                            default:
                                break
                            }
                            
                            if shouldDraw {
                                pixels[offset] = fgRed
                                pixels[offset + 1] = fgGreen
                                pixels[offset + 2] = fgBlue
                                pixels[offset + 3] = fgAlpha
                            }
                        }
                    }
                }
            }
        }
        
        // Create CGImage
        guard let context = CGContext(
            data: &pixels,
            width: totalSize,
            height: totalSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = context.makeImage() else {
            return nil
        }
        
        // Convert to PNG data
        #if os(iOS) || os(watchOS) || os(tvOS)
        let image = UIImage(cgImage: cgImage)
        return image.pngData()
        #elseif os(macOS)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: totalSize, height: totalSize))
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
        #endif
    }
    
    // MARK: - String Output
    
    /// Generate ASCII art representation of the QR code
    static func toASCII(code: Code, darkModule: Character = "██", lightModule: Character = "  ") -> String {
        let matrix = code.matrix
        var result = ""
        
        for row in matrix {
            for value in row {
                result += String(repeating: value == 1 ? darkModule : lightModule, count: 1)
            }
            result += "\n"
        }
        
        return result
    }
    
    // MARK: - Utility Methods
    
    /// Get QR code size in modules (including quiet zone)
    static func size(code: Code, quietZone: Int = 4) -> Int {
        code.matrix.count + 2 * quietZone
    }
    
    /// Get module coordinates for a given point
    static func moduleCoordinates(at point: CGPoint,
                                code: Code,
                                style: Style = Style()) -> (row: Int, col: Int)? {
        let totalSize = size(code: code, quietZone: style.quietZone)
        let moduleSize = style.moduleSize
        
        let row = Int(point.y / moduleSize) - style.quietZone
        let col = Int(point.x / moduleSize) - style.quietZone
        
        guard row >= 0 && row < code.matrix.count &&
              col >= 0 && col < code.matrix.count else {
            return nil
        }
        
        return (row, col)
    }
}

// MARK: - Public API
public final class QRCode {
    /// The internal code representation
    private let code: QREncoder.Code
    
    /// Style configuration
    private var style: QREncoder.Style
    
    // MARK: - Public Properties
    
    /// The QR code version
    public var version: Int {
        code.version
    }
    
    /// The error correction level
    public var errorLevel: ErrorLevel {
        ErrorLevel(rawValue: code.error) ?? .medium
    }
    
    /// The mask pattern used
    public var mask: Int {
        code.mask
    }
    
    /// The matrix size (number of modules)
    public var size: Int {
        code.matrix.count
    }
    
    // MARK: - Public Enums
    
    public enum ErrorLevel: Int {
        case low = 0
        case medium = 1
        case quartile = 2
        case high = 3
        
        var description: String {
            switch self {
            case .low: return "L"
            case .medium: return "M"
            case .quartile: return "Q"
            case .high: return "H"
            }
        }
    }
    
    public enum QRError: Error {
        case encodingError(String)
        case invalidInput(String)
        case invalidConfiguration(String)
    }
    
    // MARK: - Initialization
    
    /// Create a QR code with the given content and options
    public static func create(
        _ content: String,
        errorLevel: ErrorLevel = .medium,
        version: Int? = nil,
        mask: Int? = nil,
        encoding: String? = nil,
        micro: Bool? = nil
    ) throws -> QRCode {
        let options = QREncoder.EncodingOptions(
            version: version,
            errorLevel: errorLevel.rawValue,
            mode: nil,
            mask: mask,
            encoding: encoding,
            eci: false,
            micro: micro,
            boostError: true
        )
        
        do {
            let code = try QREncoder.validateAndEncode(content, options: options)
            return QRCode(code: code)
        } catch {
            throw QRError.encodingError(error.localizedDescription)
        }
    }
    
    private init(code: QREncoder.Code, style: QREncoder.Style = QREncoder.Style()) {
        self.code = code
        self.style = style
    }
    
    // MARK: - Styling
    
    /// Apply new style configuration
    @discardableResult
    public func applyStyle(_ style: QREncoder.Style) -> QRCode {
        self.style = style
        return self
    }
    
    /// Set the module size
    @discardableResult
    public func moduleSize(_ size: CGFloat) -> QRCode {
        var newStyle = style
        newStyle.moduleSize = size
        self.style = newStyle
        return self
    }
    
    /// Set the quiet zone size
    @discardableResult
    public func quietZone(_ size: Int) -> QRCode {
        var newStyle = style
        newStyle.quietZone = size
        self.style = newStyle
        return self
    }
    
    /// Set the colors
    @discardableResult
    public func colors(front: QREncoder.Color, back: QREncoder.Color? = nil) -> QRCode {
        var newStyle = style
        newStyle.foregroundColor = front
        if let back = back {
            newStyle.backgroundColor = back
        }
        self.style = newStyle
        return self
    }
    
    // MARK: - Output Generation
    
    /// Generate SVG representation
    public func svg() -> String {
        QREncoder.toSVG(code: code, style: style)
    }
    
    /// Generate PNG data
    public func pngData() -> Data? {
        QREncoder.toPNGData(code: code, style: style)
    }
    
    /// Generate ASCII representation
    public func ascii(dark: Character = "██", light: Character = "  ") -> String {
        QREncoder.toASCII(code: code, darkModule: dark, lightModule: light)
    }
    
    // MARK: - Utility Methods
    
    /// Check if a module is dark at the given coordinates
    public func isDark(row: Int, col: Int) -> Bool {
        guard row >= 0 && row < size && col >= 0 && col < size else {
            return false
        }
        return code.matrix[row][col] == 1
    }
    
    /// Get the total size including quiet zone
    public func totalSize(unitSize: CGFloat? = nil) -> CGFloat {
        let moduleSize = unitSize ?? style.moduleSize
        return CGFloat(size + 2 * style.quietZone) * moduleSize
    }
    
    /// Get module bounds for a specific position
    public func moduleBounds(row: Int, col: Int) -> CGRect {
        let x = CGFloat(style.quietZone + col) * style.moduleSize
        let y = CGFloat(style.quietZone + row) * style.moduleSize
        return CGRect(x: x, y: y, width: style.moduleSize, height: style.moduleSize)
    }
}

// MARK: - Utility Extensions
extension QRCode {
    /// QR Code metadata
    public struct Metadata {
        public let version: Int
        public let errorLevel: ErrorLevel
        public let mask: Int
        public let micro: Bool
        public let moduleCount: Int
        public let capacity: Int
        
        fileprivate init(code: QREncoder.Code) {
            self.version = code.version
            self.errorLevel = ErrorLevel(rawValue: code.error) ?? .medium
            self.mask = code.mask
            self.micro = code.version < 1
            self.moduleCount = code.matrix.count
            self.capacity = QREncoder.calculateSymbolCapacity(
                version: code.version,
                errorLevel: code.error
            )
        }
    }
    
    /// Get QR code metadata
    public var metadata: Metadata {
        Metadata(code: code)
    }
    
    /// Check if this is a Micro QR code
    public var isMicro: Bool {
        version < 1
    }
    
    /// Create a sequence of QR codes for large content
    public static func sequence(
        _ content: String,
        errorLevel: ErrorLevel = .medium,
        version: Int? = nil
    ) throws -> [QRCode] {
        do {
            let codes = try QREncoder.encodeSequence(
                content: content,
                error: errorLevel.rawValue,
                version: version
            )
            return codes.map { QRCode(code: $0) }
        } catch {
            throw QRError.encodingError(error.localizedDescription)
        }
    }
}

// MARK: - Additional Utilities
extension QRCode {
    /// Segment analysis information
    public struct SegmentInfo {
        public let mode: Int
        public let characterCount: Int
        public let bitCount: Int
        public let encoding: String?
    }
    
    /// Get information about the encoded segments
    public var segments: [SegmentInfo] {
        code.segments.map { segment in
            SegmentInfo(
                mode: segment.mode,
                characterCount: segment.charCount,
                bitCount: segment.bits.count,
                encoding: segment.encoding
            )
        }
    }
    
    /// Calculate ideal version for content
    public static func idealVersion(
        for content: String,
        errorLevel: ErrorLevel = .medium,
        micro: Bool? = nil
    ) throws -> Int {
        do {
            let segments = try QREncoder.prepareData(
                content: content,
                mode: nil,
                encoding: nil
            )
            return try QREncoder.findVersion(
                segments: segments,
                error: errorLevel.rawValue,
                eci: false,
                micro: micro
            )
        } catch {
            throw QRError.encodingError(error.localizedDescription)
        }
    }
    
    /// Validate if content can fit in specified version
    public static func validateContent(
        _ content: String,
        version: Int,
        errorLevel: ErrorLevel = .medium
    ) throws -> Bool {
        do {
            let required = try idealVersion(
                for: content,
                errorLevel: errorLevel
            )
            return required <= version
        } catch {
            throw QRError.encodingError(error.localizedDescription)
        }
    }
    
    /// Get version name (e.g., "1" or "M1")
    public var versionName: String {
        QREncoder.getVersionName(version)
    }
    
    /// Calculate maximum content length for a version
    public static func maximumContentLength(
        version: Int,
        errorLevel: ErrorLevel,
        mode: Int? = nil
    ) -> Int {
        // Implementation would calculate maximum content length based on version,
        // error level, and mode
        QREncoder.calculateMaxContentLength(
            version: version,
            errorLevel: errorLevel.rawValue,
            mode: mode
        )
    }
}

// MARK: - Debug Support
extension QRCode: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        QR Code:
        Version: \(versionName)
        Error Level: \(errorLevel.description)
        Size: \(size)x\(size)
        Mask: \(mask)
        Module Count: \(size * size)
        """
    }
}
