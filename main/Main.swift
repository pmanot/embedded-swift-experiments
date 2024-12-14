@_cdecl("app_main")
func main() {
    do {
        let ledStrip = LedStrip(gpioPin: 6, maxLeds: 12)
        let network = Network()

        // Connect to the network
        guard try network.connect(.act) else {
            print("Connection failed")
            return
        }

        // Retrieve and display the IP address
        if let ip = try? network.ipAddress() {
            print("Connected: \(ip)")
        } else {
            print("Failed to retrieve IP address")
            return
        }

        // Start the HTTP server
        let server = HTTPServer()
        guard server.start() == nil else {
            print("Server start failed")
            return
        }

        // Register the POST /led route
        server.register(
            Route(path: "/led", method: .post) { requestBody in
                let parser = JSONParser()
                let root = parser.parse(requestBody)

                ledStrip.clear()
                let brightness = root["brightness"].asInt() ?? 128
                let ledsValue = root["leds"]

                var ledUpdates: [(index: Int, color: LedStrip.Color)] = []
                guard let ledsCount = ledsValue.arrayCount() else {
                    print("Invalid LEDs array.")
                    return .failure
                }

                for j in 0..<ledsCount {
                    let ledItem = ledsValue[j]
                    
                    guard
                        let ledIndex = ledItem["index"].asInt(),
                        let rVal = ledItem["r"].asInt(),
                        let gVal = ledItem["g"].asInt(),
                        let bVal = ledItem["b"].asInt()
                    else {
                        print("Failed to parse LED item at array index \(j)")
                        continue
                    }

                    guard (0..<12).contains(ledIndex) else {
                        print("LED index \(ledIndex) out of range (0-11). Skipping.")
                        continue
                    }

                    let finalR = min(max((rVal * brightness) / 255, 0), 255)
                    let finalG = min(max((gVal * brightness) / 255, 0), 255)
                    let finalB = min(max((bVal * brightness) / 255, 0), 255)

                    let color = LedStrip.Color(r: finalR, g: finalG, b: finalB)
                    ledUpdates.append((index: ledIndex, color: color))
                }

                for update in ledUpdates {
                    ledStrip.setPixel(index: update.index, color: update.color)
                }

                ledStrip.refresh()
                print("LED strip updated with brightness \(brightness) and \(ledUpdates.count) LEDs.")
                return .success(response: "OK")
            }
        )

        // Register the POST /animation route
        server.register(
            Route(path: "/animation", method: .post) { requestBody in
                let parser = JSONParser()
                let root = parser.parse(requestBody)
                
                guard let framesCount = root["frames"].arrayCount() else {
                    print("Invalid frames array.")
                    return .failure
                }

                for i in 0..<framesCount {
                    let frame = root["frames"][i]
                    let delayMs = frame["delayMs"].asInt() ?? 0
                    let ledsValue = frame["leds"]

                    guard let ledsCount = ledsValue.arrayCount() else {
                        print("Invalid LEDs array in frame \(i).")
                        continue
                    }

                    ledStrip.clear()
                    
                    var ledUpdates: [(index: Int, color: LedStrip.Color)] = []
                    print("COUNT: \(ledsCount)")
                    for j in 0..<ledsCount {
                        let ledItem = ledsValue[j]
                        
                        guard
                            let ledIndex = ledItem["index"].asInt(),
                            let rVal = ledItem["r"].asInt(),
                            let gVal = ledItem["g"].asInt(),
                            let bVal = ledItem["b"].asInt()
                        else {
                            print("Failed to parse LED item at frame \(i), array index \(j)")
                            continue
                        }

                        guard (0..<12).contains(ledIndex) else {
                            print("LED index \(ledIndex) out of range (0-11). Skipping.")
                            continue
                        }

                        let color = LedStrip.Color(r: rVal, g: gVal, b: bVal)
                        ledUpdates.append((index: ledIndex, color: color))
                    }
                    
                    for update in ledUpdates {
                        ledStrip.setPixel(index: update.index, color: update.color)
                    }
                    
                    ledStrip.refresh()
                    print("Frame \(i) displayed for \(delayMs) ms.")
                    vTaskDelay(UInt32(delayMs) / (1000 / UInt32(configTICK_RATE_HZ)))
                }

                return .success(response: "Animation played.")
            }
        )

        // Idle loop
        while true {
            vTaskDelay(500 / (1000 / UInt32(configTICK_RATE_HZ)))
        }
    } catch {
        print("Error: \(error)")
    }
}


