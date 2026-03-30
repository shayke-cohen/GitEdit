import Foundation

#if DEBUG

// MARK: - AppXrayURLProtocol

/// URLProtocol subclass that intercepts network requests for inspection and mocking.
final class AppXrayURLProtocol: URLProtocol {
    private static let queue = DispatchQueue(label: "com.appxray.network", qos: .userInitiated)
    private static var entries: [NetworkEntry] = []
    static weak var timeline: TimelineBridge?
    private static var mocks: [NetworkMock] = []
    private static var chaosRules: [ChaosRule] = []
    private static let maxEntries = 200

    private var dataTask: URLSessionDataTask?
    private var requestData: Data?
    private var responseData: Data?
    private var startTime: CFAbsoluteTime = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        startTime = CFAbsoluteTimeGetCurrent()
        let requestId = UUID().uuidString

        if let mock = Self.findMock(for: request) {
            Self.recordRequest(request, id: requestId, pending: true)
            let req = request
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(mock.delay ?? 0) / 1000.0) { [weak self] in
                self?.deliverMock(mock, requestId: requestId, request: req)
            }
            return
        }

        if let chaos = Self.findChaos(for: request) {
            Self.recordRequest(request, id: requestId, pending: true)
            switch chaos.type {
            case "network-error":
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil))
            case "network-slow":
                let req = request
                let reqId = requestId
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(chaos.duration ?? 5000) / 1000.0) { [weak self] in
                    self?.performRequest(req, requestId: reqId)
                }
                return
            case "network-timeout":
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil))
            default:
                self.performRequest(request, requestId: requestId)
            }
            return
        }

        Self.recordRequest(request, id: requestId, pending: true)
        performRequest(request, requestId: requestId)
    }

    private func performRequest(_ request: URLRequest, requestId: String) {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let duration = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000
            if let error = error {
                Self.recordError(requestId: requestId, error: error)
            } else if let response = response as? HTTPURLResponse {
                Self.recordResponse(request: request, requestId: requestId, response: response, data: data, duration: duration)
            }
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        dataTask?.resume()
    }

    private func deliverMock(_ mock: NetworkMock, requestId: String, request: URLRequest) {
        let status = mock.response["status"] as? Int ?? 200
        let headers = mock.response["headers"] as? [String: String] ?? [:]
        let body = mock.response["body"]

        var headerDict: [String: String] = [:]
        for (k, v) in headers {
            headerDict[k] = v
        }
        if let bodyData = body as? Data {
            headerDict["Content-Length"] = "\(bodyData.count)"
        } else if let bodyStr = body as? String {
            let d = bodyStr.data(using: String.Encoding.utf8)!
            headerDict["Content-Length"] = "\(d.count)"
        }

        let url = URL(string: "http://localhost")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headerDict)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let bodyData = body as? Data {
            client?.urlProtocol(self, didLoad: bodyData)
        } else if let bodyStr = body as? String, let d = bodyStr.data(using: String.Encoding.utf8) {
            client?.urlProtocol(self, didLoad: d)
        } else if let bodyObj = body, let d = try? JSONSerialization.data(withJSONObject: bodyObj) {
            client?.urlProtocol(self, didLoad: d)
        }
        client?.urlProtocolDidFinishLoading(self)

        Self.recordMockResponse(requestId: requestId, status: status, body: body, request: request)
    }

    override func stopLoading() {
        dataTask?.cancel()
    }

    // MARK: - Static recording

    private static func recordRequest(_ request: URLRequest, id: String, pending: Bool) {
        queue.async {
            let reqDict: [String: Any] = [
                "id": id,
                "method": request.httpMethod ?? "GET",
                "url": request.url?.absoluteString ?? "",
                "headers": (request.allHTTPHeaderFields ?? [:]),
                "body": request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as Any,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            ]
            let entry = NetworkEntry(request: reqDict, response: nil, error: nil, pending: pending)
            entries.insert(entry, at: 0)
            if entries.count > maxEntries { entries.removeLast() }
        }
    }

    private static func recordResponse(request: URLRequest, requestId: String, response: HTTPURLResponse, data: Data?, duration: Double) {
        queue.async {
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? ""
            let statusCode = response.statusCode
            timeline?.emit(
                category: .network,
                action: "request.complete",
                summary: "\(method) \(url) → \(statusCode)",
                duration: duration
            )
            let respDict: [String: Any] = [
                "requestId": requestId,
                "status": response.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                "headers": (response.allHeaderFields as? [String: String]) ?? [:],
                "body": data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as Any,
                "duration": duration,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "size": data?.count ?? 0,
            ]
            if let idx = entries.firstIndex(where: { ($0.request["id"] as? String) == requestId }) {
                entries[idx] = NetworkEntry(request: entries[idx].request, response: respDict, error: nil, pending: false)
            }
        }
    }

    private static func recordError(requestId: String, error: Error) {
        queue.async {
            if let entry = entries.first(where: { ($0.request["id"] as? String) == requestId }) {
                let method = (entry.request["method"] as? String) ?? "GET"
                let url = (entry.request["url"] as? String) ?? ""
                timeline?.emit(
                    category: .network,
                    action: "request.error",
                    summary: "\(method) \(url) → \(error.localizedDescription)"
                )
            }
            if let idx = entries.firstIndex(where: { ($0.request["id"] as? String) == requestId }) {
                entries[idx] = NetworkEntry(request: entries[idx].request, response: nil, error: error.localizedDescription, pending: false)
            }
        }
    }

    private static func recordMockResponse(requestId: String, status: Int, body: Any?, request: URLRequest? = nil) {
        queue.async {
            if let req = request {
                let method = req.httpMethod ?? "GET"
                let url = req.url?.absoluteString ?? ""
                timeline?.emit(
                    category: .network,
                    action: "request.complete",
                    summary: "\(method) \(url) → \(status) (mock)",
                    duration: 0
                )
            }
            let respDict: [String: Any] = [
                "requestId": requestId,
                "status": status,
                "statusText": "",
                "headers": [:] as [String: String],
                "body": body as Any,
                "duration": 0,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "size": 0,
            ]
            if let idx = entries.firstIndex(where: { ($0.request["id"] as? String) == requestId }) {
                entries[idx] = NetworkEntry(request: entries[idx].request, response: respDict, error: nil, pending: false)
            }
        }
    }

    private static func findMock(for request: URLRequest) -> NetworkMock? {
        let url = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        return mocks.first { mock in
            mock.active && (mock.method == nil || mock.method == method) && url.contains(mock.pattern)
        }
    }

    private static func findChaos(for request: URLRequest) -> ChaosRule? {
        let url = request.url?.absoluteString ?? ""
        return chaosRules.first { rule in
            rule.active && (rule.target == nil || url.contains(rule.target!))
        }
    }

    // MARK: - Public API

    static func getEntries(filter: [String: Any]?, limit: Int?) -> [[String: Any]] {
        queue.sync {
            var result = entries
            if let urlFilter = filter?["url"] as? String {
                result = result.filter { ($0.request["url"] as? String)?.contains(urlFilter) == true }
            }
            if let methodFilter = filter?["method"] as? String {
                result = result.filter { ($0.request["method"] as? String) == methodFilter }
            }
            if let statusFilter = filter?["status"] as? Int {
                result = result.filter { ($0.response?["status"] as? Int) == statusFilter }
            }
            if let pendingFilter = filter?["pending"] as? Bool {
                result = result.filter { $0.pending == pendingFilter }
            }
            if let lim = limit {
                result = Array(result.prefix(lim))
            }
            return result.map { e in
                var d: [String: Any] = ["request": e.request, "pending": e.pending]
                if let r = e.response { d["response"] = r }
                if let err = e.error { d["error"] = err }
                return d
            }
        }
    }

    static func installMock(id: String, pattern: String, method: String?, response: [String: Any], delay: Int?, times: Int?) {
        queue.async {
            let mock = NetworkMock(
                id: id,
                pattern: pattern,
                method: method,
                response: response,
                delay: delay,
                times: times,
                active: true
            )
            mocks.removeAll { $0.id == id }
            mocks.append(mock)
        }
    }

    static func removeMock(id: String) {
        queue.async {
            mocks.removeAll { $0.id == id }
        }
    }

    static func clearMocks() {
        queue.async {
            mocks.removeAll()
        }
    }

    static func addChaosRule(_ rule: ChaosRule) {
        queue.async {
            chaosRules.append(rule)
        }
    }

    static func removeChaosRule(id: String) {
        queue.async {
            chaosRules.removeAll { $0.id == id }
        }
    }

    static func clearChaosRules() {
        queue.async {
            chaosRules.removeAll()
        }
    }

    static func listMocks() -> [[String: Any]] {
        queue.sync {
            mocks.map { m in
                [
                    "id": m.id,
                    "pattern": m.pattern,
                    "method": m.method as Any,
                    "active": m.active,
                    "delay": m.delay as Any,
                ] as [String: Any]
            }
        }
    }

    static func listChaosRules() -> [[String: Any]] {
        queue.sync {
            chaosRules.map { r in
                [
                    "id": r.id,
                    "type": r.type,
                    "target": r.target as Any,
                    "active": r.active,
                ] as [String: Any]
            }
        }
    }
}

