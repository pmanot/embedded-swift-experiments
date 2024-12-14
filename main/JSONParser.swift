// MARK: - jsmn Type & Error Codes

public enum JsmnType: UInt8 {
    case undefined = 0
    case object    = 1
    case array     = 2
    case string    = 4
    case primitive = 8
}

public enum JsmnErr: Int {
    case nomem = -1   // Not enough tokens
    case inval = -2   // Invalid character
    case part  = -3   // Incomplete JSON
}

/// Swift equivalent of jsmntok_t
public struct JsmnToken {
    public var type: JsmnType
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
public struct JsmnParser {
    public var pos: Int
    public var toknext: Int
    public var toksuper: Int
    
    public init() {
        self.pos = 0
        self.toknext = 0
        self.toksuper = -1
    }
}

// MARK: - Low-Level EmbeddedJsmn

public struct EmbeddedJsmn {
    public static func initParser(_ parser: inout JsmnParser) {
        parser.pos = 0
        parser.toknext = 0
        parser.toksuper = -1
    }
    
    /// Parse function returns token count (>=0) or negative error code
    public static func parse(parser: inout JsmnParser,
                             jsonBuffer: UnsafePointer<CChar>,
                             length: Int,
                             tokens: inout [JsmnToken]) -> Int {
        var count = parser.toknext
        
        while parser.pos < length && jsonBuffer[parser.pos] != 0 {
            let c = jsonBuffer[parser.pos]
            
            switch c {
            case 123: // '{'
                fallthrough
            case 91:  // '['
                count += 1
                guard let idx = jsmn_alloc_token(&parser, &tokens) else {
                    print("[EmbeddedJsmn] Allocation failed at pos=\(parser.pos)")
                    return JsmnErr.nomem.rawValue
                }
                let tokenType: JsmnType = (c == 123) ? .object : .array
                tokens[idx].type  = tokenType
                tokens[idx].start = parser.pos
                tokens[idx].end   = -1
                tokens[idx].size  = 0
                
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                parser.toksuper = idx
                print("[EmbeddedJsmn] Opened \(tokenType) at pos=\(parser.pos), tokenIndex=\(idx)")
                
            case 125: // '}'
                fallthrough
            case 93:  // ']'
                let closingType: JsmnType = (c == 125) ? .object : .array
                if let newSuper = jsmn_close(&parser, &tokens, closingType, parser.pos) {
                    parser.toksuper = newSuper
                    print("[EmbeddedJsmn] Closed \(closingType) at pos=\(parser.pos), newSuper=\(newSuper)")
                } else {
                    print("[EmbeddedJsmn] Mismatch closing \(closingType) at pos=\(parser.pos)")
                    return JsmnErr.inval.rawValue
                }
                
            case 34: // '"'
                let r = jsmn_parse_string(&parser, jsonBuffer, length, &tokens)
                if r < 0 { 
                    print("[EmbeddedJsmn] Error parsing string at pos=\(parser.pos)")
                    return r 
                }
                count += 1
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                print("[EmbeddedJsmn] Parsed string at pos=\(parser.pos), tokenIndex=\(parser.toknext - 1)")
                
            case 9, 10, 13, 32:
                // Whitespace - skip
                break
                
            case 58: // ':'
                parser.toksuper = parser.toknext - 1
                print("[EmbeddedJsmn] Encountered ':' at pos=\(parser.pos), toksuper set to \(parser.toksuper)")
                
            case 44: // ','
                if parser.toksuper != -1 {
                    let ttype = tokens[parser.toksuper].type
                    if ttype != .array && ttype != .object {
                        if let newSuper = jsmn_find_parent(parser: parser, tokens: tokens) {
                            print("[EmbeddedJsmn] Encountered ',' at pos=\(parser.pos), toksuper updated to \(newSuper)")
                            parser.toksuper = newSuper
                        } else {
                            print("[EmbeddedJsmn] Invalid parent after ',' at pos=\(parser.pos)")
                            return JsmnErr.inval.rawValue
                        }
                    }
                }
                
            default:
                // Parse primitive
                let r = jsmn_parse_primitive(&parser, jsonBuffer, length, &tokens)
                if r < 0 { 
                    print("[EmbeddedJsmn] Error parsing primitive at pos=\(parser.pos)")
                    return r 
                }
                count += 1
                if parser.toksuper != -1 {
                    tokens[parser.toksuper].size += 1
                }
                print("[EmbeddedJsmn] Parsed primitive at pos=\(parser.pos), tokenIndex=\(parser.toknext - 1)")
            }
            
            parser.pos += 1
        }
        
        // Check for unmatched tokens
        var i = parser.toknext - 1
        while i >= 0 {
            if tokens[i].start != -1 && tokens[i].end == -1 {
                print("[EmbeddedJsmn] Unmatched token at index=\(i)")
                return JsmnErr.part.rawValue
            }
            i -= 1
        }
        
        return count
    }
    
