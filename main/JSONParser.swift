// MARK: - High-Level Swift API

public enum JSONErrorCode: Int {
    case parseError = -1
    case invalidKey = -2
}

/// A high-level JSON parser wrapping our JSMN parser & tokens
public final class JSONParser {
    private let initialTokenCount = 4096
    private let maxTokenCount = 8192

    public func parse(_ jsonString: String) -> JSONValue {
        let utf8 = Array(jsonString.utf8CString)
        var parser = JSMNParser()
        EmbeddedJSMN.initParser(&parser)
        var tokens = [JSMNToken](repeating: JSMNToken(), count: initialTokenCount)
        var currentTokenCount = initialTokenCount
        var result: Int

        repeat {
            result = utf8.withUnsafeBufferPointer { ptr -> Int in
                EmbeddedJSMN.parse(
                    parser: &parser,
                    jsonBuffer: ptr.baseAddress!,
                    length: ptr.count - 1,
                    tokens: &tokens)
            }

            if result == JSMNErr.nomem.rawValue {
                // Not enough tokens; attempt to increase the token array size
                if currentTokenCount >= maxTokenCount {
                    // Exceeded maximum token allocation; fail gracefully
                    return JSONValue(tokens: tokens, buffer: utf8, index: -1, parseError: result)
                }
                currentTokenCount *= 2
                print("expanding token count \(currentTokenCount)")

                tokens = [JSMNToken](repeating: JSMNToken(), count: currentTokenCount)
            }
        } while result == JSMNErr.nomem.rawValue

        if result < 0 {
            return JSONValue(tokens: tokens, buffer: utf8, index: -1, parseError: result)
        }

        return JSONValue(tokens: tokens, buffer: utf8, index: 0, parseError: 0)
    }

}

/// A chainable JSONValue with subscript for objects/arrays
public struct JSONValue {
    internal let tokens: [JSMNToken]
    internal let buffer: [CChar]
    internal let index: Int
    internal let parseError: Int  // store negative error code or 0 if success

    public init(tokens: [JSMNToken], buffer: [CChar], index: Int, parseError: Int) {
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

    /// Returns the number of items in an array, or nil if not an array
    public func arrayCount() -> Int? {
        if parseError < 0 { return nil }
        if !isValid() { return nil }

        let tok = tokens[index]
        if tok.type != .array { return nil }
        return tok.size
    }

    /// Subscript for object key
    public subscript(key: String) -> JSONValue {
        if parseError < 0 {
            // Existing parse error
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: parseError)
        }
        guard isValid() else {
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.parseError.rawValue)
        }
        let tok = tokens[index]
        if tok.type != .object {
            // Not an object
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.parseError.rawValue)
        }

        if let childKeyIndex = findKey(key, objectIndex: index, tokens: tokens, buffer: buffer) {
            let valIndex = childKeyIndex + 1
            if valIndex < tokens.count {
                return JSONValue(tokens: tokens, buffer: buffer, index: valIndex, parseError: 0)
            } else {
                return JSONValue(
                    tokens: tokens, buffer: buffer, index: -1,
                    parseError: JSONErrorCode.invalidKey.rawValue)
            }
        } else {
            // Key not found
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.invalidKey.rawValue)
        }
    }

    /// Subscript for array index
    public subscript(idx: Int) -> JSONValue {
        if parseError < 0 {
            // Existing parse error
            return JSONValue(tokens: tokens, buffer: buffer, index: -1, parseError: parseError)
        }
        guard isValid() else {
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.parseError.rawValue)
        }
        let arrTok = tokens[index]
        if arrTok.type != .array {
            // Not an array
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.parseError.rawValue)
        }

        guard let arrSize = arrayCount() else {
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.parseError.rawValue)
        }

        if idx >= arrSize {
            // Array index out of range
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.invalidKey.rawValue)
        }

        // Find the token index for the requested array element
        var j = index + 1
        var currentIdx = 0
        var childIndex = -1

        while j < tokens.count && currentIdx < arrSize {
            let tok = tokens[j]
            if isDirectChild(childIndex: j, parentIndex: index, tokens: tokens) {
                if currentIdx == idx {
                    childIndex = j
                    break
                }
                // Move to next token after current child subtree
                j = nextTokenIndex(after: j, tokens: tokens)
                currentIdx += 1
            } else {
                j += 1
            }
        }

        if childIndex == -1 {
            // Array index not found
            return JSONValue(
                tokens: tokens, buffer: buffer, index: -1,
                parseError: JSONErrorCode.invalidKey.rawValue)
        }

        return JSONValue(tokens: tokens, buffer: buffer, index: childIndex, parseError: 0)
    }

    /// Attempt to read as integer if type == .primitive
    public func asInt() -> Int? {
        if parseError < 0 { return nil }
        if !isValid() { return nil }

        let tok = tokens[index]
        if tok.type != .primitive {
            return nil
        }
        let length = tok.end - tok.start
        if length <= 0 {
            return nil
        }
        var localBuf = [CChar](repeating: 0, count: length + 1)
        for j in 0..<length {
            localBuf[j] = buffer[tok.start + j]
        }
        localBuf[length] = 0
        let s = String(cString: localBuf)
        return Int(s)
    }

    /// If type == .string or .primitive, interpret as string
    public func asString() -> String? {
        if parseError < 0 { return nil }
        if !isValid() { return nil }

        let tok = tokens[index]
        if tok.type != .string && tok.type != .primitive {
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
        return s
    }
}

