public enum WiFiManagerError: Swift.Error {
    case initializationFailed
    case apStartFailed
    case connectionFailed
    case invalidIPAddress
    case httpServerError
    case deinitializationFailed
}

public struct WiFiCredentials {
    let ssid: String
    let password: String

    public init(ssid: String, password: String = "") {
        self.ssid = ssid
        self.password = password
    }
}

public struct APConfiguration {
    let credentials: WiFiCredentials
    let channel: UInt8
    let maxConnections: UInt8

    public init(
        credentials: WiFiCredentials,
        channel: UInt8 = 1,
        maxConnections: UInt8 = 4
    ) {
        self.credentials = credentials
        self.channel = channel
        self.maxConnections = maxConnections
    }
}

public class ClosureWrapper {
    let closure: () -> Void
    
    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
}

public final class WiFiManager {
    private var isInitialized = false
    private var handle: httpd_handle_t? = nil
    var handler: () -> Void = {}

    public init() {}

    public func startHTTPServer(test: @escaping () -> Void) throws(WiFiManagerError) {
        if !isInitialized {
            try initialize()
        }

        var config = DEFAULT_SERVER_CONFIG
        var localServer: httpd_handle_t?

        guard httpd_start(&localServer, &config) == ESP_OK,
            let server = localServer
        else {
            throw WiFiManagerError.httpServerError
        }

        self.handle = server

        // Store the test closure in an unmanaged pointer

        let commandUri = "/led"
        let closureWrapper = ClosureWrapper(test)
        let userContext = Unmanaged.passRetained(closureWrapper).toOpaque()
        // Pass a function pointer compatible closure
        var closure: @convention(c) (UnsafeMutablePointer<httpd_req_t>?) -> esp_err_t = { req in
            guard let req = req else { return ESP_FAIL }
            print("started")
            
            // Retrieve the closure from the unmanaged pointer            
            let bufferSize = 100
            var content = [CChar](repeating: 0, count: bufferSize)
            let recvSize = min(Int(req.pointee.content_len), bufferSize - 1)

            print("received!")

            guard httpd_req_recv(req, &content, recvSize) > 0 else {
                return ESP_FAIL
            }

            print(String(cString: content))

            let response = "Command received\n"

            guard let userContext = req.pointee.user_ctx else { return ESP_FAIL }
            let closureWrapper = Unmanaged<ClosureWrapper>.fromOpaque(userContext).takeUnretainedValue()
            let testClosure = closureWrapper.closure
            testClosure() // Call the closure

            response.withCString { cString in
                httpd_resp_send(req, cString, Int(HTTPD_RESP_USE_STRLEN))
            }

            return ESP_OK
        }

        var uriHandler = httpd_uri_t()
        uriHandler = httpd_uri_t(
            uri: commandUri,
            method: HTTP_POST,
            handler: closure,
            user_ctx: userContext
        )

        guard httpd_register_uri_handler(server, &uriHandler) == ESP_OK else {
            httpd_stop(server)
            Unmanaged<ClosureWrapper>.fromOpaque(userContext).release()
            throw WiFiManagerError.httpServerError
        }
    }

    public func initialize() throws(WiFiManagerError) {
        guard !isInitialized else { return }

        let result = wifi_manager_init()
        guard result == ESP_OK else {
            throw WiFiManagerError.initializationFailed
        }
        isInitialized = true
    }

    public func startAccessPoint(_ config: APConfiguration) throws(WiFiManagerError) {
        guard isInitialized else {
            try initialize()

            return
        }

        let result = config.credentials.ssid.withCString { ssid in
            config.credentials.password.withCString { password in
                wifi_manager_start_ap(
                    ssid,
                    password,
                    config.channel,
                    config.maxConnections
                )
            }
        }

        guard result == ESP_OK else {
            throw WiFiManagerError.apStartFailed
        }
    }

    public func connectToNetwork(
        _ credentials: WiFiCredentials,
        timeoutMs: UInt32 = 10000
    ) throws(WiFiManagerError) -> Bool {
        if !isInitialized {
            try initialize()
        }

        var connected = false
        let result = credentials.ssid.withCString { ssid in
            credentials.password.withCString { password in
                wifi_manager_connect_sta(
                    ssid,
                    password,
                    timeoutMs,
                    &connected
                )
            }
        }

        guard result == ESP_OK else {
            throw WiFiManagerError.connectionFailed
        }

        return connected
    }

    public func stopHTTPServer() throws(WiFiManagerError) {
        guard isInitialized else { return }

        let result = wifi_manager_stop_http_server()
        guard result == ESP_OK else {
            throw WiFiManagerError.httpServerError
        }
    }

    public func getAccessPointIPAddress() throws(WiFiManagerError) -> String {
        let bufferSize = 16  // Maximum IPv4 string length
        var buffer = [CChar](repeating: 0, count: bufferSize)

        let result = wifi_manager_get_ap_ip(&buffer, bufferSize)
        guard result == ESP_OK else {
            throw WiFiManagerError.invalidIPAddress
        }

        return String(cString: buffer)
    }

    public func getStationIPAddress() throws(WiFiManagerError) -> String {
        guard let netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF") else {
            throw WiFiManagerError.invalidIPAddress
        }

        var ipInfo = esp_netif_ip_info_t()
        guard esp_netif_get_ip_info(netif, &ipInfo) == ESP_OK else {
            throw WiFiManagerError.invalidIPAddress
        }

        let ip = ipInfo.ip
        let addr: UInt32 = ipInfo.ip.addr
        let byte1: UInt8 = UInt8(addr & 0xFF)
        let byte2: UInt8 = UInt8((addr >> 8) & 0xFF)
        let byte3: UInt8 = UInt8((addr >> 16) & 0xFF)
        let byte4: UInt8 = UInt8((addr >> 24) & 0xFF)

        return "\(byte1).\(byte2).\(byte3).\(byte4)"
    }

    public func deinitialize() throws(WiFiManagerError) {
        guard isInitialized else { return }

        let result = wifi_manager_deinit()
        guard result == ESP_OK else {
            throw WiFiManagerError.deinitializationFailed
        }
        isInitialized = false
    }

    deinit {
        try? deinitialize()
    }
}

private let ESP_OK: esp_err_t = 0