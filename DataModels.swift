import Foundation
import SwiftUI

// MARK: - Core Data Models

struct FurnitureItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let price: Double
    let imageUrl: String
    let url: String
    let category: String
    let description: String?
    let modelUrlUsdz: String?
    let placement: FurniturePlacement?
    /// Dimensions in meters (e.g., "0.80 × 0.80 × 0.80 m") from backend.
    let dimensionsMeters: String?
    
    enum CodingKeys: String, CodingKey {
        case name, price, imageUrl, url, category, description, modelUrlUsdz, placement
        case dimensionsMeters = "dimensionsMeters"
    }
    
    init(name: String, price: Double, imageUrl: String, url: String, category: String = "furniture", description: String? = nil, modelUrlUsdz: String? = nil, placement: FurniturePlacement? = nil, dimensionsMeters: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.price = price
        self.imageUrl = imageUrl
        self.url = url
        self.category = category
        self.description = description
        self.modelUrlUsdz = modelUrlUsdz
        self.placement = placement
        self.dimensionsMeters = dimensionsMeters
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try c.decode(String.self, forKey: .name)
        price = try c.decode(Double.self, forKey: .price)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl) ?? ""
        url = try c.decode(String.self, forKey: .url)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "furniture"
        description = try c.decodeIfPresent(String.self, forKey: .description)
        modelUrlUsdz = try c.decodeIfPresent(String.self, forKey: .modelUrlUsdz)
        placement = try c.decodeIfPresent(FurniturePlacement.self, forKey: .placement)
        dimensionsMeters = try c.decodeIfPresent(String.self, forKey: .dimensionsMeters)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(price, forKey: .price)
        try c.encode(imageUrl, forKey: .imageUrl)
        try c.encode(url, forKey: .url)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(modelUrlUsdz, forKey: .modelUrlUsdz)
        try c.encodeIfPresent(placement, forKey: .placement)
        try c.encodeIfPresent(dimensionsMeters, forKey: .dimensionsMeters)
    }
}

struct RoomModel: Codable {
    let id: String
    let dimensions: RoomDimensions?
    let walls: [WallInfo]
    let features: [RoomFeature]
    let roomModelUrlUsdz: String?
    
    init(id: String, dimensions: RoomDimensions? = nil, walls: [WallInfo] = [], features: [RoomFeature] = [], roomModelUrlUsdz: String? = nil) {
        self.id = id
        self.dimensions = dimensions
        self.walls = walls
        self.features = features
        self.roomModelUrlUsdz = roomModelUrlUsdz
    }
}

struct RoomDimensions: Codable {
    let length: Double
    let width: Double
    let height: Double
    let depth: Double
    
    init(length: Double, width: Double, height: Double, depth: Double? = nil) {
        self.length = length
        self.width = width
        self.height = height
        self.depth = depth ?? width // Use width as depth if not specified
    }
}

struct WallInfo: Codable, Identifiable {
    let id: UUID
    let position: String
    let length: Double
    let hasWindow: Bool
    let hasDoor: Bool
    
    init(id: UUID = UUID(), position: String, length: Double, hasWindow: Bool, hasDoor: Bool) {
        self.id = id
        self.position = position
        self.length = length
        self.hasWindow = hasWindow
        self.hasDoor = hasDoor
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        position = try c.decode(String.self, forKey: .position)
        length = try c.decode(Double.self, forKey: .length)
        hasWindow = try c.decodeIfPresent(Bool.self, forKey: .hasWindow) ?? false
        hasDoor = try c.decodeIfPresent(Bool.self, forKey: .hasDoor) ?? false
    }
    
    enum CodingKeys: String, CodingKey {
        case id, position, length, hasWindow, hasDoor
    }
}

struct RoomFeature: Codable, Identifiable {
    let id: UUID
    let type: String
    let position: String
    let dimensions: String?
    
    init(id: UUID = UUID(), type: String, position: String, dimensions: String?) {
        self.id = id
        self.type = type
        self.position = position
        self.dimensions = dimensions
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        type = try c.decode(String.self, forKey: .type)
        position = try c.decode(String.self, forKey: .position)
        dimensions = try c.decodeIfPresent(String.self, forKey: .dimensions)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, position, dimensions
    }
}

