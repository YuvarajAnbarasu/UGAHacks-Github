import SwiftUI
import SwiftData
import Foundation

// MARK: - Design System
struct DesignSystem {
    static let warmCream = Color(red: 0.98, green: 0.95, blue: 0.90)
    static let warmCreamDeep = Color(red: 0.95, green: 0.91, blue: 0.85)
    // Premium gradient background (replaces light tan)
    static let gradientDark = Color(red: 0x3A/255, green: 0x1F/255, blue: 0x12/255)   // #3A1F12
    static let gradientMid = Color(red: 0x6B/255, green: 0x3F/255, blue: 0x24/255)   // #6B3F24
    static let gradientLight = Color(red: 0xB0/255, green: 0x7A/255, blue: 0x4F/255) // #B07A4F
    static let sand = Color(red: 0xF3/255, green: 0xE4/255, blue: 0xD3/255)           // #F3E4D3
    static let caramel = Color(red: 0xD6/255, green: 0xB1/255, blue: 0x8A/255)      // #D6B18A
    static let darkBrown = Color(red: 0.3, green: 0.25, blue: 0.20)
    static let mediumBrown = Color(red: 0.5, green: 0.4, blue: 0.3)
    static let lightBrown = Color(red: 0.7, green: 0.6, blue: 0.45)
    static let softBrown = Color(red: 0.85, green: 0.75, blue: 0.65)
    /// Tan, lighter text (card titles, labels)
    static let textDark = Color(red: 0x6B/255, green: 0x4A/255, blue: 0x32/255)
    /// Lighter tan (descriptions, secondary text)
    static let textMedium = Color(red: 0x8B/255, green: 0x6A/255, blue: 0x52/255)
    /// Tan card background (replaces white boxes)
    static let cardBackground = Color(red: 0xF5/255, green: 0xEB/255, blue: 0xDE/255)
    static let shadowColor = Color.black.opacity(0.08)
    static let shadowWarm = Color(red: 0.35, green: 0.28, blue: 0.22).opacity(0.12)
    
    /// 160deg gradient: #3A1F12 → #6B3F24 → #B07A4F (premium fintech-style background)
    static var appBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [gradientDark, gradientMid, gradientLight],
            startPoint: UnitPoint(x: 0.2, y: 0),
            endPoint: UnitPoint(x: 0.9, y: 1.0)
        )
    }
}

// MARK: - Grain overlay for premium look (2–4% black, overlay blend)
// Disabled in Xcode Previews to avoid Canvas overload crash.
struct GrainOverlayView: View {
    var opacity: Double = 0.03
    var blendMode: BlendMode = .overlay
    
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
    
    var body: some View {
        GeometryReader { geo in
            if isPreview {
                Color.clear
            } else {
                Canvas { context, size in
                    let w = min(Int(size.width), 400)
                    let h = min(Int(size.height), 600)
                    let dotSpacing = 4
                    for x in stride(from: 0, to: w, by: dotSpacing) {
                        for y in stride(from: 0, to: h, by: dotSpacing) {
                            let raw = x &* 73856093 ^ y &* 19349663
                            let seed = UInt32(truncatingIfNeeded: raw)
                            let alpha = Double((seed % 100)) / 100.0 * opacity
                            context.fill(
                                Path(ellipseIn: CGRect(x: Double(x), y: Double(y), width: 1.5, height: 1.5)),
                                with: .color(.black.opacity(alpha))
                            )
                        }
                    }
                }
                .blendMode(blendMode)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - App background (gradient + optional grain)
struct AppBackgroundView: View {
    var withGrain: Bool = true
    
    var body: some View {
        ZStack {
            DesignSystem.appBackgroundGradient
                .ignoresSafeArea()
            if withGrain {
                GrainOverlayView(opacity: 0.03, blendMode: .overlay)
            }
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            AppBackgroundView(withGrain: true)
            
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
        
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(DesignSystem.caramel)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(DesignSystem.caramel)]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(DesignSystem.caramel.opacity(0.8))
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(DesignSystem.caramel.opacity(0.8))]
        
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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Decor")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(DesignSystem.sand)
                            
                            Text("Transform your space with AR")
                                .font(.subheadline)
                                .foregroundColor(DesignSystem.sand.opacity(0.9))
                        }
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "bell.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.textDark)
                                .frame(width: 48, height: 48)
                                .background(DesignSystem.cardBackground)
                                .clipShape(Circle())
                                .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, geometry.safeAreaInsets.top)
                    
                    // Hero Banner Card – always "Transform Your Space"
                    WelcomeBannerCard(selectedTab: $selectedTab)
                        .padding(.horizontal, 24)
                    
                    // Recent Designs Section
                    if !resultsVM.designs.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text("Recent Designs")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.sand)
                                
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
                                    .foregroundColor(DesignSystem.textDark)
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
                                .foregroundColor(DesignSystem.sand)
                            
                            Spacer()
                            
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundColor(DesignSystem.textMedium)
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
            .background(AppBackgroundView(withGrain: true))
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
                        .foregroundColor(DesignSystem.textDark)
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
                    .foregroundColor(DesignSystem.textDark)
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
                    .foregroundColor(DesignSystem.textMedium)
                
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
                .foregroundColor(DesignSystem.textDark)
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
                .foregroundColor(DesignSystem.textDark)
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
                    .foregroundColor(DesignSystem.textMedium)
                
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
                    .foregroundColor(DesignSystem.textDark)
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
                        .foregroundColor(DesignSystem.textMedium)
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
            Group {
                if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                    AsyncImage(url: url) { image in
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
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.lightBrown.opacity(0.3))
                        .overlay(
                            Image(systemName: "chair.lounge.fill")
                                .foregroundColor(DesignSystem.textMedium)
                        )
                }
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
                    .foregroundColor(DesignSystem.textMedium)
                
                if let dims = item.dimensionsMeters, !dims.isEmpty {
                    Text(dims)
                        .font(.caption)
                        .foregroundColor(DesignSystem.textMedium)
                }
            }
            
