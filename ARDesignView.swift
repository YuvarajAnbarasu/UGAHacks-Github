import SwiftUI
import AVFoundation

struct ARDesignView: View {
    let design: GeneratedDesign
    @Environment(\.dismiss) var dismiss
    @State private var showFurnitureList = false
    @State private var selectedItemForPlacement: FurnitureItem?
    @State private var isMoveMode = false
    @State private var placedCount = 0
    @State private var placedItemIds: Set<UUID> = []
    @State private var pendingAction: PendingARAction = .none
    @State private var showOutOfBoundsAlert = false
    @State private var rotationGestureAngle: Angle = .zero  // For pinch-to-rotate in move mode
    @ObservedObject private var resourceManager = RealityResourceManager.shared

    private static let outOfBoundsMessage = "Object moved out of bounds. Please move back to a position inside the area."

    var body: some View {
        ZStack {
            if resourceManager.canStartSession(.arDesign) {
                ARViewContainer(
                    design: design,
                    selectedItemForPlacement: $selectedItemForPlacement,
                    isMoveMode: isMoveMode,
                    pendingAction: $pendingAction,
                    placedItemIds: $placedItemIds,
                    rotationGestureAngle: $rotationGestureAngle,
                    onPlaced: { selectedItemForPlacement = nil },
                    onPlacedCountChanged: { placedCount = $0 },
                    onOutOfBounds: { speakOutOfBounds(); showOutOfBoundsAlert = true }
                )
                .ignoresSafeArea()
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                        Text("AR View Unavailable")
                            .font(Theme.Typography.title2)
                            .foregroundColor(.white)
                        Text("Room scanning is active. Close the scanner to view AR.")
                            .font(Theme.Typography.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }

            VStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Spacer(minLength: 0)

                    Button(action: { showFurnitureList = true }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Add")
                                .font(Theme.Typography.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("(\(placedCount))")
                                .font(Theme.Typography.caption)
                                .opacity(0.9)
                                .lineLimit(1)
                        }
                        .foregroundColor(Theme.Colors.darkBrown)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)

                    Button(action: { isMoveMode.toggle() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: isMoveMode ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.draw")
                                .font(.system(size: 14))
                            Text(isMoveMode ? "Moving" : "Move")
                                .font(Theme.Typography.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(isMoveMode ? .white : Theme.Colors.darkBrown)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Capsule().fill(isMoveMode ? Theme.Colors.mediumBrown : Theme.Colors.paleBeige.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)

                Spacer()

                VStack(spacing: Theme.Spacing.xs) {
                    if let selected = selectedItemForPlacement {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 16))
                            Text("Tap floor to place \(selected.name)")
                                .font(Theme.Typography.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                selectedItemForPlacement = nil
                            }
                            .font(Theme.Typography.caption.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.sm)
                        .background(Capsule().fill(Theme.Colors.mediumBrown.opacity(0.95)))
                    } else if isMoveMode {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tap item → tap ground. Tap again to cancel.")
                                    .font(Theme.Typography.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Text("Pinch to rotate.")
                                    .font(Theme.Typography.caption2)
                                    .opacity(0.9)
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: Theme.Spacing.xs) {
                                Button("Remove") {
                                    pendingAction = .removeSelected
                                }
                                .font(Theme.Typography.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Capsule().fill(Color.red.opacity(0.9)))
                                Button("Cancel") {
                                    pendingAction = .cancelMove
                                }
                                .font(Theme.Typography.caption2)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.sm)
                        .background(Capsule().fill(Theme.Colors.mediumBrown.opacity(0.95)))
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Add furniture, then move items.")
                                .font(Theme.Typography.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Button("Add") {
                                showFurnitureList = true
                            }
                            .font(Theme.Typography.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Capsule().fill(Theme.Colors.mediumBrown))
                        }
                        .foregroundColor(.white)
                        .padding(Theme.Spacing.sm)
                        .background(Capsule().fill(Theme.Colors.mediumBrown.opacity(0.8)))
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
            }
        }
        .sheet(isPresented: $showFurnitureList) {
            FurniturePlacementListView(
                furniture: design.furniture,
                placedItemIds: placedItemIds,
                selectedItem: $selectedItemForPlacement,
                onSelect: { item in
                    selectedItemForPlacement = item
                    showFurnitureList = false
                }
            )
        }
        .onAppear {
            _ = resourceManager.requestSession(.arDesign)
        }
        .onDisappear {
            resourceManager.releaseSession(.arDesign)
        }
        .alert("Out of Bounds", isPresented: $showOutOfBoundsAlert) {
            Button("OK", role: .cancel) { showOutOfBoundsAlert = false }
        } message: {
            Text(Self.outOfBoundsMessage)
        }
    }

    private func speakOutOfBounds() {
        let utterance = AVSpeechUtterance(string: Self.outOfBoundsMessage)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        AVSpeechSynthesizer().speak(utterance)
    }
}

struct FurniturePlacementListView: View {
    let furniture: [FurnitureItem]
    let placedItemIds: Set<UUID>
    @Binding var selectedItem: FurnitureItem?
    var onSelect: (FurnitureItem) -> Void
    @Environment(\.dismiss) var dismiss

    var totalCost: Double {
        furniture.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Recommended Furniture")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.horizontal)

                        Text("Select an item to place in your room. Tap the floor in AR to position it.")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(4)
                            .padding(.horizontal)

                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(furniture) { item in
                                FurniturePlacementItemRow(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id,
                                    isPlaced: placedItemIds.contains(item.id),
                                    onPlace: { onSelect(item) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Add to Room")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text("Total")
                            .font(Theme.Typography.caption2)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("$\(Int(totalCost))")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.primary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Colors.cardBackground))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "xmark")
                                .font(Theme.Typography.subheadline.weight(.semibold))
                            Text("Close")
                                .font(Theme.Typography.headline)
                        }
                        .foregroundColor(Theme.Colors.primary)
                    }
                }
            }
        }
    }
}

