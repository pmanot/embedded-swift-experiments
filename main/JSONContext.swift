public class JSONContext {
    private var ctx: jparse_ctx_t
    private var valid: Bool

    public init(jsonString: String) {
        ctx = jparse_ctx_t()
        valid = false

        jsonString.withCString { ptr in
            var len: Int32 = 0
            while ptr[Int(len)] != 0 {
                len += 1
            }
            let result = json_parse_start(&ctx, ptr, len)
            valid = result == OS_SUCCESS
            print("Init result: valid=")
            print(valid)
        }
    }

    public func isValid() -> Bool {
        return valid
    }

    public func getString(key: UnsafePointer<CChar>, maxLength: Int32) -> Result<String, JSONError> {
        var buffer = [CChar](repeating: 0, count: Int(maxLength))
        let result = json_obj_get_string(&ctx, key, &buffer, maxLength)
        if result == OS_SUCCESS {
            return .success(String(cString: buffer))
        }
        return .failure(.fail)
    }

    public func getInt(key: UnsafePointer<CChar>) -> Result<Int32, JSONError> {
        var value: Int32 = 0
        let result = json_obj_get_int(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public func getFloat(key: UnsafePointer<CChar>) -> Result<Float, JSONError> {
        var value: Float = 0.0
        let result = json_obj_get_float(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public func getBool(key: UnsafePointer<CChar>) -> Result<Bool, JSONError> {
        var value: Bool = false
        let result = json_obj_get_bool(&ctx, key, &value)
        if result == OS_SUCCESS {
            return .success(value)
        }
        return .failure(.fail)
    }

    public func enterObject(key: UnsafePointer<CChar>) -> Bool {
        print("Entering object")
        let result = json_obj_get_object(&ctx, key) == OS_SUCCESS
        print("Enter object result:")
        print(result)
        return result
    }

    public func leaveObject() -> Bool {
        print("Leaving object")
        let result = json_obj_leave_object(&ctx) == OS_SUCCESS
        print("Leave object result:")
        print(result)
        return result
    }

    public func enterArray(key: UnsafePointer<CChar>) -> Result<Int32, JSONError> {
        print("Entering array")
        var count: Int32 = 0
        let result = json_obj_get_array(&ctx, key, &count)
        print("Enter array result:")
        print(result == OS_SUCCESS)
        print("Array count:")
        print(count)
        if result == OS_SUCCESS {
            return .success(count)
        }
        return .failure(.fail)
    }

    public func leaveArray() -> Bool {
        print("Leaving array")
        let result = json_obj_leave_array(&ctx) == OS_SUCCESS
        print("Leave array result:")
        print(result)
        return result
    }

    public func getArrayString(index: UInt32, maxLength: Int32) -> Result<String, JSONError> {
        print("Getting array string at index:")
        print(index)
        var buffer = [CChar](repeating: 0, count: Int(maxLength))
        let result = json_arr_get_string(&ctx, index, &buffer, maxLength)
        print("Get array string result:")
        print(result == OS_SUCCESS)
        if result == OS_SUCCESS {
            return .success(String(cString: buffer))
        }
        return .failure(.fail)
    }

    public func getArrayInt(index: UInt32) -> Result<Int32, JSONError> {
        print("Getting array int at index:")
        print(index)
        var value: Int32 = 0
        let result = json_arr_get_int(&ctx, index, &value)
        print("Get array int result:")
        print(result == OS_SUCCESS)
        if result == OS_SUCCESS {
            print("Array int value:")
            print(value)
            return .success(value)
        }
        return .failure(.fail)
    }

    public func cleanup() {
        json_parse_end(&ctx)
    }

    deinit {
        cleanup()
    }
}

extension JSONContext {
    public func getStringArray(key: UnsafePointer<CChar>, maxLength: Int32) -> Result<[String], JSONError> {
    // First get array length
    var count: Int32 = 0
    guard json_obj_get_array(&ctx, key, &count) == OS_SUCCESS else {
        return .failure(.fail)
    }
    
    // Get all strings
    var result: [String] = []
    for i in 0..<count {
        var buffer = [CChar](repeating: 0, count: Int(maxLength))
        if json_arr_get_string(&ctx, UInt32(i), &buffer, maxLength) == OS_SUCCESS {
            result.append(String(cString: buffer))
        } else {
            _ = json_obj_leave_array(&ctx)
            return .failure(.fail)
        }
    }
    
    // Clean up
    _ = json_obj_leave_array(&ctx)
    return .success(result)
}

public func getIntArray(key: UnsafePointer<CChar>) -> Result<[Int32], JSONError> {
    // First get array length
    var count: Int32 = 0
    guard json_obj_get_array(&ctx, key, &count) == OS_SUCCESS else {
        return .failure(.fail)
    }
    
    // Get all integers
    var result: [Int32] = []
    for i in 0..<count {
        var value: Int32 = 0
        if json_arr_get_int(&ctx, UInt32(i), &value) == OS_SUCCESS {
            result.append(value)
        } else {
            _ = json_obj_leave_array(&ctx)
            return .failure(.fail)
        }
    }
    
    // Clean up
    _ = json_obj_leave_array(&ctx)
    return .success(result)
}
}