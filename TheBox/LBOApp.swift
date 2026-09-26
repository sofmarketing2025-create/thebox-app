import SwiftUI
import SwiftData
import Observation
import UserNotifications

/// Estado compartilhado entre telas e com as ações do app Atalhos
@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var abrirRegistro = false
    var tourPasso: Int? = nil
    var bloqueado = UserDefaults.standard.bool(forKey: "faceID")
}

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    // Mostra o aviso ("R$ 20,00 registrado") mesmo com o app aberto
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct LBOApp: App {
    @State private var sessao = Sessao()
    @State private var estado = AppState.shared
    @AppStorage("tema") private var tema = "sistema"

    init() {
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
    }

    private var esquema: ColorScheme? {
        switch tema {
        case "claro": return .light
        case "escuro": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(sessao)
                .environment(estado)
                .preferredColorScheme(esquema)
                .tint(.primary)
        }
    }
}

struct RaizView: View {
    @Environment(Sessao.self) private var sessao

    var body: some View {
        Group {
            if let uid = sessao.uid {
                UsuarioView(uid: uid)
                    .modelContainer(Store.container(uid))
                    .id(uid)
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sessao.uid)
    }
}

/// Tudo que aparece depois do login: boas-vindas (1ª vez), app e bloqueio com Face ID
struct UsuarioView: View {
    let uid: String
    @Environment(AppState.self) private var estado
    @Environment(\.scenePhase) private var fase
    @Environment(\.modelContext) private var ctx
    @AppStorage private var onboardingFeito: Bool
    @AppStorage("faceID") private var faceID = false

    init(uid: String) {
        self.uid = uid
        _onboardingFeito = AppStorage(wrappedValue: false, "onboarding-" + uid)
    }

    var body: some View {
        ZStack {
            if onboardingFeito {
                MainView()
            } else {
                OnboardingView { withAnimation { onboardingFeito = true } }
            }
            if estado.bloqueado && faceID {
                TelaBloqueio { desbloquear() }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task {
            if onboardingFeito,
               await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
                _ = await Notificacoes.pedirPermissao()
            }
            Notificacoes.reagendar(ctx)
            if estado.bloqueado && faceID { desbloquear() }
        }
        .onChange(of: fase) { _, nova in
            switch nova {
            case .background:
                if faceID { estado.bloqueado = true }
                Notificacoes.reagendar(ctx)
            case .active:
                if estado.bloqueado && faceID { desbloquear() }
            default:
                break
            }
        }
    }

    private func desbloquear() {
        Task {
            if await Biometria.autenticar() {
                withAnimation { estado.bloqueado = false }
            }
        }
    }
}

struct TelaBloqueio: View {
    var desbloquear: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LogoView(tamanho: 96)
            Text("LBO FINANÇAS").font(.system(size: 13, weight: .medium)).tracking(5).foregroundStyle(.secondary)
            Spacer()
            Button {
                desbloquear()
            } label: {
                Label("Desbloquear", systemImage: "faceid")
            }
            .buttonStyle(EstiloPrincipal())
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fundo.ignoresSafeArea())
    }
}