    // MARK: - jsmn Helpers
    
    private static func jsmn_alloc_token(_ parser: inout JsmnParser,
                                        _ tokens: inout [JsmnToken]) -> Int? {
        if parser.toknext >= tokens.count { return nil }
        let idx = parser.toknext
        parser.toknext += 1
        tokens[idx] = JsmnToken()
        return idx
    }
    
    private static func jsmn_close(_ parser: inout JsmnParser,
                                   _ tokens: inout [JsmnToken],
                                   _ closingType: JsmnType,
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
    
    private static func jsmn_parse_string(_ parser: inout JsmnParser,
                                         _ json: UnsafePointer<CChar>,
                                         _ length: Int,
                                         _ tokens: inout [JsmnToken]) -> Int {
        let startPos = parser.pos
        parser.pos += 1 // Skip opening quote
        
        while parser.pos < length && json[parser.pos] != 0 {
            let c = json[parser.pos]
            if c == 34 { // Closing quote
                guard let tIdx = jsmn_alloc_token(&parser, &tokens) else {
                    parser.pos = startPos
                    return JsmnErr.nomem.rawValue
                }
                tokens[tIdx].type  = .string
                tokens[tIdx].start = startPos + 1
                tokens[tIdx].end   = parser.pos
                tokens[tIdx].size  = 0
                print("[EmbeddedJsmn] String parsed from \(startPos) to \(parser.pos), tokenIndex=\(tIdx)")
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
                            return JsmnErr.inval.rawValue
                        }
                        i += 1
                    }
                    parser.pos -= 1 // Adjust position
                default:
                    // Invalid escape sequence
                    parser.pos = startPos
                    return JsmnErr.inval.rawValue
                }
            }
            parser.pos += 1
        }
        
