// JsonParser.swift

public enum JSONError: Int32, Error {
    case fail = -1
    case success = 0

    init(code: Int32) {
        self = code == 0 ? .success : .fail
    }
}

public class JSONValue {
    private let parser: JSONContext
    private var currentPath: [(type: PathType, value: String)]
    private let maxStringLength: Int32 = 256

    private enum PathType {
        case key
        case index
    }

    init(parser: JSONContext) {
        self.parser = parser
        self.currentPath = []
    }

    public subscript(key: String) -> JSONValue {
        get {
            var newPath = currentPath
            newPath.append((.key, key))
            let newValue = JSONValue(parser: parser)
            newValue.currentPath = newPath
            return newValue
        }
    }

    public subscript(index: Int) -> JSONValue {
        get {
            print("Array access at index:")
            print(index)
            let newValue = JSONValue(parser: parser)
            newValue.currentPath = currentPath
            newValue.currentPath.append((.index, String(index)))
            return newValue
        }
    }

    public func cast(to: String.Type) -> String? {
        guard let lastPath = currentPath.last else {
            return nil
        }

        switch lastPath.type {
        case .index:
            if let parentKey = currentPath.dropLast().last?.value {
                return parentKey.withCString { key in
                    if case .success(_) = parser.enterArray(key: key) {
                        if let idx = UInt32(lastPath.value) {
                            if case .success(let str) = parser.getArrayString(
                                index: idx, maxLength: maxStringLength)
                            {
                                _ = parser.leaveArray()
                                return str
                            }
                        }
                    }
                    return nil
                }
            }

        case .key:
            return lastPath.value.withCString { key in
                if case .success(let value) = parser.getString(key: key, maxLength: maxStringLength)
                {
                    return value
                }
                return nil
            }
        }

        return nil
    }

    public func cast(to: Int32.Type) -> Int32? {
        guard let lastPath = currentPath.last else {
            return nil
        }

        switch lastPath.type {
        case .index:
            if let parentKey = currentPath.dropLast().last?.value {
                return parentKey.withCString { key in
                    if case .success(_) = parser.enterArray(key: key) {
                        if let idx = UInt32(lastPath.value) {
                            if case .success(let num) = parser.getArrayInt(index: idx) {
                                _ = parser.leaveArray()
                                return num
                            }
                        }
                    }
                    return nil
                }
            }

        case .key:
            return lastPath.value.withCString { key in
                if case .success(let value) = parser.getInt(key: key) {
                    return value
                }
                return nil
            }
        }

        return nil
    }

    public func cast(to: Float.Type) -> Float? {
        guard let lastPath = currentPath.last else {
            return nil
        }

        if case .key = lastPath.type {
            return lastPath.value.withCString { key in
                if case .success(let value) = parser.getFloat(key: key) {
                    return value
                }
                return nil
            }
        }
        return nil
    }

    public func cast(to: Bool.Type) -> Bool? {
        guard let lastPath = currentPath.last else {
            return nil
        }

        if case .key = lastPath.type {
            return lastPath.value.withCString { key in
                if case .success(let value) = parser.getBool(key: key) {
                    return value
                }
                return nil
            }
        }
        return nil
    }

    public func enterArray() -> Result<Int32, JSONError> {
        guard let lastPath = currentPath.last else {
            return .failure(.fail)
        }

        if case .key = lastPath.type {
            return lastPath.value.withCString { key in
                parser.enterArray(key: key)
            }
        }
        return .failure(.fail)
    }

    public func leaveArray() -> Bool {
        return parser.leaveArray()
    }
}

public func parseJson(_ jsonString: String) -> JSONValue? {
    let parser = JSONContext(jsonString: jsonString)
    if parser.isValid() {
        return JSONValue(parser: parser)
    }
    return nil
}

extension JSONValue {
    private func navigateToParent() -> Bool {
        // Skip the last element since that's what we're trying to access
        let pathToParent = Array(currentPath.dropLast())
        
        for (type, value) in pathToParent {
            switch type {
            case .key:
                let success = value.withCString { key in
                    parser.enterObject(key: key)
                }
                if !success {
                    return false
                }
            case .index:
                // We don't support arrays of arrays yet
                return false
            }
        }
        return true
    }

    public func asStringArray() -> [String]? {
        guard let lastPath = currentPath.last, case .key = lastPath.type else {
            return nil
        }
        
        // First navigate to parent objects
        if !navigateToParent() {
            return nil
        }
        
        let result = lastPath.value.withCString { key in
            parser.getStringArray(key: key, maxLength: maxStringLength)
        }
        
        // Leave all objects we entered
        for _ in currentPath.dropLast() {
            _ = parser.leaveObject()
        }
        
        if case .success(let array) = result {
            return array
        }
        return nil
    }

    public func asIntArray() -> [Int32]? {
        guard let lastPath = currentPath.last, case .key = lastPath.type else {
            return nil
        }
        
        // First navigate to parent objects
        if !navigateToParent() {
            return nil
        }
        
        let result = lastPath.value.withCString { key in
            parser.getIntArray(key: key)
        }
        
        // Leave all objects we entered
        for _ in currentPath.dropLast() {
            _ = parser.leaveObject()
        }
        
        if case .success(let array) = result {
            return array
        }
        return nil
    }
}