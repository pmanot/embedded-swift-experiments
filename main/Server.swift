public final class HTTPServer {
    private var handle: httpd_handle_t?
    private var registeredHandlers: [(Route, UnsafeMutableRawPointer)] = []
    private var uriCStrings: [UnsafeMutablePointer<CChar>] = []
    
    public init() {}
    
    public func start() -> HTTPError? {
        var config = DEFAULT_SERVER_CONFIG
        var localHandle: httpd_handle_t?
        
        guard httpd_start(&localHandle, &config) == ESP_OK,
              let server = localHandle else {
            return .serverStartFailed
        }
        
        handle = server
        return nil
    }
    
    @discardableResult
    public func register(_ route: Route) -> HTTPError? {
        guard let server = handle else {
            return .serverStartFailed
        }
        
        guard let uriCString = strdup(route.path) else {
            return .registrationFailed
        }
        uriCStrings.append(uriCString)
        
        let wrapper = HandlerWrapper(handler: route.handler)
        let context = Unmanaged.passRetained(wrapper).toOpaque()
        
        let handler: @convention(c) (UnsafeMutablePointer<httpd_req_t>?) -> esp_err_t = { req in
            guard let req = req,
                  let ctx = req.pointee.user_ctx else { 
                return ESP_FAIL 
            }
            
            let wrapper = Unmanaged<HandlerWrapper>.fromOpaque(ctx)
                .takeUnretainedValue()
            
            let bufferSize = 100
            var content = [CChar](repeating: 0, count: bufferSize)
            let recvSize = min(Int(req.pointee.content_len), bufferSize - 1)
            
            guard httpd_req_recv(req, &content, recvSize) > 0 else {
                return ESP_FAIL
            }
            
            let requestBody = String(cString: content)
            let result = wrapper.handler(requestBody)
            
            if case .success(let response) = result {
                let responseCStr = strdup(response)
                defer { free(responseCStr) }
                if let responseCStr = responseCStr {
                    _ = httpd_resp_send(req, responseCStr, Int(HTTPD_RESP_USE_STRLEN))
                }
            }
            
            return result.espError
        }
        
        var uriHandler = httpd_uri_t(
            uri: uriCString,
            method: route.method.rawValue,
            handler: handler,
            user_ctx: context
        )
        
        print("Registering route: ", terminator: "")
        print(route.path, terminator: "\n")
        
        guard httpd_register_uri_handler(server, &uriHandler) == ESP_OK else {
            Unmanaged<HandlerWrapper>.fromOpaque(context).release()
            free(uriCString)
            uriCStrings.removeLast()
            return .registrationFailed
        }
        
        registeredHandlers.append((route, context))
        return nil
    }
    
    public func stop() -> HTTPError? {
        guard let server = handle else { return nil }
        
        for (_, context) in registeredHandlers {
            Unmanaged<HandlerWrapper>.fromOpaque(context).release()
        }
        
        for uriCString in uriCStrings {
            free(uriCString)
        }
        
        registeredHandlers.removeAll()
        uriCStrings.removeAll()
        
        guard httpd_stop(server) == ESP_OK else {
            return .serverStopFailed
        }
        handle = nil
        return nil
    }
    
    deinit {
        _ = stop()
    }
}

private final class HandlerWrapper {
    let handler: (String) -> HTTPResult
    
    init(handler: @escaping (String) -> HTTPResult) {
        self.handler = handler
    }
}

public struct ServerConfig {
    let maxUriHandlers: UInt16
    let stackSize: Int
    let maxRespHeaders: UInt16
    
    public static let `default` = ServerConfig(
        maxUriHandlers: 8,
        stackSize: 4096,
        maxRespHeaders: 8
    )
    
    var espConfig: httpd_config_t {
        var config = httpd_config_t()
        config.max_uri_handlers = maxUriHandlers
        config.stack_size = stackSize
        config.max_resp_headers = maxRespHeaders
        return config
    }
}

public struct HTTPError {
    let code: Int32
    
    public static let serverStartFailed = HTTPError(code: 1)
    public static let serverStopFailed = HTTPError(code: 2)
    public static let registrationFailed = HTTPError(code: 3)
}

// Basic HTTP types
public enum HTTPMethod {
    case get
    case post
    case put
    case delete
    
    var rawValue: httpd_method_t {
        switch self {
        case .get: return HTTP_GET
        case .post: return HTTP_POST
        case .put: return HTTP_PUT
        case .delete: return HTTP_DELETE
        }
    }
}

// Type-safe route handler result
public enum HTTPResult {
    case success(response: String)
    case failure
    
    var espError: esp_err_t {
        switch self {
        case .success: return ESP_OK
        case .failure: return ESP_FAIL
        }
    }
}

// Route configuration
public struct Route {
    let path: String
    let method: HTTPMethod
    let handler: (String) -> HTTPResult
    
    public init(
        path: String,
        method: HTTPMethod,
        handler: @escaping (String) -> HTTPResult
    ) {
        self.path = path
        self.method = method
        self.handler = handler
    }
}