// MARK: - Supporting types

private struct NetworkEntry {
    let request: [String: Any]
    let response: [String: Any]?
    let error: String?
    let pending: Bool
}

private struct NetworkMock {
    let id: String
    let pattern: String
    let method: String?
    let response: [String: Any]
    let delay: Int?
    let times: Int?
    var active: Bool
}

struct ChaosRule {
    let id: String
    let type: String
    let target: String?
    let duration: Int?
    var active: Bool
}

// MARK: - NetworkInterceptor

/// Public facade for network interception.
final class NetworkInterceptor {
    private weak var timeline: TimelineBridge?

    init(timeline: TimelineBridge? = nil) {
        self.timeline = timeline
    }

    func install() {
        AppXrayURLProtocol.timeline = timeline
        URLProtocol.registerClass(AppXrayURLProtocol.self)
    }

    func uninstall() {
        URLProtocol.unregisterClass(AppXrayURLProtocol.self)
    }

    func list(params: [String: Any]) async -> [String: Any] {
        let filter = params["filter"] as? [String: Any]
        let limit = params["limit"] as? Int
        let entries = AppXrayURLProtocol.getEntries(filter: filter, limit: limit)
        return ["entries": entries]
    }

    func mock(params: [String: Any]) async -> [String: Any] {
        let action = params["action"] as? String ?? "list"
        switch action {
        case "install":
            guard let id = params["id"] as? String ?? params["pattern"] as? String,
                  let pattern = params["pattern"] as? String,
                  let response = params["response"] as? [String: Any] else {
                return ["success": false, "error": "id, pattern, response required"]
            }
            let method = params["method"] as? String
            let delay = params["delay"] as? Int
            let times = params["times"] as? Int
            AppXrayURLProtocol.installMock(id: id, pattern: pattern, method: method, response: response, delay: delay, times: times)
            return ["success": true]
        case "remove":
            if let id = params["id"] as? String {
                AppXrayURLProtocol.removeMock(id: id)
            }
            return ["success": true]
        case "clear":
            AppXrayURLProtocol.clearMocks()
            return ["success": true]
        case "list":
            let mocks = AppXrayURLProtocol.listMocks()
            return ["mocks": mocks]
        default:
            return ["success": false, "error": "Unknown action"]
        }
    }
}

#endif