// MARK: - Helper Functions

/// Find a key named `keyName` in the object at `objectIndex`. Return token index if found, else nil.
func findKey(
    _ keyName: String,
    objectIndex: Int,
    tokens: [JSMNToken],
    buffer: [CChar]
) -> Int? {
    let objTok = tokens[objectIndex]
    if objTok.type != .object {
        return nil
    }

    var i = objectIndex + 1
    while i < tokens.count {
        let t = tokens[i]
        if t.start >= objTok.end { break }
        if isDirectChild(childIndex: i, parentIndex: objectIndex, tokens: tokens),
            t.type == .string
        {
            if substringEquals(token: t, buffer: buffer, compare: keyName) {
                return i
            }
        }
        i += 1
    }
    return nil
}

/// Check if `childIndex` is a direct child of `parentIndex`
func isDirectChild(childIndex: Int, parentIndex: Int, tokens: [JSMNToken]) -> Bool {
    let parent = tokens[parentIndex]
    let child = tokens[childIndex]
    if parent.end == -1 { return false }
    return child.start >= parent.start && child.end <= parent.end
}

/// Compare substring in `token` with `compare` string
func substringEquals(token: JSMNToken, buffer: [CChar], compare: String) -> Bool {
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
func nextTokenIndex(after current: Int, tokens: [JSMNToken]) -> Int {
    let currentEnd = tokens[current].end
    for i in (current + 1)..<tokens.count {
        if tokens[i].start > currentEnd {
            return i
        }
    }
    return tokens.count
}

// MARK: - High-Level Tests

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
    // Debug raw tokens removed

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
            let bVal = item["b"].asInt()
        {
            let finalR = (rVal * brightness) % 256
            let finalG = (gVal * brightness) % 256
            let finalB = (bVal * brightness) % 256
            print(
                "testJSONParserArray LED #\(i): index=\(idx), R=\(finalR), G=\(finalG), B=\(finalB)"
            )
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
    // Debug raw tokens removed

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
            let bVal = item["b"].asInt()
        {
            print("testJSONParserNested LED #\(i): idx=\(idx), R=\(rVal), G=\(gVal), B=\(bVal)")
        } else {
            print("testJSONParserNested parse fail for item \(i)")
        }
    }

    let msg = config["message"].asString() ?? "<no msg>"
    print("testJSONParserNested message=\(msg)")
    print(">>> End testJSONParserNested\n")
}

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

        print("  Roles:")
        for role in roles {
            print(role)
        }
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

// MARK: - Execute Tests

// Uncomment the following lines to run tests
/*
testJSONParserSimple()
testJSONParserArray()
testJSONParserNested()
testJSONParserDeeplyNested()
*/

extension JSONValue {
    public func tokenDebugType() -> String {
        if index < 0 || index >= tokens.count {
            return "invalid"
        }
        switch tokens[index].type {
        case .undefined:
            return "undefined"
        case .object:
            return "object"
        case .array:
            return "array"
        case .string:
            return "string"
        case .primitive:
            return "primitive"
        }
    }
}
