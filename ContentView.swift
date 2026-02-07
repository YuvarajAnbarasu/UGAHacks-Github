import SwiftUI
import SwiftData
import Foundation

// MARK: - Design System
struct DesignSystem {
    static let warmCream = Color(red: 0.98, green: 0.95, blue: 0.90)
    static let darkBrown = Color(red: 0.3, green: 0.25, blue: 0.20)
    static let mediumBrown = Color(red: 0.5, green: 0.4, blue: 0.3)
    static let lightBrown = Color(red: 0.7, green: 0.6, blue: 0.45)
    static let softBrown = Color(red: 0.85, green: 0.75, blue: 0.65)
    static let textDark = Color(red: 0.2, green: 0.15, blue: 0.12)
    static let textMedium = Color(red: 0.4, green: 0.35, blue: 0.3)
    static let cardBackground = Color.white
    static let shadowColor = Color.black.opacity(0.08)
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            DesignSystem.warmCream
                .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                ScanView()
                    .tabItem {
                        Label("Scan", systemImage: "viewfinder.circle.fill")
                    }
                    .tag(1)

                ResultsView()
                    .tabItem {
                        Label("Gallery", systemImage: "photo.stack.fill")
                    }
                    .tag(3)
            }
            .accentColor(DesignSystem.darkBrown)
            .onAppear {
                configureTabBarAppearance()
            }
        }
    }
    
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.white
        
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(DesignSystem.darkBrown)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(DesignSystem.darkBrown)]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(DesignSystem.textMedium)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(DesignSystem.textMedium)]
        
        // Add subtle shadow
        appearance.shadowColor = UIColor(DesignSystem.shadowColor)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Home View
struct HomeView: View {
    @Binding var selectedTab: Int
    @ObservedObject private var resultsVM = ResultsViewModel()
    @State private var itemsViewed = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Header with App Name and Notification
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Furnisher")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(DesignSystem.darkBrown)
                            
                            Text("Transform your space with AR")
                                .font(.subheadline)
                                .foregroundColor(DesignSystem.textMedium)
                        }
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "bell.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.darkBrown)
                                .frame(width: 48, height: 48)
                                .background(DesignSystem.cardBackground)
                                .clipShape(Circle())
                                .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, geometry.safeAreaInsets.top)
                    
                    // Hero Banner Card
                    if resultsVM.designs.isEmpty {
                        WelcomeBannerCard(selectedTab: $selectedTab)
                            .padding(.horizontal, 24)
                    } else {
                        PromotionBannerCard()
                            .padding(.horizontal, 24)
                    }
                    
                    // Recent Designs Section
                    if !resultsVM.designs.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text("Recent Designs")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.textDark)
                                
                                Spacer()
                                
                                Button(action: {
                                    withAnimation(.spring()) {
                                        selectedTab = 3
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Text("See all")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                    }
                                    .foregroundColor(DesignSystem.darkBrown)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(DesignSystem.darkBrown.opacity(0.08))
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(Array(resultsVM.designs.prefix(3).enumerated()), id: \.element.id) { index, design in
                                        RecentDesignCard(design: design, isLarge: index == 0)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    
                    // Your Wishlist Section
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Your Wishlist")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.textDark)
                            
                            Spacer()
                            
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundColor(DesignSystem.mediumBrown)
                        }
                        .padding(.horizontal, 24)
                        
                        VStack(spacing: 16) {
                            UniformStatCard(
                                title: "Designs Created",
                                value: "\(resultsVM.designs.count)",
                                icon: "cube.box.fill",
                                color: DesignSystem.darkBrown
                            )
                            
                            // Items Viewed card that navigates to gallery
                            Button(action: {
                                withAnimation(.spring()) {
                                    selectedTab = 3
                                }
                            }) {
                                UniformStatCard(
                                    title: "Items Viewed",
                                    value: "\(itemsViewed)",
                                    icon: "eye.fill",
                                    color: DesignSystem.mediumBrown
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Bottom spacing for tab bar
                    Spacer()
                        .frame(height: 120)
                }
            }
            .background(DesignSystem.warmCream)
            .navigationBarHidden(true)
            .onAppear {
                resultsVM.loadDesigns()
            }
        }
    }
}

// MARK: - New Modern Components

