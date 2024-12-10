@_cdecl("app_main")
func app_main() {
    do {
        let ledStrip = LedStrip(gpioPin: 6, maxLeds: 65)
        let network = Network()
        
        guard try network.connect(.b204) else {
            print("Connection failed")
            return
        }
        
        let ip = try network.ipAddress()
        print("Connected: \(ip)")
        
        let server = HTTPServer()
        guard server.start() == nil else {
            print("Server start failed")
            return
        }
        
        server.register(Route(path: "/led", method: .post) { request in
            print("LED: \(request)")
            let color = LedStrip.Color.lightRandom
            ledStrip.clear()
            
            for index in 0..<65 {
              ledStrip.setPixel(index: index, color: color)
              ledStrip.refresh()
            }

            return .success(response: "OK")
        })
        
        while true {
            vTaskDelay(500 / (1000 / UInt32(configTICK_RATE_HZ)))
        }
    } catch {
        print("Error: \(error)")
    }
}