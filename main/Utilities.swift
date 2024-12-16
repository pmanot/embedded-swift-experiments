func floatToString(_ value: Float, decimals: Int32 = 2) -> String {
    var buffer = [CChar](repeating: 0, count: Int(FLOAT_STR_BUFFER_SIZE))
    float_to_str(&buffer, value, decimals)
    return String(cString: buffer)
}

func printArray(_ array: [String]) {
    var result: String = ""

    result += "["
    for (index, element) in array.enumerated() {
        result += element
        if !(index == array.count - 1) {
            result += ","
        }
    }
    result += "]"

    print(result)
}

func printArray(_ array: [Int]) {
    let strings = array.map { "\($0)" }
    printArray(strings)
}

func printArray(_ array: [Int32]) {
    printArray(array.map { Int($0) })
}

func printArray(_ array: [Float]) {
    let strings = array.map { floatToString($0) }
    printArray(strings)
}