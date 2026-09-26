import Foundation
import LocalAuthentication

enum Biometria {
    /// Face ID (ou o código do iPhone, se o Face ID falhar)
    static func autenticar() async -> Bool {
        let contexto = LAContext()
        var erro: NSError?
        guard contexto.canEvaluatePolicy(.deviceOwnerAuthentication, error: &erro) else { return false }
        return (try? await contexto.evaluatePolicy(.deviceOwnerAuthentication,
                                                   localizedReason: "Desbloquear o LBO Finanças")) ?? false
    }
}