            Spacer()
            
            if let buyURL = URL(string: item.url), !item.url.isEmpty {
                Link(destination: buyURL) {
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
    @State private var showAR = false

    private var arDesign: GeneratedDesign {
        GeneratedDesign(sceneId: sceneId, roomModel: roomModel, furniture: furniture)
    }

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
                                    .foregroundColor(DesignSystem.caramel)
                                
                                Text(furniture.isEmpty && roomModel != nil
                                     ? "Your room is ready to view in AR"
                                     : "\(furniture.count) furniture items selected")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.caramel)
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

                    // View in AR – single button triggers fullScreenCover (nested Button was swallowing taps)
                    ModernActionButton(
                        title: "View in AR",
                        subtitle: furniture.isEmpty && roomModel != nil
                            ? "See your scanned room in augmented reality"
                            : "Experience your design in augmented reality",
                        icon: "arkit",
                        style: .gradient,
                        action: { showAR = true }
                    )
                    .padding(.horizontal, 20)
                    .fullScreenCover(isPresented: $showAR) {
                        ARDesignView(design: arDesign)
                    }

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
            .background(AppBackgroundView(withGrain: true))
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Scan View
struct ScanView: View {
    @State private var showRoomScanner = false
    @State private var capturedRoomURL: URL?
    @State private var selectedRoomType = "bedroom"
    @ObservedObject private var furnishVM = FurnishViewModel()
    @State private var showResult = false
    @State private var contentAppeared = false
    
    private static let roomTypes = ["bedroom", "living room", "kitchen", "office", "dining room", "bathroom"]

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header (hidden on Room Scanned Successfully screen)
                    if capturedRoomURL == nil {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Decor")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(DesignSystem.sand)
                                
                                Text("3D Room Scanner")
                                    .font(.subheadline)
                                    .foregroundColor(DesignSystem.sand.opacity(0.9))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, geometry.safeAreaInsets.top)
                        
                        Spacer()
                    }
                    
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
                                    colors: [DesignSystem.gradientMid, DesignSystem.gradientLight, DesignSystem.caramel],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(DesignSystem.sand.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: DesignSystem.shadowWarm, radius: 16, x: 0, y: 8)
                            .shadow(color: DesignSystem.darkBrown.opacity(0.25), radius: 24, x: 0, y: 12)
                        }
                        .scaleEffect(capturedRoomURL != nil ? 0.9 : (contentAppeared ? 1.0 : 0.92))
                        .opacity(contentAppeared ? 1 : 0.96)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: capturedRoomURL != nil)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: contentAppeared)
                        
                        // Instruction Text
                        VStack(spacing: 12) {
                            if capturedRoomURL == nil {
                                VStack(spacing: 12) {
                                    Text("Ready to Scan")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(DesignSystem.sand)
                                    
                                    Text("Tap the scanner to capture your room in 3D")
                                        .font(.subheadline)
                                        .foregroundColor(DesignSystem.sand.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                }
                                .opacity(contentAppeared ? 1 : 0)
                                .offset(y: contentAppeared ? 0 : 6)
                                .animation(.easeOut(duration: 0.4).delay(0.08), value: contentAppeared)
                                
                                // Feature hints – soft pills
                                VStack(spacing: 16) {
                                    HStack(spacing: 20) {
                                        FeatureHint(icon: "cube.transparent", text: "3D Capture")
                                        FeatureHint(icon: "brain.head.profile", text: "AI Design")
                                        FeatureHint(icon: "arkit", text: "AR Preview")
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(DesignSystem.cardBackground)
                                            .shadow(color: DesignSystem.shadowColor, radius: 10, x: 0, y: 4)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(DesignSystem.softBrown.opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .padding(.top, 24)
                                .opacity(contentAppeared ? 1 : 0)
                                .offset(y: contentAppeared ? 0 : 8)
                                .animation(.easeOut(duration: 0.4).delay(0.15), value: contentAppeared)
                                
                            } else {
                                VStack(spacing: 20) {
                                    // Visual cue: file created
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.fill")
                                            .font(.title2)
                                            .foregroundColor(DesignSystem.textDark)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Room file created")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(DesignSystem.textDark)
                                            Text(capturedRoomURL?.lastPathComponent ?? "room.usdz")
                                                .font(.caption)
                                                .foregroundColor(DesignSystem.textMedium)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title3)
                                    }
                                    .padding(18)
                                    .background(DesignSystem.cardBackground)
                                    .cornerRadius(20)
                                    .shadow(color: DesignSystem.shadowWarm, radius: 12, x: 0, y: 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(DesignSystem.softBrown.opacity(0.2), lineWidth: 1)
                                    )
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(Color(red: 0.35, green: 0.7, blue: 0.4))
                                    
                                    Text("Room Scanned Successfully!")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    // Room Type – its own card (same style as "Room file created")
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.grid.2x2.fill")
                                            .font(.title2)
                                            .foregroundColor(DesignSystem.textDark)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Room type")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(DesignSystem.textDark)
                                            Picker("Room type", selection: $selectedRoomType) {
                                                ForEach(Self.roomTypes, id: \.self) { type in
                                                    Text(type.capitalized).tag(type)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .tint(DesignSystem.textDark)
                                        }
                                        Spacer()
                                    }
                                    .padding(18)
                                    .background(DesignSystem.cardBackground)
                                    .cornerRadius(20)
                                    .shadow(color: DesignSystem.shadowWarm, radius: 12, x: 0, y: 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(DesignSystem.softBrown.opacity(0.2), lineWidth: 1)
                                    )
                                    
                                    Button(action: {
                                        if let roomURL = capturedRoomURL {
                                            Task {
                                                await furnishVM.generateDesign(
                                                    fromRoomURL: roomURL,
                                                    roomType: selectedRoomType,
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
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(DesignSystem.caramel)
                                        .cornerRadius(14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, capturedRoomURL != nil ? 28 : 0)
                    }
                    
                    Spacer()
                    Spacer()
                }
            }
            .background(AppBackgroundView(withGrain: true))
            .navigationBarHidden(true)
            .onAppear {
                guard !contentAppeared else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        contentAppeared = true
                    }
                }
            }
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
        .onChange(of: furnishVM.result?.sceneId) { _, newValue in
            if newValue != nil {
                showResult = true
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
                .foregroundColor(DesignSystem.textMedium)
                .frame(width: 32, height: 32)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.textMedium)
        }
    }
}

// MARK: - Furniture list item (from room designs)
struct FurnitureListRowView: View {
    let item: FurnitureItem
    let designDate: Date?

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: item.price)) ?? "$\(Int(item.price))"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail or placeholder
            Group {
                if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            Image(systemName: "chair.lounge.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.textMedium)
                        @unknown default:
                            Image(systemName: "chair.lounge.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.textMedium)
                        }
                    }
                } else {
                    Image(systemName: "chair.lounge.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.textMedium)
                }
            }
            .frame(width: 56, height: 56)
            .background(DesignSystem.softBrown.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.textDark)
                    .lineLimit(2)
                if let date = designDate {
                    Text("From design \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.caption)
                        .foregroundColor(DesignSystem.textMedium)
                }
                Text(formattedPrice)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.textMedium)
                if let dims = item.dimensionsMeters, !dims.isEmpty {
                    Text(dims)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.textMedium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = URL(string: item.url), !item.url.isEmpty {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.title3)
                        Text("Buy")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [DesignSystem.darkBrown, DesignSystem.mediumBrown],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(DesignSystem.cardBackground)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadowColor, radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(DesignSystem.softBrown.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Results View (Furniture list from designs)
struct ResultsView: View {
    @ObservedObject private var resultsVM = ResultsViewModel()
    @State private var selectedDesign: GeneratedDesign?

    /// All furniture from all designs, with design date for context
    private var furnitureWithSource: [(item: FurnitureItem, design: GeneratedDesign)] {
        resultsVM.designs.flatMap { design in
            design.furniture.map { (item: $0, design: design) }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header (light text on gradient)
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Furniture")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.sand)
                            
                            if furnitureWithSource.isEmpty {
                                Text(resultsVM.designs.isEmpty ? "currently, you have no furniture added. " : "No furniture in designs yet")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.sand.opacity(0.85))
                            } else {
                                Text("\(furnitureWithSource.count) item\(furnitureWithSource.count == 1 ? "" : "s") from \(resultsVM.designs.count) design\(resultsVM.designs.count == 1 ? "" : "s")")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.sand.opacity(0.85))
                            }
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

                    if furnitureWithSource.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: "chair.lounge.fill")
                                .font(.system(size: 56))
                                .foregroundColor(DesignSystem.textDark)
                                .frame(width: 100, height: 100)
                                .background(DesignSystem.darkBrown.opacity(0.1))
                                .cornerRadius(30)
                            
                            VStack(spacing: 12) {
                                Text("No furniture yet")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.textDark)
                                
                                Text("Generate a design from a scanned room to see items, cost, and links to purchase online.")
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
                        .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(furnitureWithSource.enumerated()), id: \.offset) { _, pair in
                                FurnitureListRowView(item: pair.item, designDate: pair.design.timestamp)
                                    .onTapGesture {
                                        selectedDesign = pair.design
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .background(AppBackgroundView(withGrain: true))
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