struct FurniturePlacement: Codable {
    let position: Position3D
    let rotation: Rotation3D
    let scale: Scale3D
}

struct Position3D: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct Rotation3D: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct Scale3D: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct GeneratedDesign: Identifiable, Codable {
    let id: UUID
    let sceneId: String
    let timestamp: Date
    let roomModel: RoomModel?
    let furniture: [FurnitureItem]
    let totalCost: Double
    
    enum CodingKeys: String, CodingKey {
        case id, sceneId, timestamp, roomModel, furniture, totalCost
    }
    
    init(sceneId: String, roomModel: RoomModel?, furniture: [FurnitureItem], id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.sceneId = sceneId
        self.timestamp = timestamp
        self.roomModel = roomModel
        self.furniture = furniture
        self.totalCost = furniture.reduce(0) { $0 + $1.price }
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sceneId = try c.decode(String.self, forKey: .sceneId)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        roomModel = try c.decodeIfPresent(RoomModel.self, forKey: .roomModel)
        let decodedFurniture = try c.decode([FurnitureItem].self, forKey: .furniture)
        furniture = decodedFurniture
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost) ?? decodedFurniture.reduce(0) { $0 + $1.price }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sceneId, forKey: .sceneId)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(roomModel, forKey: .roomModel)
        try c.encode(furniture, forKey: .furniture)
        try c.encode(totalCost, forKey: .totalCost)
    }
}

struct FurnishedResponse: Codable {
    let sceneId: String
    let roomModel: RoomModel?
    let furniture: [FurnitureItem]
    let message: String?
    
    init(sceneId: String, roomModel: RoomModel? = nil, furniture: [FurnitureItem], message: String? = nil) {
        self.sceneId = sceneId
        self.roomModel = roomModel
        self.furniture = furniture
        self.message = message
    }
}

// MARK: - Sample Data for Testing
extension FurnitureItem {
    static let sampleItems = [
        FurnitureItem(
            name: "Modern Sofa",
            price: 899.99,
            imageUrl: "https://example.com/sofa.jpg",
            url: "https://example.com/buy/sofa",
            category: "seating",
            description: "Comfortable 3-seat modern sofa",
            modelUrlUsdz: "https://example.com/models/sofa.usdz",
            placement: FurniturePlacement(
                position: Position3D(x: 0, y: 0, z: -2),
                rotation: Rotation3D(x: 0, y: 0, z: 0),
                scale: Scale3D(x: 1, y: 1, z: 1)
            ),
            dimensionsMeters: "2.10 × 0.90 × 0.85 m"
        ),
        FurnitureItem(
            name: "Coffee Table",
            price: 299.99,
            imageUrl: "https://example.com/table.jpg",
            url: "https://example.com/buy/table",
            category: "tables",
            description: "Glass top coffee table",
            modelUrlUsdz: "https://example.com/models/table.usdz",
            placement: FurniturePlacement(
                position: Position3D(x: 0, y: 0, z: -1),
                rotation: Rotation3D(x: 0, y: 0, z: 0),
                scale: Scale3D(x: 1, y: 1, z: 1)
            ),
            dimensionsMeters: "1.20 × 0.60 × 0.45 m"
        ),
        FurnitureItem(
            name: "Floor Lamp",
            price: 149.99,
            imageUrl: "https://example.com/lamp.jpg",
            url: "https://example.com/buy/lamp",
            category: "lighting",
            description: "Modern LED floor lamp",
            modelUrlUsdz: "https://example.com/models/lamp.usdz",
            placement: FurniturePlacement(
                position: Position3D(x: 1.5, y: 0, z: -2.5),
                rotation: Rotation3D(x: 0, y: 0, z: 0),
                scale: Scale3D(x: 1, y: 1, z: 1)
            ),
            dimensionsMeters: "0.25 × 1.60 × 0.25 m"
        )
    ]
}

extension GeneratedDesign {
    static let sampleDesign = GeneratedDesign(
        sceneId: "sample_scene_001",
        roomModel: RoomModel(
            id: "room_001",
            dimensions: RoomDimensions(length: 12.0, width: 10.0, height: 9.0),
            roomModelUrlUsdz: "https://example.com/models/room.usdz"
        ),
        furniture: FurnitureItem.sampleItems
    )
}
