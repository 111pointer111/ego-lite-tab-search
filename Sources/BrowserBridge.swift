import Foundation

struct SpaceChoice: Decodable, Identifiable {
    let id: Int
    let name: String
    let profileName: String
}

struct BrowserTab: Decodable, Identifiable {
    let id: String
    let title: String
    let url: String
    let windowId: Int
    let contextId: String
    let profileName: String
    let spaceId: Int?
    let spaceName: String
    let candidates: [SpaceChoice]

    var displayURL: String {
        guard var components = URLComponents(string: url) else { return url }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? url
    }
}

struct SpaceBinding: Codable {
    let windowId: Int
    let contextId: String
    let spaceId: Int
}

struct BridgeRequest: Encodable {
    let action: String
    var helperKey: String = BrowserBridge.clientKey
    var bindings: [SpaceBinding] = []
    var targetId: String?
    var windowId: Int?
    var contextId: String?
}

struct BridgeResponse: Decodable {
    let ok: Bool
    let tabs: [BrowserTab]?
    let error: String?
    let ambiguousWindows: Int?
}

final class BrowserBridge {
    static let clientKey: String = {
        if let key = UserDefaults.standard.string(forKey: "bridgeClientKey") { return key }
        let key = String(UUID().uuidString.prefix(8))
        UserDefaults.standard.set(key, forKey: "bridgeClientKey")
        return key
    }()
    private let queue = DispatchQueue(label: "app.ego-tab-search.bridge")

    func send(_ request: BridgeRequest, completion: @escaping (Result<BridgeResponse, Error>) -> Void) {
        queue.async {
            let result = Result { try self.run(request) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func run(_ request: BridgeRequest) throws -> BridgeResponse {
        let resource = Bundle.main.resourceURL!.appendingPathComponent("bridge/runtime.mjs")
        let encodedRequest = String(data: try JSONEncoder().encode(request), encoding: .utf8)!
        let encodedPath = String(data: try JSONSerialization.data(withJSONObject: resource.absoluteString, options: .fragmentsAllowed), encoding: .utf8)!
        let script = "const bridge = await import(\(encodedPath)); await bridge.execute({ taskSpace, listTaskSpaces }, \(encodedRequest));"
        let process = Process()
        process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/ego-browser")
        process.arguments = ["nodejs"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // The installed CLI emits script console output on stderr on some builds.
        process.standardError = output
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        let marker = "__EGO_TAB_SEARCH__"
        let line = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).last { $0.hasPrefix(marker) }
        guard let line else {
            throw NSError(domain: "EgoTabSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法连接 ego lite，请确认浏览器已打开，再按 ⌘R 重试。"])
        }
        return try JSONDecoder().decode(BridgeResponse.self, from: Data(line.dropFirst(marker.count).utf8))
    }
}
