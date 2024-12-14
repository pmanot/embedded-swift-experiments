// JsonParser.swift

public enum JsonError: Int32, Error {
    case fail = -1
    case success = 0

    init(code: Int32) {
        self = code == 0 ? .success : .fail
    }
}

public struct JsonContext {
    private var ctx: jparse_ctx_t
    private var valid: Bool

    public init(jsonString: String) {
        ctx = jparse_ctx_t()
        valid = false

        // Get C string pointer and length
        jsonString.withCString { ptr in
            var len: Int32 = 0
            while ptr[Int(len)] != 0 {
                len += 1
            }
            let result = json_parse_start(&ctx, ptr, len)
            valid = result == OS_SUCCESS
        }
    }

    public func isValid() -> Bool {
        return valid
    }

    public mutating func getString(key: UnsafePointer<CChar>, maxLength: Int32) -> Result<
        String, JsonError
    > {
        var buffer = [CChar](repeating: 0, count: Int(maxLength))
        let result = json_obj_get_string(&ctx, key, &buffer, maxLength)
        if result == OS_SUCCESS {
            return .success(String(cString: buffer))
        }
        return .failure(.fail)
    }

    public mutating func getInt(key: UnsafePointer<CChar>) -> Result<Int32, JsonError> {
        var value: Int32 = 0
        let result = json_obj_get_int(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public mutating func getFloat(key: UnsafePointer<CChar>) -> Result<Float, JsonError> {
        var value: Float = 0.0
        let result = json_obj_get_float(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public mutating func getBool(key: UnsafePointer<CChar>) -> Result<Bool, JsonError> {
        var value: Bool = false
        let result = json_obj_get_bool(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public mutating func enterObject(key: UnsafePointer<CChar>) -> Bool {
        return json_obj_get_object(&ctx, key) == OS_SUCCESS
    }

    public mutating func leaveObject() -> Bool {
        return json_obj_leave_object(&ctx) == OS_SUCCESS
    }

    public mutating func enterArray(key: UnsafePointer<CChar>) -> Result<Int32, JsonError> {
        var count: Int32 = 0
        let result = json_obj_get_array(&ctx, key, &count)
        if result == OS_SUCCESS {
            return .success(count)
        }
        return .failure(.fail)
    }

    public mutating func leaveArray() -> Bool {
        return json_obj_leave_array(&ctx) == OS_SUCCESS
    }

    public mutating func getArrayString(index: UInt32, maxLength: Int32) -> Result<
        String, JsonError
    > {
        var buffer = [CChar](repeating: 0, count: Int(maxLength))
        let result = json_arr_get_string(&ctx, index, &buffer, maxLength)
        if result == OS_SUCCESS {
            return .success(String(cString: buffer))
        }
        return .failure(.fail)
    }

    public mutating func getArrayInt(index: UInt32) -> Result<Int32, JsonError> {
        var value: Int32 = 0
        let result = json_arr_get_int(&ctx, index, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public mutating func cleanup() {
        json_parse_end(&ctx)
    }
}

// JsonWrapper.swift

public class JsonValue {
    private var parser: JsonContext
    private var currentPath: [(type: PathType, value: String)]
    private let maxStringLength: Int32 = 256  // Configurable max string length

    private enum PathType {
        case key
        case index
    }

    private enum ValueError: Error {
        case invalidPath
        case invalidType
        case parserError
    }

    init(parser: JsonContext) {
        self.parser = parser
        self.currentPath = []
    }

    // Subscript for string keys
    public subscript(key: String) -> JsonValue {
        get {
            var newPath = currentPath
            newPath.append((.key, key))
            let newValue = JsonValue(parser: parser)
            newValue.currentPath = newPath
            return newValue
        }
    }

    // Subscript for integer indices
    public subscript(index: Int) -> JsonValue {
        get {
            // Instead of appending to path, we should execute the array access immediately
            var mutableParser = parser
            
            // First get to the array using our current path
            for (type, value) in currentPath {
                switch type {
                case .key:
                    value.withCString { key in
                        _ = mutableParser.enterObject(key: key)
                    }
                case .index:
                    // shouldn't happen when accessing array elements
                    break
                }
            }
            
            // Create new value with the current parser state
            let newValue = JsonValue(parser: mutableParser)
            newValue.currentPath = currentPath
            // Add the index to track that this is an array access
            newValue.currentPath.append((.index, String(index)))
            return newValue
        }
    }


    // Type conversion methods
    public func asString() -> Result<String, JsonError> {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath.dropLast() {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        // Get the final value
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .key:
                return lastPath.value.withCString { key in
                    mutableParser.getString(key: key, maxLength: maxStringLength)
                }
            case .index:
                if let idx = UInt32(lastPath.value) {
                    return mutableParser.getArrayString(index: idx, maxLength: maxStringLength)
                }
            }
        }

        return .failure(.fail)
    }

    public func asInt() -> Result<Int32, JsonError> {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath.dropLast() {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        // Get the final value
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .key:
                return lastPath.value.withCString { key in
                    mutableParser.getInt(key: key)
                }
            case .index:
                if let idx = UInt32(lastPath.value) {
                    return mutableParser.getArrayInt(index: idx)
                }
            }
        }

        return .failure(.fail)
    }

    public func asFloat() -> Result<Float, JsonError> {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath.dropLast() {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        // Get the final value
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .key:
                return lastPath.value.withCString { key in
                    mutableParser.getFloat(key: key)
                }
            case .index:
                return .failure(.fail)  // Arrays don't support float values in current implementation
            }
        }

        return .failure(.fail)
    }

    public func asBool() -> Result<Bool, JsonError> {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath.dropLast() {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        // Get the final value
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .key:
                return lastPath.value.withCString { key in
                    mutableParser.getBool(key: key)
                }
            case .index:
                return .failure(.fail)  // Arrays don't support boolean values in current implementation
            }
        }

        return .failure(.fail)
    }

    // Array methods
    public func enterArray() -> Result<Int32, JsonError> {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        // Get array length
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .key:
                return lastPath.value.withCString { key in
                    mutableParser.enterArray(key: key)
                }
            case .index:
                return .failure(.fail)  // Can't enter array at array index
            }
        }

        return .failure(.fail)
    }

    public func leaveArray() -> Bool {
        var mutableParser = parser

        // Navigate to the correct path
        for (type, value) in currentPath {
            switch type {
            case .key:
                value.withCString { key in
                    if !mutableParser.enterObject(key: key) {
                        return
                    }
                }
            case .index:
                if let idx = Int32(value) {
                    _ = mutableParser.enterArray(key: value)
                }
            }
        }

        return mutableParser.leaveArray()
    }
}


extension JsonValue {
        public func cast(to: String.Type) throws(JsonError) -> String {
        var mutableParser = parser
        
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .index:
                // We need to:
                // 1. Enter the array at the parent path
                // 2. Get the element at the index
                let parentPath = Array(currentPath.dropLast())
                for (type, value) in parentPath {
                    switch type {
                    case .key:
                        value.withCString { key in
                            _ = mutableParser.enterObject(key: key)
                        }
                    case .index:
                        // Shouldn't happen for array access
                        break
                    }
                }
                
                // Now enter the array at the parent path
                if let parentKey = parentPath.last?.value {
                    if case .success(let _) = parentKey.withCString({ key in
                        mutableParser.enterArray(key: key)
                    }) {
                        // Now we can get the array element
                        if let idx = UInt32(lastPath.value) {
                            if case .success(let str) = mutableParser.getArrayString(index: idx, maxLength: maxStringLength) {
                                return str
                            }
                        }
                    }
                }
            case .key:
                // Normal string access
                if case .success(let value) = asString() {
                    return value
                }
            }
        }
        throw JsonError.fail
    }

