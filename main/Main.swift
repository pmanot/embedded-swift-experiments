@_cdecl("app_main")
func main() {
    let jsonString = """
    {
        "top_level_array": ["a", "b", "c"],
        "nested": {
            "string_array": ["x", "y", "z"],
            "number_array": [1, 2, 3],
            "deep": {
                "more_strings": ["deep1", "deep2"],
                "mixed_data": {
                    "strings": ["mix1", "mix2"],
                    "numbers": [42, 43]
                }
            }
        },
        "siblings": {
            "sibling1": {
                "data": ["s1a", "s1b"]
            },
            "sibling2": {
                "data": ["s2a", "s2b"]
            }
        },
        "mixed_level": ["top1", "top2"],
        "complex": {
            "l1": {
                "l2": {
                    "l3": {
                        "deep_array": ["deep_a", "deep_b"]
                    }
                }
            }
        }
    }
    """

    if let json = parseJson(jsonString) {
        print("Testing top level array:")
        if let topArray = json["top_level_array"].asStringArray() {
            printArray(topArray)
        }
        
        print("Testing first level nested array:")
        if let nestedArray = json["nested"]["string_array"].asStringArray() {
            printArray(nestedArray)
        }
        
        print("Testing deep nested array:")
        if let deepArray = json["nested"]["deep"]["more_strings"].asStringArray() {
            printArray(deepArray)
        }
        
        print("Testing very deep array:")
        if let veryDeepArray = json["complex"]["l1"]["l2"]["l3"]["deep_array"].asStringArray() {
            printArray(veryDeepArray)
        }
        
        print("Testing sibling arrays:")
        if let sibling1 = json["siblings"]["sibling1"]["data"].asStringArray() {
            printArray(sibling1)
        }
        if let sibling2 = json["siblings"]["sibling2"]["data"].asStringArray() {
            printArray(sibling2)
        }
        
        print("Testing mixed data arrays:")
        if let mixedStrings = json["nested"]["deep"]["mixed_data"]["strings"].asStringArray() {
            printArray(mixedStrings)
        }
        if let mixedNumbers = json["nested"]["deep"]["mixed_data"]["numbers"].asIntArray() {
            printArray(mixedNumbers)
        }
    }
}