struct WelcomeBannerCard: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section with text
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transform Your Space")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.textDark)
                        .lineLimit(2)
                    
                    Text("Experience the future of interior design with AR technology. Scan your room and see furniture come to life.")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.textMedium)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                Button(action: {
                    withAnimation(.spring()) {
                        selectedTab = 1
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.headline)
                        Text("Start Scanning")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [DesignSystem.darkBrown, DesignSystem.mediumBrown],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(28)
                    .shadow(color: DesignSystem.darkBrown.opacity(0.3), radius: 12, x: 0, y: 8)
                }
            }
            .padding(28)
        }
        .background(DesignSystem.cardBackground)
        .cornerRadius(24)
        .shadow(color: DesignSystem.shadowColor, radius: 16, x: 0, y: 8)
    }
}

struct PromotionBannerCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today Only")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.darkBrown)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.darkBrown.opacity(0.1))
                        .cornerRadius(8)
                    
                    Spacer()
                }
                
                Text("Premium Features")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text("Unlock advanced AR design tools")
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.textMedium)
                
                Button(action: {}) {
                    Text("Upgrade Now")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DesignSystem.darkBrown)
                        .cornerRadius(20)
                }
            }
            
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.mediumBrown.opacity(0.3))
        }
        .padding(20)
        .background(DesignSystem.cardBackground)
        .cornerRadius(20)
        .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(color)
                        .cornerRadius(12)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.textDark)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DesignSystem.textMedium)
                }
            }
            .padding(16)
            .frame(width: 140, height: 120)
            .background(DesignSystem.cardBackground)
            .cornerRadius(16)
            .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
        }
    }
}

struct RecentDesignCard: View {
    let design: GeneratedDesign
    let isLarge: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .font(.title2)
                    .foregroundColor(DesignSystem.darkBrown)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.darkBrown.opacity(0.1))
                    .cornerRadius(10)
                
                Spacer()
                
                Text(design.timestamp.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.textMedium)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("\(design.furniture.count) Items")
                    .font(isLarge ? .title3 : .headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text("$\(Int(design.totalCost))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.mediumBrown)
                
                if isLarge {
                    Text("Tap to view in AR")
                        .font(.caption)
                        .foregroundColor(DesignSystem.textMedium)
                }
            }
        }
        .padding(16)
        .frame(width: isLarge ? 200 : 160, height: 140)
        .background(DesignSystem.cardBackground)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
    }
}

// MARK: - Uniform Stat Card for equal sizing (full width layout)
struct UniformStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(color)
                .cornerRadius(14)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.textDark)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.textMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(DesignSystem.cardBackground)
        .cornerRadius(20)
        .shadow(color: DesignSystem.shadowColor, radius: 12, x: 0, y: 6)
    }
}



// MARK: - Missing Components

struct ModernStatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let showRemoveButton: Bool
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(iconColor)
                    .cornerRadius(16)
                
                Spacer()
                
                if showRemoveButton {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DesignSystem.textMedium)
                            .font(.title2)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.textMedium)
            }
        }
        .padding(24)
        .background(DesignSystem.cardBackground)
        .cornerRadius(20)
        .shadow(color: DesignSystem.shadowColor, radius: 12, x: 0, y: 6)
    }
}

enum ModernActionButtonStyle {
    case primary, secondary, gradient
}

struct ModernActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let style: ModernActionButtonStyle
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 50, height: 50)
                    .background(iconBackgroundColor)
                    .cornerRadius(16)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(textColor)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(textColor.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(textColor)
            }
            .padding(20)
            .background(backgroundView)
        }
    }
    
    private var textColor: Color {
        switch style {
        case .primary:
            return DesignSystem.textDark
        case .secondary:
            return DesignSystem.textDark
        case .gradient:
            return .white
        }
    }
    
    private var iconColor: Color {
        switch style {
        case .primary, .secondary:
            return .white
        case .gradient:
            return .white
        }
    }
    
    private var iconBackgroundColor: Color {
        switch style {
        case .primary:
            return DesignSystem.darkBrown
        case .secondary:
            return DesignSystem.mediumBrown
        case .gradient:
            return .white.opacity(0.2)
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 20)
                .fill(DesignSystem.cardBackground)
                .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
        case .secondary:
            RoundedRectangle(cornerRadius: 20)
                .fill(DesignSystem.cardBackground)
                .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
        case .gradient:
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [DesignSystem.darkBrown, DesignSystem.mediumBrown],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
        }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(DesignSystem.darkBrown)
                .frame(width: 50, height: 50)
                .background(DesignSystem.darkBrown.opacity(0.1))
                .cornerRadius(16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.textMedium)
            }
            
            Spacer()
        }
        .padding(20)
        .background(DesignSystem.cardBackground)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadowColor, radius: 6, x: 0, y: 3)
    }
}

struct ModernLoadingOverlay: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        ZStack {
            DesignSystem.darkBrown.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(DesignSystem.darkBrown)
                
