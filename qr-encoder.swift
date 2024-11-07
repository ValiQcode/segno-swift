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
