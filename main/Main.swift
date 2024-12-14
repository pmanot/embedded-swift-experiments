/*
@_cdecl("app_main")
func main() {
  do {
    let ledStrip = LedStrip(gpioPin: 6, maxLeds: 12)
    let network = Network()

    // Simple test debug, or remove if desired
    testJson()

    guard try network.connect(.act) == true else {
      print("Connection failed")
      return
    }

    if let ip = try? network.ipAddress() {
      print("Connected: \(ip)")
    } else {
      print("Failed to retrieve IP address")
      return
    }

    let server = HTTPServer()
    guard server.start() == nil else {
      print("Server start failed")
      return
    }

    // POST /led expects nested JSON with "brightness" and an array "leds"
    server.register(
      Route(path: "/led", method: .post) { requestBody in
        print("=== Incoming requestBody ===")
        print(requestBody)
        print("===========================")

        // Parse the requestBody as JSON
        let parser = JSONParser()
        let root = parser.parse(requestBody)

        // Clear LED strip first
        ledStrip.clear()

        // Default brightness if none found
        var brightness = 128

        if let b = try? root["brightness"].asInt() {
          brightness = b
        }
        print(brightness)

        let ledsValue = root["leds"]
        print("ledsValue token type: \(ledsValue.tokenDebugType())")

        let count = ledsValue.arrayCount()
        print("LED array count: \(count)")

        for i in 0..<count {
          let ledItem = ledsValue[i]
          print("ledItem token type: \(ledItem.tokenDebugType())")

          guard
            let ledIndex = try? ledItem["index"].asInt(),
            let rVal = try? ledItem["r"].asInt(),
            let gVal = try? ledItem["g"].asInt(),
            let bVal = try? ledItem["b"].asInt()
          else {
            print("Failed to parse LED item at array index \(i)")
            continue
          }

          let finalR = rVal
          let finalG = gVal
          let finalB = bVal
          print("Index \(ledIndex): \(finalR) \(finalG) \(finalB)")

          ledStrip.setPixel(
            index: ledIndex,
            color: LedStrip.Color(r: finalR, g: finalG, b: finalB)
          )
          ledStrip.refresh()
        }

        // "count" loop ends exactly after the actual array length
        print("Done parsing LED array")
        return .success(response: "OK")

      }
    )

    // Idle loop
    while true {
      // Delay 500ms
      vTaskDelay(500 / (1000 / UInt32(configTICK_RATE_HZ)))
    }
  } catch {
    print("Error: \(error)")
  }
}
*/

@_cdecl("app_main")
func main() {
    // Possibly do some environment setup, then:
    testJSONParserSimple()
    testJSONParserArray()
    testJSONParserNested()
    testJSONParserDeeplyNested()
    // ...the rest of your main code...
}