                VStack(spacing: 12) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.textDark)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.textMedium)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(DesignSystem.cardBackground)
            .cornerRadius(24)
            .shadow(color: DesignSystem.shadowColor, radius: 20, x: 0, y: 10)
        }
    }
}

struct ModernEmptyGalleryCard: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.box.fill")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.darkBrown)
                .frame(width: 100, height: 100)
                .background(DesignSystem.darkBrown.opacity(0.1))
                .cornerRadius(30)
            
            VStack(spacing: 12) {
                Text("No Designs Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text("Create your first AR furniture design by scanning a room and generating layouts")
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.textMedium)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(DesignSystem.cardBackground)
        .cornerRadius(24)
        .shadow(color: DesignSystem.shadowColor, radius: 12, x: 0, y: 6)
    }
}

struct ModernGalleryCard: View {
    let design: GeneratedDesign
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cube.box.fill")
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.darkBrown)
                    .cornerRadius(12)
                
                Spacer()
                
                Text(design.timestamp.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.textMedium)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("\(design.furniture.count) Items")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.textDark)
                
                Text("$\(Int(design.totalCost))")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.mediumBrown)
                
                Text("Tap to view in AR")
                    .font(.caption)
                    .foregroundColor(DesignSystem.textMedium)
            }
        }
        .padding(20)
        .background(DesignSystem.cardBackground)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
    }
}

struct ModernDesignSummaryCard: View {
    let furniture: [FurnitureItem]
    
    private var totalCost: Int {
        Int(furniture.reduce(0) { $0 + $1.price })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Design Summary")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.textDark)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.darkBrown)
                    .font(.title2)
            }
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(furniture.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.textDark)
                    Text("Items")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.textMedium)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("$\(totalCost)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.mediumBrown)
                    Text("Total Cost")
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.textMedium)
                }
                
                Spacer()
            }
        }
        .padding(24)
        .background(DesignSystem.cardBackground)
        .cornerRadius(20)
        .shadow(color: DesignSystem.shadowColor, radius: 12, x: 0, y: 6)
    }
}

struct ModernFurnitureItemCard: View {
    let item: FurnitureItem
    
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: item.imageUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.lightBrown.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(DesignSystem.textMedium)
                    )
            }
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(DesignSystem.textDark)
                    .lineLimit(2)
                
                Text("$\(Int(item.price))")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.mediumBrown)
            }
            
            Spacer()
            
            Link(destination: URL(string: item.url)!) {
                Text("Buy")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DesignSystem.darkBrown)
                    .cornerRadius(20)
            }
        }
        .padding(20)
        .background(DesignSystem.cardBackground)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadowColor, radius: 6, x: 0, y: 3)
    }
}

// MARK: - Furnished Result View
struct FurnishedResultView: View {
    let furniture: [FurnitureItem]
    let sceneId: String
    let roomModel: RoomModel?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Design Complete")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.textDark)
                                
