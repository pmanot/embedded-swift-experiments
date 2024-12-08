//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@_cdecl("app_main")
func app_main() {
  print("Hello from Swift on ESP32-C6!")
  
  // Initialize WiFi
  guard wifi_manager_init() == ESP_OK else {
    print("Failed to initialize WiFi")
    return
  }
  
  // Try to connect to WiFi network first (as client)
  var connected: Bool = false
  let staResult = wifi_manager_connect_sta(
    "<SSID>",      // Your WiFi SSID
    "<PASSWORD>",          // Your WiFi Password
    10000,                // Timeout in ms (10 seconds)
    &connected            // Connection status
  )
  
  if staResult == ESP_OK && connected {
    print("Successfully connected to WiFi!")
    
    // Get and print the device's IP address
    var ipBuffer = [CChar](repeating: 0, count: 16)
    if wifi_manager_get_sta_ip(&ipBuffer, 16) == ESP_OK {
        let ipAddress = String(cString: ipBuffer)
        print("Device IP address: \(ipAddress)")
    }
    
    // Start HTTP server
    if wifi_manager_start_http_server() == ESP_OK {
        print("HTTP server started successfully")
        print("You can now send POST requests to http://<device-ip>/command")
    } else {
        print("Failed to start HTTP server")
    }
  } else {
    print("Failed to connect to WiFi")
    return
  }

  let n = 65
  let ledStrip = LedStrip(gpioPin: 6, maxLeds: n)
  ledStrip.clear()

  var colors: [LedStrip.Color] = .init(repeating: .off, count: n)
  while true {
    colors.removeLast()
    colors.insert(.lightRandom, at: 0)

    for index in 0 ..< n {
      ledStrip.setPixel(index: index, color: colors[index])
    }
    ledStrip.refresh()
    
    let blinkDelayMs: UInt32 = 500
    vTaskDelay(blinkDelayMs / (1000 / UInt32(configTICK_RATE_HZ)))
  }
}