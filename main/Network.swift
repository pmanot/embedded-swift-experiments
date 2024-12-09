public enum NetworkError: Int32 {
    case initFailed = 1
    case connectionFailed
    case invalidConfig 
    case httpError
    
    var espError: esp_err_t {
        Int32(rawValue)
    }
}

// Network configuration
public struct NetworkConfig {
    let ssid: String
    let password: String
    let timeout: UInt32
    
    public static func wifi(_ ssid: String, _ password: String) -> Self {
        .init(ssid: ssid, password: password, timeout: 10000)
    }
    
    // Saved configurations
    public static let act = NetworkConfig.wifi("ACT102518899180", "70086670")
    public static let manju = NetworkConfig.wifi("@manjusstudio", "wifi2020!")
    public static let b204 = NetworkConfig.wifi("B-204", "coriolis")
}

// Main network interface
public final class Network {
    private var isInitialized = false
    private let netif: esp_netif_t
    
    public init() throws {
        guard let netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF") else {
            throw NetworkError.initFailed
        }
        self.netif = netif
        try initialize()
    }
    
    private func initialize() throws {
        guard !isInitialized else { return }
        guard esp_netif_init() == ESP_OK else {
            throw NetworkError.initFailed
        }
        isInitialized = true
    }
    
    public func connect(_ config: NetworkConfig) throws -> Bool {
        var connected = false
        let result = config.ssid.withCString { ssid in
            config.password.withCString { password in
                wifi_connect(ssid, password, config.timeout, &connected)
            }
        }
        
        guard result == ESP_OK else {
            throw NetworkError.connectionFailed
        }
        return connected
    }
    
    public func ipAddress() throws -> String {
        var ipInfo = esp_netif_ip_info_t()
        guard esp_netif_get_ip_info(netif, &ipInfo) == ESP_OK else {
            throw NetworkError.invalidConfig
        }
        
        let addr = ipInfo.ip.addr
        return [
            UInt8(addr & 0xFF),
            UInt8((addr >> 8) & 0xFF), 
            UInt8((addr >> 16) & 0xFF),
            UInt8((addr >> 24) & 0xFF)
        ].map(String.init).joined(separator: ".")
    }
    
    deinit {
        guard isInitialized else { return }
        esp_netif_deinit()
    }
}