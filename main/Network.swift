public enum NetworkError: Int32, Error {
    case initFailed = 1
    case connectionFailed
    case invalidConfig 
    case httpError
}

public struct NetworkConfig {
    let ssid: String
    let password: String
    let timeout: UInt32
    
    public static func wifi(_ ssid: String, _ password: String) -> Self {
        .init(ssid: ssid, password: password, timeout: 10000)
    }
    
    public static let hotspot = NetworkConfig.wifi("Purav's iPhone", "987654321")
    public static let act = NetworkConfig.wifi("ACT102518899180", "70086670")
    public static let manju = NetworkConfig.wifi("@manjusstudio", "wifi2020!")
    public static let b204 = NetworkConfig.wifi("B-204", "coriolis")
    public static let voyager = NetworkConfig.wifi("Voyager3", "Houston420*")
}

public final class Network {
    private var isInitialized = false
    private var handle: httpd_handle_t?
    
    public init() {}
    
    public func initialize() throws(NetworkError) {
        guard !isInitialized else { return }
        let result = wifi_manager_init()
        guard result == ESP_OK else {
            throw NetworkError.initFailed
        }
        isInitialized = true
    }
    
    public func connect(_ config: NetworkConfig) throws(NetworkError) -> Bool {
        if !isInitialized {
            try initialize()
        }
        
        var connected = false
        let result = config.ssid.withCString { ssid in
            config.password.withCString { password in
                wifi_manager_connect_sta(ssid, password, config.timeout, &connected)
            }
        }
        
        guard result == ESP_OK else {
            throw NetworkError.connectionFailed
        }
        return connected
    }
    
    public func ipAddress() throws(NetworkError) -> String {
        guard let netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF") else {
            throw NetworkError.invalidConfig
        }
        
        var ipInfo = esp_netif_ip_info_t()
        guard esp_netif_get_ip_info(netif, &ipInfo) == ESP_OK else {
            throw NetworkError.invalidConfig
        }
        
        let addr: UInt32 = ipInfo.ip.addr
        let byte1: UInt8 = UInt8(addr & 0xFF)
        let byte2: UInt8 = UInt8((addr >> 8) & 0xFF)
        let byte3: UInt8 = UInt8((addr >> 16) & 0xFF)
        let byte4: UInt8 = UInt8((addr >> 24) & 0xFF)
        
        return "\(byte1).\(byte2).\(byte3).\(byte4)"
    }
    
    deinit {
        guard isInitialized else { return }
        _ = wifi_manager_deinit()
    }
}

// Access Point

public struct APConfig {
    let credentials: NetworkConfig
    let channel: UInt8
    let maxConnections: UInt8
    
    public static func create(
        _ ssid: String, 
        password: String = "", 
        channel: UInt8 = 1,
        maxConnections: UInt8 = 4
    ) -> Self {
        .init(
            credentials: .wifi(ssid, password),
            channel: channel,
            maxConnections: maxConnections
        )
    }
}

public final class APNetwork {
    let ipAddress: String
    fileprivate init(ipAddress: String) {
        self.ipAddress = ipAddress
    }
}

extension Network {
    public func startAP(_ config: APConfig) throws(NetworkError) -> APNetwork {
        if !isInitialized {
            try initialize()
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
            throw NetworkError.connectionFailed
        }
        
        let bufferSize = 16
        var buffer = [CChar](repeating: 0, count: bufferSize)
        
        guard wifi_manager_get_ap_ip(&buffer, bufferSize) == ESP_OK else {
            throw NetworkError.invalidConfig
        }
        
        return APNetwork(ipAddress: String(cString: buffer))
    }
}