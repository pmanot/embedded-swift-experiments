@_cdecl("app_main")
func app_main() {
    print("Starting WiFi and HTTP server...")
    let wifiManager = WiFiManager()
    let server = HTTPServer()

    do {
        // Initialize WiFi first
        try wifiManager.initialize()
        
        let credentials = WiFiCredentials(
            ssid: "ACT102518899180",
            password: "70086670"
        )
        
        // Connect to WiFi
        let connected = try wifiManager.connectToNetwork(credentials)
        guard connected else {
            print("Failed to connect to WiFi")
            return
        }
        
        print("Successfully connected to WiFi!")
        
        // Get and print IP address
        let ipAddress = try wifiManager.getStationIPAddress()
        print("Device IP address: \(ipAddress)")
        
        // Start HTTP server
        if let error = server.start() {
            print("Server failed to start: \(error.code)")
            return
        }
        
        // Register routes
        if let error = server.register(Route(path: "/led", method: .post) { request in
            print("LED command received: \(request)")
            return .success(response: "OK")
        }) {
            print("Failed to register route: \(error.code)")
            return
        }
        
        print("HTTP server started successfully")
        print("You can now send POST requests to http://\(ipAddress)/led")
        
        // Keep the task alive
        while true {
            vTaskDelay(500 / (1000 / UInt32(configTICK_RATE_HZ)))
        }
        
    } catch {
        print("Error during initialization: \(error)")
    }
}




/*
let credentials = WiFiCredentials(
  ssid: "B-204",
  password: "coriolis"
)
*/
/*
let credentials = WiFiCredentials(
    ssid: "@manjusstudio",
    password: "wifi2020!"
)
*/