struct FurniturePlacementItemRow: View {
    let item: FurnitureItem
    let isSelected: Bool
    let isPlaced: Bool
    var onPlace: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Group {
                if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.secondaryBackground)
                            .overlay(Image(systemName: "chair.lounge.fill").foregroundColor(Theme.Colors.textSecondary))
                    }
                } else {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.secondaryBackground)
                        .overlay(Image(systemName: "chair.lounge.fill").foregroundColor(Theme.Colors.textSecondary))
                }
            }
            .frame(width: 80, height: 80)
            .cornerRadius(Theme.CornerRadius.md)
            .clipped()

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.name)
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                if let dims = item.dimensionsMeters, !dims.isEmpty {
                    Text(dims)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Text("$\(Int(item.price))")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primary)
            }

            Spacer()

            if isPlaced {
                Text("Placed")
                    .font(Theme.Typography.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                Button(action: onPlace) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Place")
                            .fontWeight(.semibold)
                    }
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Colors.mediumBrown))
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .fill(Theme.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .strokeBorder(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 2)
                )
        )
        .shadow(color: Theme.Shadow.small.color, radius: Theme.Shadow.small.radius, x: Theme.Shadow.small.x, y: Theme.Shadow.small.y)
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
                Theme.Colors.background.ignoresSafeArea()
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
                    .background(Capsule().fill(Theme.Colors.cardBackground))
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
            Group {
                if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .fill(Theme.Colors.secondaryBackground)
                            ProgressView().tint(Theme.Colors.primary)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.secondaryBackground)
                        .overlay(Image(systemName: "chair.lounge.fill").foregroundColor(Theme.Colors.textSecondary))
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

            if let buyURL = URL(string: item.url), !item.url.isEmpty {
                Link(destination: buyURL) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.mediumBrown, Theme.Colors.darkBrown],
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
        }
        .padding(Theme.Spacing.md)
        .floatingCardStyle()
    }
}