func testAnimationJSONParsing() {
    // Sample JSON payload matching the expected schema
    let jsonString = """
    {
        "frames": [
            {
                "delayMs": 300,
                "leds": [
                    { "index": 0, "r": 255, "g": 0, "b": 0 },
                    { "index": 1, "r": 0, "g": 255, "b": 0 }
                ]
            },
            {
                "delayMs": 300,
                "leds": [
                    { "index": 2, "r": 0, "g": 0, "b": 255 },
                    { "index": 3, "r": 255, "g": 255, "b": 0 }
                ]
            },
            {
                "delayMs": 500,
                "leds": [
                    { "index": 0, "r": 0, "g": 255, "b": 0 },
                    { "index": 1, "r": 0, "g": 0, "b": 255 },
                    { "index": 2, "r": 255, "g": 0, "b": 0 },
                    { "index": 3, "r": 255, "g": 255, "b": 255 }
                ]
            },
            {
                "delayMs": 700,
                "leds": [
                    { "index": 0, "r": 128, "g": 0, "b": 128 },
                    { "index": 1, "r": 0, "g": 128, "b": 128 },
                    { "index": 2, "r": 128, "g": 128, "b": 0 },
                    { "index": 3, "r": 64, "g": 64, "b": 64 }
                ]
            },
            {
                "delayMs": 1000,
                "leds": [
                    { "index": 0, "r": 255, "g": 255, "b": 255 },
                    { "index": 1, "r": 0, "g": 0, "b": 0 },
                    { "index": 2, "r": 255, "g": 255, "b": 255 },
                    { "index": 3, "r": 0, "g": 0, "b": 0 }
                ]
            }
        ]
    }
    """

    // Initialize the JSON parser
    let parser = JSONParser()
    let root = parser.parse(jsonString)

    // Check if parsing was successful
    if root.parseError < 0 {
        print("Failed to parse JSON. Error code: \(root.parseError)")
        return
    }

    // Access the "frames" array
    let framesValue = root["frames"]

    // Validate that "frames" is an array
    guard let framesCount = framesValue.arrayCount() else {
        print("Invalid frames array.")
        return
    }

    print("Number of frames: \(framesCount)\n")

    // Iterate through each frame
    for frameIndex in 0..<framesCount {
        let frame = framesValue[frameIndex]

        // Retrieve delayMs
        let delayMs = frame["delayMs"].asInt() ?? 0

        // Access the "leds" array within the frame
        let ledsValue = frame["leds"]

        // Validate that "leds" is an array
        guard let ledsCount = ledsValue.arrayCount() else {
            print("Invalid LEDs array in frame \(frameIndex).")
            continue
        }

        print("Frame \(frameIndex + 1): Delay = \(delayMs) ms, LEDs Count = \(ledsCount)")

        // Iterate through each LED in the frame
        for ledIndex in 0..<ledsCount {
            let ledItem = ledsValue[ledIndex]

            // Parse LED properties
            guard
                let index = ledItem["index"].asInt(),
                let r = ledItem["r"].asInt(),
                let g = ledItem["g"].asInt(),
                let b = ledItem["b"].asInt()
            else {
                print("  Failed to parse LED item at frame \(frameIndex + 1), LED \(ledIndex + 1).")
                continue
            }

            print("  LED \(ledIndex + 1): Index = \(index), R = \(r), G = \(g), B = \(b)")
        }

        print("") // Add an empty line for readability
    }

    print("JSON parsing test completed successfully.")
}
