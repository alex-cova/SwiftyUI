import Foundation

/// Starter snippets for the Mockup tool's "Sample" menu — each exercises a different slice of
/// the supported subset so the preview has something real to show on first open.
public nonisolated struct MockupSample: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let source: String
}

public nonisolated enum MockupSamples {
    public static let all: [MockupSample] = [
        kyotoWeekend, profileCard, settingsList, loginForm, pricingRow, dashboard, multiplePreviews, navigationLinks,
        iOS26Showcase,
    ]

    public static let kyotoWeekend = MockupSample(
        title: "Kyoto weekend",
        source: """
        struct KyotoWeekend: View {
            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("SATURDAY · OCT 18")
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.orange)
                                    Text("Good morning, Mina")
                                        .font(.title2)
                                        .bold()
                                }
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 42, height: 42)
                                    Text("MK")
                                        .font(.callout)
                                        .bold()
                                        .foregroundStyle(.white)
                                }
                            }

                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(height: 220)

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label("CURATED ROUTE", systemImage: "sparkles")
                                            .font(.caption)
                                            .bold()
                                        Spacer()
                                        Image(systemName: "bookmark.fill")
                                    }

                                    Spacer()

                                    Text("Kyoto after rain")
                                        .font(.largeTitle)
                                        .bold()
                                    Text("Quiet temples, warm tea and lantern-lit alleys.")
                                        .font(.subheadline)
                                    HStack(spacing: 14) {
                                        Label("8 stops", systemImage: "mappin.and.ellipse")
                                        Label("4.2 km", systemImage: "figure.walk")
                                    }
                                    .font(.caption)
                                    .bold()
                                }
                                .foregroundStyle(.white)
                                .padding(22)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                            .shadow(color: .orange, radius: 14, y: 8)

                            HStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(.orange)
                                            .frame(width: 42, height: 42)
                                        Image(systemName: "figure.walk")
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Your pace")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("3 of 8 places")
                                            .font(.headline)
                                        ProgressView(value: 0.38)
                                            .tint(.orange)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 18).fill(.quaternary))

                                VStack(spacing: 5) {
                                    Image(systemName: "cloud.sun.fill")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                    Text("19°")
                                        .font(.title3)
                                        .bold()
                                    Text("Soft light")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(width: 104)
                                .background(RoundedRectangle(cornerRadius: 18).fill(.quaternary))
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Today")
                                        .font(.title2)
                                        .bold()
                                    Text("A slow route through Higashiyama")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Map", systemImage: "map") {}
                                    .buttonStyle(.glass)
                            }

                            PlanRow(
                                time: "09:30",
                                icon: "cup.and.saucer.fill",
                                title: "Kissa Kishin",
                                detail: "Breakfast · counter seat"
                            )
                            PlanRow(
                                time: "11:00",
                                icon: "leaf.fill",
                                title: "Shoren-in Garden",
                                detail: "Temple · 45 min"
                            )
                            PlanRow(
                                time: "13:15",
                                icon: "camera.fill",
                                title: "Sannenzaka",
                                detail: "Walk · ceramic shops"
                            )

                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(.teal)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Local note")
                                        .font(.headline)
                                    Text("Take the stone path behind Chion-in for a quieter approach.")
                                        .font(.caption)
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(
                                        colors: [.teal, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )

                            HStack(spacing: 10) {
                                Button("Share route", systemImage: "square.and.arrow.up") {}
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)
                                Button("Start walking", systemImage: "location.fill") {}
                                    .buttonStyle(.borderedProminent)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(18)
                    }
                    .navigationTitle("Field Guide")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("More", systemImage: "ellipsis") {}
                        }
                    }
                }
                .tint(.orange)
                .frame(width: 390, height: 820)
            }
        }

        struct PlanRow: View {
            var time: String
            var icon: String
            var title: String
            var detail: String

            var body: some View {
                HStack(spacing: 12) {
                    Text(time)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.orange)
                        .frame(width: 44)

                    ZStack {
                        Circle()
                            .fill(.orange)
                            .frame(width: 42, height: 42)
                        Image(systemName: icon)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(.quaternary))
            }
        }

        #Preview("Kyoto weekend") {
            KyotoWeekend()
        }
        """
    )

    public static let profileCard = MockupSample(
        title: "Profile card",
        source: """
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Ada Lovelace")
                .font(.title2)
                .bold()

            Text("Mathematician · Writer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label("Follow", systemImage: "plus")
                Label("Message", systemImage: "bubble.left")
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 280)
        .background(.gray)
        .cornerRadius(16)
        """
    )

    public static let settingsList = MockupSample(
        title: "Settings list",
        source: """
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink("Apple ID") {
                        Text("Apple ID")
                    }
                    NavigationLink("iCloud") {
                        Text("iCloud")
                    }
                    NavigationLink("Sign in & Security") {
                        Text("Sign in & Security")
                    }
                }

                Section("General") {
                    NavigationLink("Appearance") {
                        Text("Appearance")
                    }
                    NavigationLink("Notifications") {
                        Text("Notifications")
                    }
                    NavigationLink("Privacy") {
                        Text("Privacy")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .frame(width: 320, height: 360)
        """
    )

    public static let loginForm = MockupSample(
        title: "Login form",
        source: """
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome back")
                .font(.largeTitle)
                .bold()

            Text("Sign in to continue")
                .foregroundStyle(.secondary)

            TextField("Email", text: .constant(""))
            TextField("Password", text: .constant(""))

            Toggle("Remember me", isOn: .constant(false))
                .font(.callout)

            Button("Sign In") {}
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.tint)
                .foregroundStyle(.white)
                .cornerRadius(10)
        }
        .padding(28)
        .frame(width: 320)
        """
    )

    public static let dashboard = MockupSample(
        title: "Dashboard (state + subview)",
        source: """
        struct Dashboard: View {
            @State private var compact = false
            let heading = "Overview"

            var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text(heading)
                        .font(.largeTitle)
                        .bold()

                    Toggle("Compact layout", isOn: $compact)
                        .font(.callout)

                    if compact {
                        Text("Compact mode is on")
                            .foregroundStyle(.secondary)
                    } else {
                        StatGrid()
                    }

                    Button("See stats") {}
                        .onClickShow("StatGrid")
                }
                .padding(28)
                .frame(width: 360)
            }
        }

        struct StatGrid: View {
            var body: some View {
                HStack(spacing: 12) {
                    ForEach(0..<3) {
                        VStack(spacing: 6) {
                            Text("42")
                                .font(.system(size: 28, weight: .bold))
                            Text("metric")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                    }
                }
            }
        }
        """
    )

    public static let multiplePreviews = MockupSample(
        title: "Multiple previews",
        source: """
        struct Dashboard: View {
            @State private var compact = false
            let heading = "Overview"

            var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text(heading)
                        .font(.largeTitle)
                        .bold()

                    Toggle("Compact layout", isOn: $compact)
                        .font(.callout)

                    if compact {
                        Text("Compact mode is on")
                            .foregroundStyle(.secondary)
                    } else {
                        StatGrid()
                    }

                    Button("See stats") {}
                        .onClickShow("StatGrid")
                }
                .padding(28)
                .frame(width: 360)
            }
        }

        struct StatGrid: View {
            var body: some View {
                HStack(spacing: 12) {
                    ForEach(0..<3) {
                        VStack(spacing: 6) {
                            Text("42")
                                .font(.system(size: 28, weight: .bold))
                            Text("metric")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                    }
                }
            }
        }

        #Preview("Stats") {
            StatGrid()
        }

        #Preview("Capsule") {
            Capsule()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                .frame(width: 220, height: 64)
        }
        """
    )

    public static let pricingRow = MockupSample(
        title: "Pricing tiers",
        source: """
        HStack(spacing: 16) {
            ForEach(0..<3) {
                VStack(spacing: 10) {
                    Text("Plan")
                        .font(.headline)
                    Text("$9")
                        .font(.system(size: 40, weight: .bold))
                    Divider()
                    Text("Everything you need")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Choose") {}
                }
                .padding(20)
                .frame(width: 150, height: 220)
                .background(.gray)
                .cornerRadius(14)
            }
        }
        """
    )

    public static let navigationLinks = MockupSample(
        title: "Navigation links",
        source: """
        struct HomeView: View {
            var body: some View {
                NavigationStack {
                    List {
                        NavigationLink("Profile") {
                            ProfileView()
                        }
                        NavigationLink("Settings") {
                            SettingsView()
                        }
                    }
                    .navigationTitle("Home")
                }
            }
        }

        struct ProfileView: View {
            var body: some View {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 64))
                    Text("Alex")
                        .font(.title)
                    Text("Designer")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Profile")
            }
        }

        struct SettingsView: View {
            @State private var alerts = true
            var body: some View {
                List {
                    Toggle("Notifications", isOn: $alerts)
                    NavigationLink("Appearance") {
                        Text("Dark Mode")
                            .padding()
                    }
                }
                .navigationTitle("Settings")
            }
        }

        #Preview {
            HomeView()
        }
        """
    )

    public static let iOS26Showcase = MockupSample(
        title: "iOS 26 showcase",
        source: """
        struct MusicHome: View {
            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Now trending").font(.headline)
                                Text("Fresh picks, updated daily").foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .glassEffect(.regular.interactive())

                            GlassEffectContainer(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button("Play", systemImage: "play.fill") {}
                                        .buttonStyle(.glassProminent)
                                    Button("Shuffle", systemImage: "shuffle") {}
                                        .buttonStyle(.glass)
                                }
                            }

                            VStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .symbolRenderingMode(.hierarchical)
                                    .symbolEffect(.variableColor)
                                    .font(.system(size: 40))
                                Text("Concentric artwork frame")
                            }
                            .padding(20)
                            .background(.blue)
                            .clipShape(.concentric)
                        }
                        .padding()
                    }
                    .safeAreaBar(edge: .bottom) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Fields of Gold — playing")
                            Spacer()
                            Image(systemName: "pause.fill")
                        }
                        .padding(.horizontal, 12)
                    }
                    .navigationTitle("Music")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Edit") {}
                        }
                        ToolbarSpacer(.flexible, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add", systemImage: "plus") {}
                        }
                    }
                }
            }
        }

        struct LibraryTabs: View {
            var body: some View {
                TabView {
                    Tab("Home", systemImage: "house") {
                        MusicHome()
                    }
                    Tab("Library", systemImage: "books.vertical") {
                        Text("Library")
                    }
                    Tab(role: .search) {
                        Text("Search")
                    }
                }
                .tabViewBottomAccessory {
                    Label("Now Playing", systemImage: "play.fill")
                }
            }
        }

        #Preview {
            LibraryTabs()
        }
        """
    )
}
