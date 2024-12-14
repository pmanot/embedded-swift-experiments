// MARK: - JSMN Type & Error Codes

public enum JSMNType: UInt8 {
    case undefined = 0
    case object    = 1
    case array     = 2
    case string    = 4
    case primitive = 8
}

public enum JSMNErr: Int {
    case nomem = -1   // Not enough tokens
    case inval = -2   // Invalid character
    case part  = -3   // Incomplete JSON
}

/// Swift equivalent of jsmntok_t
public struct JSMNToken {
    public var type: JSMNType
    public var start: Int
    public var end: Int
    public var size: Int
    
    public init() {
        self.type = .undefined
        self.start = -1
        self.end = -1
        self.size = 0
    }
}

/// Swift equivalent of jsmn_parser
public struct JSMNParser {
    public var pos: Int
    public var toknext: Int
    public var toksuper: Int
    
    public init() {
        self.pos = 0
        self.toknext = 0
        self.toksuper = -1
    }
}

// MARK: - Low-Level EmbeddedJSMN

public struct EmbeddedJSMN {
    public static func initParser(_ parser: inout JSMNParser) {
        parser.pos = 0
        parser.toknext = 0
        parser.toksuper = -1
    }
    
    /// Parse function returns token count (>=0) or negative error code
    public static func parse(parser: inout JSMNParser,
                             jsonBuffer: UnsafePointer<CChar>,
                             length: Int,
                             tokens: inout [JSMNToken]) -> Int {
        var count = parser.toknext
        
        while parser.pos < length && jsonBuffer[parser.pos] != 0 {
            let c = jsonBuffer[parser.pos]
            
            switch c {
            case 123: // '{'
                fallthrough
            case 91:  // '['
                count += 1
                guard let idx = jsmnAllocToken(&parser, &tokens) else {
                    // Allocation failed
                    return JSMNErr.nomem.rawValue
                }
                let tokenType: JSMNType = (c == 123) ? .object : .array
                tokens[idx].type  = tokenType
                tokens[idx].start = parser.pos
                tokens[idx].end   = -1
                tokens[idx].size  = 0
                
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                parser.toksuper = idx
                // Debug print removed
                
            case 125: // '}'
                fallthrough
            case 93:  // ']'
                let closingType: JSMNType = (c == 125) ? .object : .array
                if let newSuper = jsmnClose(&parser, &tokens, closingType, parser.pos) {
                    parser.toksuper = newSuper
                    // Debug print removed
                } else {
                    // Mismatch closing
                    return JSMNErr.inval.rawValue
                }
                
            case 34: // '"'
                let r = jsmnParseString(&parser, jsonBuffer, length, &tokens)
                if r < 0 { 
                    // Error parsing string
                    return r 
                }
                count += 1
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                // Debug print removed
                
            case 9, 10, 13, 32:
                // Whitespace - skip
                break
                
            case 58: // ':'
                parser.toksuper = parser.toknext - 1
                // Debug print removed
                
            case 44: // ','
                if parser.toksuper != -1 {
                    let ttype = tokens[parser.toksuper].type
                    if ttype != .array && ttype != .object {
                        if let newSuper = jsmnFindParent(parser: parser, tokens: tokens) {
                            parser.toksuper = newSuper
                            // Debug print removed
                        } else {
                            // Invalid parent after ','
                            return JSMNErr.inval.rawValue
                        }
                    }
                }
                
            default:
                // Parse primitive
                let r = jsmnParsePrimitive(&parser, jsonBuffer, length, &tokens)
                if r < 0 { 
                    // Error parsing primitive
                    return r 
                }
                count += 1
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                // Debug print removed
            }
            
            parser.pos += 1
        }
        
        // Check for unmatched tokens
        var i = parser.toknext - 1
        while i >= 0 {
            if tokens[i].start != -1 && tokens[i].end == -1 {
                // Unmatched token
                return JSMNErr.part.rawValue
            }
            i -= 1
        }
        
        return count
    }
    
    // MARK: - JSMN Helpers
    
    private static func jsmnAllocToken(_ parser: inout JSMNParser,
                                      _ tokens: inout [JSMNToken]) -> Int? {
        if parser.toknext >= tokens.count { return nil }
        let idx = parser.toknext
        parser.toknext += 1
        tokens[idx] = JSMNToken()
        return idx
    }
    