                                Text("\(furniture.count) furniture items selected")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.textMedium)
                            }
                            
                            Spacer()
                            
                            Button("Done") {
                                dismiss()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DesignSystem.darkBrown)
                            .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // AR View Button
                    NavigationLink(destination: ARDesignView(design: GeneratedDesign(
                        sceneId: sceneId,
                        roomModel: roomModel,
                        furniture: furniture
                    ))) {
                        ModernActionButton(
                            title: "View in AR",
                            subtitle: "Experience your design in augmented reality",
                            icon: "arkit",
                            style: .gradient,
                            action: {}
                        )
                    }
                    .padding(.horizontal, 20)

                    // Summary Card
                    ModernDesignSummaryCard(furniture: furniture)
                        .padding(.horizontal, 20)

                    // Furniture List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Furniture Items")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.textDark)
                            .padding(.horizontal, 20)

                        LazyVStack(spacing: 12) {
                            ForEach(furniture) { (item: FurnitureItem) in
                                ModernFurnitureItemCard(item: item)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(DesignSystem.warmCream)
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Scan View
struct ScanView: View {
    @State private var showRoomScanner = false
    @State private var capturedRoomURL: URL?
    @ObservedObject private var furnishVM = FurnishViewModel()
    @State private var showResult = false

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Furnisher")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(DesignSystem.darkBrown)
                            
                            Text("3D Room Scanner")
                                .font(.subheadline)
                                .foregroundColor(DesignSystem.textMedium)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, geometry.safeAreaInsets.top)
                    
                    Spacer()
                    
                    // Main Content
                    VStack(spacing: 32) {
                        // Scan Button (no animated rings)
                        Button(action: {
                            showRoomScanner = true
                        }) {
                            VStack(spacing: 0) {
                                Image(systemName: "viewfinder.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 160, height: 160)
                            .background(
                                LinearGradient(
                                    colors: [DesignSystem.darkBrown, DesignSystem.mediumBrown],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: DesignSystem.darkBrown.opacity(0.4), radius: 20, x: 0, y: 12)
                        }
                        .scaleEffect(capturedRoomURL != nil ? 0.9 : 1.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: capturedRoomURL != nil)
                        
                        // Instruction Text
                        VStack(spacing: 12) {
                            if capturedRoomURL == nil {
                                Text("Ready to Scan")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(DesignSystem.textDark)
                                
                                Text("Tap the scanner to capture your room in 3D")
                                    .font(.subheadline)
                                    .foregroundColor(DesignSystem.textMedium)
                                    .multilineTextAlignment(.center)
                                
                                // Feature hints closer to main content
                                VStack(spacing: 16) {
                                    HStack(spacing: 24) {
                                        FeatureHint(icon: "cube.transparent", text: "3D Capture")
                                        FeatureHint(icon: "brain.head.profile", text: "AI Design")
                                        FeatureHint(icon: "arkit", text: "AR Preview")
                                    }
                                }
                                .padding(.top, 24)
                                
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                    
                                    Text("Room Scanned Successfully!")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(DesignSystem.textDark)
                                    
                                    Text("Your 3D room model is ready for design generation")
                                        .font(.subheadline)
                                        .foregroundColor(DesignSystem.textMedium)
                                        .multilineTextAlignment(.center)
                                    
                                    // Generate design button
                                    Button(action: {
                                        if let roomURL = capturedRoomURL {
                                            Task {
                                                await furnishVM.generateDesign(
                                                    fromRoomURL: roomURL,
                                                    roomType: "bedroom",
                                                    budget: "5000"
                                                )
                                                if furnishVM.result != nil {
                                                    showResult = true
                                                }
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "wand.and.stars")
                                                .font(.headline)
                                            Text("Generate Design")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 16)
                                        .background(
                                            LinearGradient(
                                                colors: [DesignSystem.mediumBrown, DesignSystem.lightBrown],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(28)
                                        .shadow(color: DesignSystem.mediumBrown.opacity(0.4), radius: 12, x: 0, y: 8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                    Spacer()
                }
            }
            .background(DesignSystem.warmCream)
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showRoomScanner) {
            if #available(iOS 16.0, *) {
                RoomPlanCaptureViewFixed(capturedRoomURL: $capturedRoomURL)
            }
        }
        .overlay {
            if furnishVM.isLoading {
                ModernLoadingOverlay(
                    title: "Creating Your Design...",
                    subtitle: "This may take 2-3 minutes"
                )
            }
        }
        .sheet(isPresented: $showResult) {
            if let result = furnishVM.result {
                FurnishedResultView(
                    furniture: result.furniture,
                    sceneId: result.sceneId,
                    roomModel: result.roomModel
                )
            }
        }
        .alert("Error", isPresented: .constant(furnishVM.errorMessage != nil)) {
            Button("OK") {
                furnishVM.errorMessage = nil
            }
        } message: {
            Text(furnishVM.errorMessage ?? "")
        }
    }
}

struct FeatureHint: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(DesignSystem.mediumBrown)
                .frame(width: 32, height: 32)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.textMedium)
        }
    }
}

// MARK: - Results View
struct ResultsView: View {
    @ObservedObject private var resultsVM = ResultsViewModel()
    @State private var selectedDesign: GeneratedDesign?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AR Design Gallery")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.textDark)
                            
                            Text("\(resultsVM.designs.count) designs created")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.textMedium)
                        }
                        
                        Spacer()
                        
                        if !resultsVM.designs.isEmpty {
                            Button(action: {
                                resultsVM.deleteAllDesigns()
                            }) {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.red.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(color: DesignSystem.shadowColor, radius: 4, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    if resultsVM.designs.isEmpty {
                        ModernEmptyGalleryCard()
                            .padding(.horizontal, 20)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 16) {
                            ForEach(resultsVM.designs) { (design: GeneratedDesign) in
                                ModernGalleryCard(design: design)
                                    .onTapGesture {
                                        selectedDesign = design
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(DesignSystem.warmCream)
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedDesign) { design in
                ARDesignView(design: design)
            }
            .onAppear {
                resultsVM.loadDesigns()
            }
        }
    }
}

#Preview("Main App") {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
