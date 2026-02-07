import SwiftUI

struct ARDesignView: View {
    let design: GeneratedDesign
    @Environment(\.dismiss) var dismiss
    @State private var showFurnitureList = false
    @StateObject private var resourceManager = RealityResourceManager.shared

    var body: some View {
        ZStack {
            if resourceManager.canStartSession(.arDesign) {
                ARViewContainer(design: design)
                    .ignoresSafeArea()
            } else {
                // Show placeholder when RoomPlan is active
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                        
                        Text("AR View Unavailable")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Text("Room scanning is active. Close the scanner to view AR.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }

            // Sophisticated overlay UI
            VStack {
                // Top controls with glass morphism
                HStack(spacing: Theme.Spacing.md) {
                    // Close button
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            Color.white.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )

                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(
                            color: .black.opacity(0.3),
                            radius: 12,
                            x: 0,
                            y: 4
                        )
                    }

                    Spacer()

                    // Furniture count badge
                    Button(action: { showFurnitureList.toggle() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "cube.box.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(design.furniture.count)")
                                .font(.system(size: 15, weight: .bold))
                            Text("items")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(Theme.Colors.darkBrown)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            Color.white.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(
                            color: .black.opacity(0.3),
                            radius: 12,
                            x: 0,
                            y: 4
                        )
                    }
                }
                .padding(Theme.Spacing.lg)

                Spacer()

                // Bottom info card
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("AR Preview")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))

                            Text("Interactive 3D View")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Button(action: { showFurnitureList.toggle() }) {
                            Text("Details")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    Capsule()
                                        .fill(Theme.Colors.mediumBrown)
                                )
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(Theme.Spacing.lg)
                .shadow(
                    color: .black.opacity(0.4),
                    radius: 20,
                    x: 0,
                    y: 8
                )
            }
        }
        .sheet(isPresented: $showFurnitureList) {
            FurnitureListView(furniture: design.furniture)
        }
        .onDisappear {
            // Release AR resources when view disappears
            resourceManager.releaseSession(.arDesign)
        }
    }
}

struct FurnitureListView: View {
    let furniture: [FurnitureItem]
    @Environment(\.dismiss) var dismiss

    var totalCost: Double {
        furniture.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(furniture) { item in
                            FurnitureItemCard(item: item)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationTitle("Furniture Collection")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("$\(Int(totalCost))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.Colors.primary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.cardBackground)
                    )
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Close")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(Theme.Colors.primary)
                    }
                }
            }
        }
    }
}

struct FurnitureItemCard: View {
    let item: FurnitureItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            AsyncImage(url: URL(string: item.imageUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.secondaryBackground)

                    ProgressView()
                        .tint(Theme.Colors.primary)
                }
            }
            .frame(width: 80, height: 80)
            .cornerRadius(Theme.CornerRadius.md)
            .clipped()

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)

                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Text("$\(Int(item.price))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.Colors.primary)
            }

            Spacer()

            Link(destination: URL(string: item.url)!) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Colors.mediumBrown,
                                    Theme.Colors.darkBrown
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "cart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.Colors.paleBeige)
                }
                .shadow(
                    color: Theme.Shadow.medium.color,
                    radius: Theme.Shadow.medium.radius,
                    x: Theme.Shadow.medium.x,
                    y: Theme.Shadow.medium.y
                )
            }
        }
        .padding(Theme.Spacing.md)
        .floatingCardStyle()
    }
}
