import Foundation

class FurnisherAPI {
    static let shared = FurnisherAPI()
    
    /// Use HTTPS (ngrok) to satisfy App Transport Security.
    private let baseURL = "https://lavonia-undeducted-aida.ngrok-free.dev"
    
    private init() {}
    
    /// Room scan pipeline (same server, /roomscan).
    private static let roomScanPipelineBaseURL = "https://lavonia-undeducted-aida.ngrok-free.dev"
    
    /// Upload USDZ + room_type to the room scan pipeline endpoint.
    func uploadRoomScanToPipeline(usdzURL: URL, roomType: String) async throws {
        var urlString = Self.roomScanPipelineBaseURL
        if !urlString.hasSuffix("/roomscan") {
            urlString = urlString.hasSuffix("/") ? urlString + "roomscan" : urlString + "/roomscan"
        }
        guard let url = URL(string: urlString) else { throw FurnisherAPIError.invalidURL }
        guard let fileData = try? Data(contentsOf: usdzURL) else { throw FurnisherAPIError.noFileData }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        request.timeoutInterval = 120
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"room_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(roomType)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(usdzURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw FurnisherAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Server error"
            throw FurnisherAPIError.serverError(httpResponse.statusCode, message)
        }
    }
    
    func sendRoomScan(usdzURL: URL, roomType: String = "bedroom", budget: String = "5000") async throws -> FurnishedResponse {
        guard let url = URL(string: "\(baseURL)/roomscan") else {
            throw FurnisherAPIError.invalidURL
        }
        
        guard let fileData = try? Data(contentsOf: usdzURL) else {
            throw FurnisherAPIError.noFileData
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        request.timeoutInterval = 600
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(usdzURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: model/vnd.usdz+zip\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"room_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(roomType)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"budget\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(budget)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        return try await executeRequest(request)
    }
    
    private func executeRequest(_ request: URLRequest) async throws -> FurnishedResponse {
        let maxRetries = 2
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FurnisherAPIError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw FurnisherAPIError.serverError(httpResponse.statusCode, errorMessage)
                }
                let decoder = JSONDecoder()
                do {
                    let flaskResponse = try decoder.decode(FlaskResponse.self, from: data)
                    return convertFlaskResponse(flaskResponse)
                } catch {
                    throw FurnisherAPIError.decodingError(error.localizedDescription)
                }
            } catch let error as FurnisherAPIError {
                throw error
            } catch {
                lastError = error
                let nsError = error as NSError
                // Retry on transient network errors: -1005 connection lost, -1001 timeout
                let isRetryable = (nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorNetworkConnectionLost || nsError.code == NSURLErrorTimedOut))
                if isRetryable && attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s backoff
                    continue
                }
                throw FurnisherAPIError.networkError(error)
            }
        }
        throw FurnisherAPIError.networkError(lastError ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: nil))
    }
    
    private func convertFlaskResponse(_ response: FlaskResponse) -> FurnishedResponse {
        guard let firstPlan = response.plans.first else {
            return FurnishedResponse(sceneId: response.scanId, roomModel: nil, furniture: [], message: nil)
        }
        let furniture = firstPlan.furniture.map { item in
            let scale = item.scale
            let sx = scale?.x ?? 1.0, sy = scale?.y ?? 1.0, sz = scale?.z ?? 1.0
            let dimensionsStr = formatDimensionsForDisplay(item.dimensions)
            return FurnitureItem(
                name: item.description ?? extractName(from: item.pageLink),
                price: extractPrice(from: item.price),
                imageUrl: item.imageLink ?? "",
                url: item.pageLink,
                category: "furniture",
                description: item.description,
                modelUrlUsdz: constructFullURL(item.usdzUrl),
                placement: FurniturePlacement(
                    position: Position3D(x: item.position.x, y: item.position.y, z: item.position.z),
                    rotation: Rotation3D(x: 0, y: 0, z: 0),
                    scale: Scale3D(x: sx, y: sy, z: sz)
                ),
                dimensionsMeters: dimensionsStr
            )
        }
        let roomUrl = response.roomScanUrl.flatMap { s in s.isEmpty ? nil : s }
        let roomModel: RoomModel? = roomUrl.map { url in
            RoomModel(
                id: UUID().uuidString,
                dimensions: nil,
                walls: [],
                features: [],
                roomModelUrlUsdz: constructFullURL(url)
            )
        }
        return FurnishedResponse(
            sceneId: response.scanId,
            roomModel: roomModel,
            furniture: furniture,
            message: nil
        )
    }
    
    private func constructFullURL(_ path: String) -> String {
        if path.hasPrefix("http") { return path }
        return baseURL + path
    }
    
    private func extractName(from url: String) -> String {
        let components = url.split(separator: "/")
        if let last = components.last {
            return String(last)
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        return "Furniture Item"
    }
    
    private func extractPrice(from priceString: String) -> Double {
        let cleaned = priceString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0.0
    }
    
    /// Format backend dimensions string (e.g. "0.80x0.80x0.80m") for display in meters.
    private func formatDimensionsForDisplay(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        // Backend: "0.80x0.80x0.80m" -> "0.80 × 0.80 × 0.80 m"
        var cleaned = raw.replacingOccurrences(of: "x", with: " × ").replacingOccurrences(of: "X", with: " × ")
        if cleaned.hasSuffix("m") && !cleaned.hasSuffix(" m") { cleaned = String(cleaned.dropLast()) + " m" }
        else if !cleaned.lowercased().contains("m") { cleaned += " m" }
        return cleaned
    }
}
