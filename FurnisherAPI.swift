import Foundation

class FurnisherAPI {
    static let shared = FurnisherAPI()
    
    private let baseURL = "http://136.116.236.142:5000"
    
    private init() {}
    
    func sendRoomScan(usdzURL: URL, roomType: String = "bedroom", budget: String = "5000") async throws -> FurnishedResponse {
        guard let url = URL(string: "\(baseURL)/generate-design") else {
            throw FurnisherAPIError.invalidURL
        }
        
        guard let fileData = try? Data(contentsOf: usdzURL) else {
            throw FurnisherAPIError.noFileData
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        
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
            throw FurnisherAPIError.networkError(error)
        }
    }
    
    private func convertFlaskResponse(_ response: FlaskResponse) -> FurnishedResponse {
        guard let firstPlan = response.plans.first else {
            return FurnishedResponse(sceneId: response.scanId, roomModel: nil, furniture: [], message: nil)
        }
        let furniture = firstPlan.furniture.map { item in
            FurnitureItem(
                name: extractName(from: item.pageLink),
                price: extractPrice(from: item.price),
                imageUrl: item.imageLink,
                url: item.pageLink,
                category: "furniture",
                description: nil,
                modelUrlUsdz: constructFullURL(item.usdzUrl),
                placement: FurniturePlacement(
                    position: Position3D(x: item.position.x, y: item.position.y, z: item.position.z),
                    rotation: Rotation3D(x: 0, y: 0, z: 0),
                    scale: Scale3D(x: 1.0, y: 1.0, z: 1.0)
                )
            )
        }
        let roomModel = RoomModel(
            id: UUID().uuidString,
            dimensions: nil,
            walls: [],
            features: [],
            roomModelUrlUsdz: constructFullURL(response.roomScanUrl)
        )
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
}