    private static func jsmnClose(_ parser: inout JSMNParser,
                                  _ tokens: inout [JSMNToken],
                                  _ closingType: JSMNType,
                                  _ endPos: Int) -> Int? {
        for i in stride(from: parser.toknext - 1, through: 0, by: -1) {
            if tokens[i].start != -1 && tokens[i].end == -1 {
                if tokens[i].type != closingType {
                    return nil
                }
                tokens[i].end = endPos + 1
                parser.toksuper = -1
                for j in stride(from: i, through: 0, by: -1) {
                    if tokens[j].start != -1 && tokens[j].end == -1 {
                        parser.toksuper = j
                        break
                    }
                }
                return parser.toksuper
            }
        }
        return nil
    }
    
    private static func jsmnParseString(_ parser: inout JSMNParser,
                                       _ json: UnsafePointer<CChar>,
                                       _ length: Int,
                                       _ tokens: inout [JSMNToken]) -> Int {
        let startPos = parser.pos
        parser.pos += 1 // Skip opening quote
        
        while parser.pos < length && json[parser.pos] != 0 {
            let c = json[parser.pos]
            if c == 34 { // Closing quote
                guard let tIdx = jsmnAllocToken(&parser, &tokens) else {
                    parser.pos = startPos
                    return JSMNErr.nomem.rawValue
                }
                tokens[tIdx].type  = .string
                tokens[tIdx].start = startPos + 1
                tokens[tIdx].end   = parser.pos
                tokens[tIdx].size  = 0
                return 0
            }
            if c == 92 && parser.pos + 1 < length { // Escape character '\'
                parser.pos += 1
                let esc = json[parser.pos]
                switch esc {
                case 34, 47, 92, 98, 102, 114, 110, 116:
                    // Valid escape sequences, continue
                    break
                case 117: // Unicode escape \uXXXX
                    var i = 0
                    while i < 4 && parser.pos + 1 < length {
                        parser.pos += 1
                        let hx = json[parser.pos]
                        let isHex = (hx >= 48 && hx <= 57)  // '0'-'9'
                                 || (hx >= 65 && hx <= 70)   // 'A'-'F'
                                 || (hx >= 97 && hx <= 102)  // 'a'-'f'
                        if !isHex {
                            parser.pos = startPos
                            return JSMNErr.inval.rawValue
                        }
                        i += 1
                    }
                    parser.pos -= 1 // Adjust position
                default:
                    // Invalid escape sequence
                    parser.pos = startPos
                    return JSMNErr.inval.rawValue
                }
            }
            parser.pos += 1
        }
        
        // String not closed
        parser.pos = startPos
        return JSMNErr.part.rawValue
    }
    
    private static func jsmnParsePrimitive(_ parser: inout JSMNParser,
                                          _ json: UnsafePointer<CChar>,
                                          _ length: Int,
                                          _ tokens: inout [JSMNToken]) -> Int {
        let startPos = parser.pos
        while parser.pos < length && json[parser.pos] != 0 {
            let c = json[parser.pos]
            #if !JSMN_STRICT
            switch c {
            case 58, 9, 13, 10, 32, 44, 93, 125:
                return jsmnPrimitiveDone(&parser, &tokens, startPos)
            default:
                if c < 32 || c >= 127 {
                    parser.pos = startPos
                    return JSMNErr.inval.rawValue
                }
            }
            #else
            switch c {
            case 9, 13, 10, 32, 44, 93, 125:
                return jsmnPrimitiveDone(&parser, &tokens, startPos)
            default:
                if c < 32 || c >= 127 {
                    parser.pos = startPos
                    return JSMNErr.inval.rawValue
                }
            }
            #endif
            parser.pos += 1
        }
        #if !JSMN_STRICT
        return jsmnPrimitiveDone(&parser, &tokens, startPos)
        #else
        parser.pos = startPos
        return JSMNErr.part.rawValue
        #endif
    }
    
    private static func jsmnPrimitiveDone(_ parser: inout JSMNParser,
                                         _ tokens: inout [JSMNToken],
                                         _ startPos: Int) -> Int {
        guard let tIdx = jsmnAllocToken(&parser, &tokens) else {
            parser.pos = startPos
            return JSMNErr.nomem.rawValue
        }
        tokens[tIdx].type  = .primitive
        tokens[tIdx].start = startPos
        tokens[tIdx].end   = parser.pos
        tokens[tIdx].size  = 0
        parser.pos -= 1
        return 0
    }
    
    private static func jsmnFindParent(parser: JSMNParser, tokens: [JSMNToken]) -> Int? {
        for i in stride(from: parser.toknext - 1, through: 0, by: -1) {
            let t = tokens[i]
            if (t.type == .array || t.type == .object),
               t.start != -1, t.end == -1 {
                return i
            }
        }
        return nil
    }
}