    public func cast(to: Int32.Type) throws(JsonError) -> Int32 {
        var mutableParser = parser
        
        if let lastPath = currentPath.last {
            switch lastPath.type {
            case .index:
                let parentPath = Array(currentPath.dropLast())
                for (type, value) in parentPath {
                    switch type {
                    case .key:
                        value.withCString { key in
                            _ = mutableParser.enterObject(key: key)
                        }
                    case .index:
                        break
                    }
                }
                
                if let parentKey = parentPath.last?.value {
                    if case .success(let _) = parentKey.withCString({ key in
                        mutableParser.enterArray(key: key)
                    }) {
                        if let idx = UInt32(lastPath.value) {
                            if case .success(let num) = mutableParser.getArrayInt(index: idx) {
                                return num
                            }
                        }
                    }
                }
            case .key:
                if case .success(let value) = asInt() {
                    return value
                }
            }
        }
        throw JsonError.fail
    }
    
    public func cast(to: Float.Type) throws(JsonError) -> Float {
        if case .success(let value) = asFloat() {
            return value
        }
        throw JsonError.fail
    }

    public func cast(to: Bool.Type) throws(JsonError) -> Bool {
        if case .success(let value) = asBool() {
            return value
        }
        throw JsonError.fail
    }
}


// Factory function to create a JSON wrapper
public func parseJson(_ jsonString: String) -> JsonValue? {
    let parser = JsonContext(jsonString: jsonString)
    if parser.isValid() {
        return JsonValue(parser: parser)
    }
    return nil
}
