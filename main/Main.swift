@_cdecl("app_main")
func main() {
    let jsonString = """
    {
        "simple_array": ["first", "second", "third"],
        "nums": [1, 2, 3]
    }
    """
    
    if let json = parseJson(jsonString) {
        print("Testing array access...")
        
        // First let's try to enter the array and print its length
        if case .success(let count) = json["simple_array"].enterArray() {
            print("Array length: \(count)")
            
            // Try to get first element directly 
            do {
                let first = try json["simple_array"][0].cast(to: String.self)
                print("First element: \(first)")
            } catch {
                print("Failed to get first element using subscript and cast")
            }
            
            // Try using raw array access
            do {
                // First get into array context
                for i in 0..<Int(count) {
                    let element = try json["simple_array"][i].cast(to: String.self)
                    print("Element \(i): \(element)")
                }
            } catch {
                print("Failed in array iteration")
            }
            
            _ = json["simple_array"].leaveArray()
        } else {
            print("Failed to enter array")
        }
        
        // Test with numbers array
        if case .success(let numCount) = json["nums"].enterArray() {
            print("Numbers array length: \(numCount)")
            
            do {
                let firstNum = try json["nums"][0].cast(to: Int32.self)
                print("First number: \(firstNum)")
            } catch {
                print("Failed to get first number")
            }
            
            _ = json["nums"].leaveArray()
        }
    } else {
        print("Failed to parse JSON")
    }
}