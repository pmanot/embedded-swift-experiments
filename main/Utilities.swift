func floatToString(_ value: Float, decimals: Int32 = 2) -> String {
    var buffer = [CChar](repeating: 0, count: Int(FLOAT_STR_BUFFER_SIZE))
    float_to_str(&buffer, value, decimals)
    return String(cString: buffer)
}