        // String not closed
        parser.pos = startPos
        return JsmnErr.part.rawValue
    }
    
    private static func jsmn_parse_primitive(_ parser: inout JsmnParser,
                                             _ json: UnsafePointer<CChar>,
                                             _ length: Int,
                                             _ tokens: inout [JsmnToken]) -> Int {
        let startPos = parser.pos
        while parser.pos < length && json[parser.pos] != 0 {
            let c = json[parser.pos]
            #if !JSMN_STRICT
            switch c {
            case 58, 9, 13, 10, 32, 44, 93, 125:
                return jsmn_primitive_done(&parser, &tokens, startPos)
            default:
                if c < 32 || c >= 127 {
                    parser.pos = startPos
                    return JsmnErr.inval.rawValue
                }
            }
            #else
            switch c {
            case 9, 13, 10, 32, 44, 93, 125:
                return jsmn_primitive_done(&parser, &tokens, startPos)
            default:
                if c < 32 || c >= 127 {
                    parser.pos = startPos
                    return JsmnErr.inval.rawValue
                }
            }
            #endif
            parser.pos += 1
        }
        #if !JSMN_STRICT
        return jsmn_primitive_done(&parser, &tokens, startPos)
        #else
        parser.pos = startPos
        return JsmnErr.part.rawValue
        #endif
    }
    
    private static func jsmn_primitive_done(_ parser: inout JsmnParser,
                                           _ tokens: inout [JsmnToken],
                                           _ startPos: Int) -> Int {
        guard let tIdx = jsmn_alloc_token(&parser, &tokens) else {
            parser.pos = startPos
            return JsmnErr.nomem.rawValue
        }
        tokens[tIdx].type  = .primitive
        tokens[tIdx].start = startPos
        tokens[tIdx].end   = parser.pos
        tokens[tIdx].size  = 0
        parser.pos -= 1
        print("[EmbeddedJsmn] Primitive parsed from \(startPos) to \(parser.pos), tokenIndex=\(tIdx)")
        return 0
    }
    
    private static func jsmn_find_parent(parser: JsmnParser, tokens: [JsmnToken]) -> Int? {
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

// MARK: - High-Level Swift API

public enum JSONErrorCode: Int {
    case parseError = -1
    case invalidKey = -2
}

/// A high-level "JSON parser" wrapping our jsmn parser & tokens
public final class JSONParser {
    public init() {}
    
    /// Parse the given JSON string, returning a JSONValue referencing the top-level token.
    public func parse(_ jsonString: String) -> JSONValue {
        let utf8 = Array(jsonString.utf8CString)
        
        var parser = JsmnParser()
        EmbeddedJsmn.initParser(&parser)
        var tokens = [JsmnToken](repeating: JsmnToken(), count: 128)
        
        let result = utf8.withUnsafeBufferPointer { ptr -> Int in
            EmbeddedJsmn.parse(parser: &parser,
                               jsonBuffer: ptr.baseAddress!,
                               length: ptr.count - 1,
                               tokens: &tokens)
        }
        
        print("[JSONParser] parse result=\(result)")
        if result < 0 {
            print("[JSONParser] parse error code=\(result)")
            return JSONValue(tokens: tokens, buffer: utf8, index: -1, parseError: result)
        }
        // Root is tokens[0]
        return JSONValue(tokens: tokens, buffer: utf8, index: 0, parseError: 0)
    }
}

/// Similar to what you had: a chainable JSONValue with subscript for objects/arrays
public struct JSONValue {
    internal let tokens: [JsmnToken]
    internal let buffer: [CChar]
    internal let index: Int
    internal let parseError: Int  // store negative error code or 0 if success
    
    public init(tokens: [JsmnToken], buffer: [CChar], index: Int, parseError: Int) {
        self.tokens = tokens
        self.buffer = buffer
        self.index = index
        self.parseError = parseError
    }
    
    private func isValid() -> Bool {
        if parseError < 0 { return false }
        if index < 0 || index >= tokens.count { return false }
        return true
    }
    
    /// Subscript for object key
    public subscript(key: String) -> JSONValue {
        if parseError < 0 {
            print("[JSONValue] Existing parseError=\(parseError), returning fail for key=\(key)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: parseError)
        }
        guard isValid() else {
            print("[JSONValue] isValid fail for key=\(key)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.parseError.rawValue)
        }
        let tok = tokens[index]
        if tok.type != .object {
            print("[JSONValue] Not an object. Type=\(tok.type), key=\(key)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.parseError.rawValue)
        }
        
        if let childKeyIndex = findKey(key, objectIndex: index, tokens: tokens, buffer: buffer) {
            let valIndex = childKeyIndex + 1
            if valIndex < tokens.count {
                print("[JSONValue] Found key='\(key)' at token=\(childKeyIndex), valIndex=\(valIndex)")
                return JSONValue(tokens: tokens, buffer: buffer, index: valIndex, parseError: 0)
            } else {
                print("[JSONValue] Invalid valIndex=\(valIndex) for key='\(key)'")
                return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.invalidKey.rawValue)
            }
        } else {
            print("[JSONValue] Key='\(key)' not found")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.invalidKey.rawValue)
        }
    }
    
    /// Subscript for array index
    public subscript(idx: Int) -> JSONValue {
        if parseError < 0 {
            print("[JSONValue] Existing parseError=\(parseError), returning fail for idx=\(idx)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: parseError)
        }
        guard isValid() else {
            print("[JSONValue] isValid fail for idx=\(idx)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.parseError.rawValue)
        }
        let arrTok = tokens[index]
        if arrTok.type != .array {
            print("[JSONValue] Not an array. Type=\(arrTok.type), idx=\(idx)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.parseError.rawValue)
        }
        
        print("[JSONValue] Subscript array idx=\(idx), array token size=\(arrTok.size)")
        
        var arrayChildCount = 0
        var j = index + 1
        var childIndex = -1
        
        for _ in 0..<arrTok.size {
            if j >= tokens.count { break }
            if isDirectChild(childIndex: j, parentIndex: index, tokens: tokens) {
                if arrayChildCount == idx {
                    childIndex = j
                    print("[JSONValue] Found array item at tokenIndex=\(j) for idx=\(idx)")
                    break
                }
                // Move to next token after current child subtree
                let nextJ = nextTokenIndex(after: j, tokens: tokens)
                print("[JSONValue] Skipping tokens from \(j) to \(nextJ - 1)")
                j = nextJ
                arrayChildCount += 1
            } else {
                print("[JSONValue] Token at \(j) is not a direct child, skipping")
                j += 1
            }
        }
        
        if childIndex == -1 {
            print("[JSONValue] Array index out of range: idx=\(idx)")
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: JSONErrorCode.invalidKey.rawValue)
        }
        return JSONValue(tokens: tokens, buffer: buffer, index: childIndex, parseError: 0)
    }
    
    /// Attempt to read as integer if type == .primitive
    public func asInt() -> Int? {
        if parseError < 0 { return nil }
        if !isValid() { return nil }
        
        let tok = tokens[index]
        if tok.type != .primitive { 
            print("[JSONValue] asInt failed: token type is \(tok.type)")
            return nil 
        }
        let length = tok.end - tok.start
        if length <= 0 { 
            print("[JSONValue] asInt failed: invalid length \(length)")
            return nil 
        }
        var localBuf = [CChar](repeating: 0, count: length + 1)
        for j in 0..<length {
            localBuf[j] = buffer[tok.start + j]
        }
        localBuf[length] = 0
        let s = String(cString: localBuf)
        print("[JSONValue] asInt parsed string='\(s)'")
        return Int(s)
    }
    
    /// If type == .string or .primitive, interpret as string
    public func asString() -> String? {
        if parseError < 0 { return nil }
        if !isValid() { return nil }
        
        let tok = tokens[index]
        if tok.type != .string && tok.type != .primitive {
            print("[JSONValue] asString failed: token type is \(tok.type)")
            return nil
        }
        let length = tok.end - tok.start
        if length <= 0 { return "" }
        var localBuf = [CChar](repeating: 0, count: length + 1)
        for j in 0..<length {
            localBuf[j] = buffer[tok.start + j]
        }
        localBuf[length] = 0
        let s = String(cString: localBuf)
        print("[JSONValue] asString parsed string='\(s)'")
        return s
    }
}

// MARK: - Helper Functions

/// Find a key named `keyName` in the object at `objectIndex`. Return token index if found, else nil.
func findKey(_ keyName: String,
            objectIndex: Int,
            tokens: [JsmnToken],
            buffer: [CChar]) -> Int? {
    let objTok = tokens[objectIndex]
    if objTok.type != .object {
        print("[findKey] Token at \(objectIndex) is not an object")
        return nil
    }
    
    var i = objectIndex + 1
    while i < tokens.count {
        let t = tokens[i]
        if t.start >= objTok.end { break }
        if isDirectChild(childIndex: i, parentIndex: objectIndex, tokens: tokens),
           t.type == .string {
            if substringEquals(token: t, buffer: buffer, compare: keyName) {
                print("[findKey] Matched key='\(keyName)' at token=\(i)")
                return i
            }
        }
        i += 1
    }
    print("[findKey] Key='\(keyName)' not found in object at token=\(objectIndex)")
    return nil
}

/// Check if `childIndex` is a direct child of `parentIndex`
func isDirectChild(childIndex: Int, parentIndex: Int, tokens: [JsmnToken]) -> Bool {
    let parent = tokens[parentIndex]
    let child  = tokens[childIndex]
    if parent.end == -1 { return false }
    return child.start >= parent.start && child.end <= parent.end
}

/// Compare substring in `token` with `compare` string
func substringEquals(token: JsmnToken, buffer: [CChar], compare: String) -> Bool {
    let tokenLen = token.end - token.start
    let compareBytes = Array(compare.utf8)
    if tokenLen != compareBytes.count { return false }
    for i in 0..<tokenLen {
        let c1 = UInt8(bitPattern: buffer[token.start + i])
        let c2 = compareBytes[i]
        if c1 != c2 {
            return false
        }
    }
    return true
}

/// Find the next token index after the current subtree
func nextTokenIndex(after current: Int, tokens: [JsmnToken]) -> Int {
    let currentEnd = tokens[current].end
    for i in (current + 1)..<tokens.count {
        if tokens[i].start > currentEnd {
            return i
        }
    }
    return tokens.count
}

// MARK: - Low-Level jsmn Test (No High-Level API)

public func debugRawTokens(jsonString: String) {
    print(">>> debugRawTokens")
    var parser = JsmnParser()
    EmbeddedJsmn.initParser(&parser)
    var tokens = [JsmnToken](repeating: JsmnToken(), count: 64)
    
    let utf8 = Array(jsonString.utf8CString)
    let result = utf8.withUnsafeBufferPointer { ptr -> Int in
        EmbeddedJsmn.parse(parser: &parser,
                           jsonBuffer: ptr.baseAddress!,
                           length: ptr.count - 1,
                           tokens: &tokens)
    }
    if result < 0 {
        print("debugRawTokens parse error code=\(result)")
        return
    }
    print("debugRawTokens parseCount=\(result)")
    
    // Dump all tokens
    for (i, tok) in tokens.enumerated() {
        if i >= result { break }
        if tok.type == .undefined && tok.start == -1 && tok.end == -1 {
            break
        }
        let ttype = tokenTypeName(tok.type)
        print("token[\(i)] type=\(ttype), start=\(tok.start), end=\(tok.end), size=\(tok.size)")
    }
}

/// Minimal helper for debugging token types
func tokenTypeName(_ t: JsmnType) -> String {
    switch t {
    case .undefined: return "undefined"
    case .object:    return "object"
    case .array:     return "array"
    case .string:    return "string"
    case .primitive: return "primitive"
    }
}

// MARK: - High-Level Helper

/// Skip the entire subtree of a token to prevent misenumeration
func skipSubtree(_ childIndex: Int, tokens: [JsmnToken]) -> Int {
    let childTok = tokens[childIndex]
    if childTok.type == .object || childTok.type == .array {
        var j = childIndex + 1
        for _ in 0..<childTok.size {
            if j >= tokens.count { break }
            if isDirectChild(childIndex: j, parentIndex: childIndex, tokens: tokens) {
                j = skipSubtree(j, tokens: tokens)
            }
        }
        return j
    }
    return childIndex + 1
}

// MARK: - Multiple Tests

public func testJSONParserSimple() {
    print(">>> testJSONParserSimple")
    let parser = JSONParser()
    let json = """
    {
      "brightness": 128
    }
    """
    let root = parser.parse(json)
    let brightness = root["brightness"].asInt() ?? -999
    print("testJSONParserSimple brightness=\(brightness)")
    print(">>> End testJSONParserSimple\n")
}

public func testJSONParserArray() {
    print(">>> testJSONParserArray")
    let parser = JSONParser()
    let json = """
    {
      "brightness": 128,
      "leds": [
        { "index":0, "r":255, "g":0, "b":0 },
        { "index":1, "r":0, "g":255, "b":0 },
        { "index":2, "r":0, "g":0, "b":255 }
      ]
    }
    """
    // Debug raw tokens first
    debugRawTokens(jsonString: json)
    
    let root = parser.parse(json)
    let brightness = root["brightness"].asInt() ?? -999
    print("testJSONParserArray brightness=\(brightness)")
    
    let ledsVal = root["leds"]
    let arrTok = ledsVal.tokens[ledsVal.index]
    let arrSize = arrTok.size
    print("testJSONParserArray leds array size=\(arrSize)")
    
    for i in 0..<arrSize {
        print("testJSONParserArray enumerating array index=\(i)")
        let item = ledsVal[i]
        if let idx = item["index"].asInt(),
           let rVal = item["r"].asInt(),
           let gVal = item["g"].asInt(),
           let bVal = item["b"].asInt() {
            let finalR = (rVal * brightness) % 256
            let finalG = (gVal * brightness) % 256
            let finalB = (bVal * brightness) % 256
            print("testJSONParserArray LED #\(i): index=\(idx), R=\(finalR), G=\(finalG), B=\(finalB)")
        } else {
            print("testJSONParserArray LED #\(i) parse fail")
        }
    }
    print(">>> End testJSONParserArray\n")
}

public func testJSONParserNested() {
    print(">>> testJSONParserNested")
    let parser = JSONParser()
    let json = """
    {
      "config": {
        "brightness": 100,
        "leds": [
          { "index":0, "r":50, "g":10, "b":0 },
          { "index":1, "r":0, "g":50, "b":10 }
        ],
        "someflag": true,
        "message": "Nested test"
      }
    }
    """
    debugRawTokens(jsonString: json)
    
    let root = parser.parse(json)
    let config = root["config"]
    let bright = config["brightness"].asInt() ?? -999
    print("testJSONParserNested brightness=\(bright)")
    
    let ledsVal = config["leds"]
    let arrTok = ledsVal.tokens[ledsVal.index]
    let arrSize = arrTok.size
    print("testJSONParserNested leds array size=\(arrSize)")
    
    for i in 0..<arrSize {
        print("testJSONParserNested enumerating leds array item \(i)")
        let item = ledsVal[i]
        if let idx = item["index"].asInt(),
           let rVal = item["r"].asInt(),
           let gVal = item["g"].asInt(),
           let bVal = item["b"].asInt() {
            print("testJSONParserNested LED #\(i): idx=\(idx), R=\(rVal), G=\(gVal), B=\(bVal)")
        } else {
            print("testJSONParserNested parse fail for item \(i)")
        }
    }
    
    let msg = config["message"].asString() ?? "<no msg>"
    print("testJSONParserNested message=\(msg)")
    print(">>> End testJSONParserNested\n")
}

// MARK: - Execute Tests

// Uncomment the following lines to run tests
/*
testJSONParserSimple()
testJSONParserArray()
testJSONParserNested()
*/

public func testJSONParserDeeplyNested() {
    print(">>> testJSONParserDeeplyNested")
    let parser = JSONParser()
    let json = """
    {
      "company": {
        "name": "Tech Corp",
        "employees": [
          {
            "id": 1,
            "name": "Alice",
            "roles": ["Developer", "Team Lead"],
            "details": {
              "age": 30,
              "contact": {
                "email": "alice@techcorp.com",
                "phone": "123-456-7890"
              }
            }
          },
          {
            "id": 2,
            "name": "Bob",
            "roles": ["Developer"],
            "details": {
              "age": 25,
              "contact": {
                "email": "bob@techcorp.com",
                "phone": "098-765-4321"
              }
            }
          }
        ],
        "locations": {
          "headquarters": {
            "address": "123 Tech Street",
            "city": "Innovate City",
            "country": "Futuristan"
          },
          "branch": {
            "address": "456 Innovation Ave",
            "city": "Create Town",
            "country": "Futuristan"
          }
        }
      }
    }
    """
    
    let root = parser.parse(json)
    
    // Extract company information
    let company = root["company"]
    let companyName = company["name"].asString() ?? "<no name>"
    
    // Extract employees
    let employees = company["employees"]
    let employeeCount = employees.tokens[employees.index].size
    print("Company Name: \(companyName)")
    print("Number of Employees: \(employeeCount)")
    
    for i in 0..<employeeCount {
        let employee = employees[i]
        let empId = employee["id"].asInt() ?? -1
        let empName = employee["name"].asString() ?? "<no name>"
        let rolesArray = employee["roles"]
        let rolesCount = rolesArray.tokens[rolesArray.index].size
        var roles: [String] = []
        for j in 0..<rolesCount {
            if let role = rolesArray[j].asString() {
                roles.append(role)
            }
        }
        let details = employee["details"]
        let age = details["age"].asInt() ?? -1
        let contact = details["contact"]
        let email = contact["email"].asString() ?? "<no email>"
        let phone = contact["phone"].asString() ?? "<no phone>"
        
        print("\nEmployee \(i + 1):")
        print("  ID: \(empId)")
        print("  Name: \(empName)")
        print("  Roles: \(roles)")
        print("  Age: \(age)")
        print("  Contact:")
        print("    Email: \(email)")
        print("    Phone: \(phone)")
    }
    
    // Extract locations
    let locations = company["locations"]
    let headquarters = locations["headquarters"]
    let hqAddress = headquarters["address"].asString() ?? "<no address>"
    let hqCity = headquarters["city"].asString() ?? "<no city>"
    let hqCountry = headquarters["country"].asString() ?? "<no country>"
    
    let branch = locations["branch"]
    let branchAddress = branch["address"].asString() ?? "<no address>"
    let branchCity = branch["city"].asString() ?? "<no city>"
    let branchCountry = branch["country"].asString() ?? "<no country>"
    
    print("\nLocations:")
    print("  Headquarters:")
    print("    Address: \(hqAddress)")
    print("    City: \(hqCity)")
    print("    Country: \(hqCountry)")
    print("  Branch:")
    print("    Address: \(branchAddress)")
    print("    City: \(branchCity)")
    print("    Country: \(branchCountry)")
    
    print(">>> End testJSONParserDeeplyNested\n")
}
