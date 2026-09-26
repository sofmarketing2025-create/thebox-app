import Foundation

/// Dados do projeto no Supabase (Project Settings → API Keys).
/// A chave aqui é a pública (anon / publishable), feita pra ficar dentro do app.
enum Configuracao {
    static let supabaseURL = URL(string: "https://SEU-PROJETO.supabase.co")!
    static let supabaseChave = "SUA-CHAVE-PUBLICA"
}
