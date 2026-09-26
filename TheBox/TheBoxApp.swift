import SwiftUI
import SwiftData

@MainActor
enum Store {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Conta.self, Gasto.self)
        } catch {
            fatalError("Não foi possível abrir o banco de dados: \(error)")
        }
    }()
}

@main
struct TheBoxApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.white)
        }
        .modelContainer(Store.container)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var fase
    @Environment(\.modelContext) private var ctx

    var body: some View {
        TabView {
            ContasView()
                .tabItem { Label("Contas", systemImage: "calendar.badge.clock") }
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            AnaliseView()
                .tabItem { Label("Análise", systemImage: "chart.bar") }
            ConfigView()
                .tabItem { Label("Config", systemImage: "gearshape") }
        }
        .task {
            _ = await Notificacoes.pedirPermissao()
            Notificacoes.reagendar(ctx)
        }
        .onChange(of: fase) { _, nova in
            if nova != .active { Notificacoes.reagendar(ctx) }
        }
    }
}
