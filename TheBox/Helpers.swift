import SwiftUI
import UIKit

let ptBR = Locale(identifier: "pt_BR")

// MARK: - Meses

enum Mes {
    static let nomes = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
                        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
    static let curtos = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]

    /// Índice do mês: ano * 12 + (mês - 1)
    static func indice(_ date: Date = .now) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return (c.year ?? 2026) * 12 + (c.month ?? 1) - 1
    }
    static func nome(_ i: Int) -> String { nomes[((i % 12) + 12) % 12] }
    static func curto(_ i: Int) -> String { curtos[((i % 12) + 12) % 12] }
    static func ano(_ i: Int) -> Int { i / 12 }
    static func chave(_ i: Int) -> String { String(format: "%04d-%02d", i / 12, i % 12 + 1) }

    /// Data de vencimento naquele mês (ajusta dia 31 em meses menores)
    static func data(_ i: Int, dia: Int, hora: Int = 9) -> Date {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = i / 12
        c.month = i % 12 + 1
        c.day = 1
        let primeiro = cal.date(from: c) ?? .now
        let dias = cal.range(of: .day, in: .month, for: primeiro)?.count ?? 28
        c.day = min(max(dia, 1), dias)
        c.hour = hora
        return cal.date(from: c) ?? primeiro
    }
}

// MARK: - Moeda

enum Moeda: String, CaseIterable, Identifiable {
    case BRL, USD, EUR, SGD, UYU, PYG, JPY
    var id: String { rawValue }
    var simbolo: String {
        switch self {
        case .BRL: return "R$"
        case .USD: return "US$"
        case .EUR: return "€"
        case .SGD: return "S$"
        case .UYU: return "$U"
        case .PYG: return "₲"
        case .JPY: return "¥"
        }
    }
    var nome: String {
        switch self {
        case .BRL: return "Real"
        case .USD: return "Dólar americano"
        case .EUR: return "Euro"
        case .SGD: return "Dólar de Singapura"
        case .UYU: return "Peso uruguaio"
        case .PYG: return "Guarani"
        case .JPY: return "Iene"
        }
    }
    static var atual: Moeda {
        Moeda(rawValue: UserDefaults.standard.string(forKey: "moeda") ?? "BRL") ?? .BRL
    }
}

extension Double {
    var moeda: String {
        formatted(.currency(code: Moeda.atual.rawValue).locale(ptBR))
    }
    var moedaInteira: String {
        formatted(.currency(code: Moeda.atual.rawValue).locale(ptBR).precision(.fractionLength(0)))
    }
    var curto: String {
        if self >= 1000 {
            return (self / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(ptBR)) + "k"
        }
        return String(Int(rounded()))
    }
    var textoCampo: String { String(format: "%.2f", self).replacingOccurrences(of: ".", with: ",") }
    var inteiro: String { formatted(.number.precision(.fractionLength(0)).locale(ptBR)) }
}

/// Formata o que foi digitado como dinheiro, contando centavos: "21655" → "216,55"
func mascaraDinheiro(_ texto: String) -> String {
    let digitos = String(texto.filter(\.isNumber).drop(while: { $0 == "0" }).prefix(11))
    guard !digitos.isEmpty else { return "" }
    let valor = Double(Int(digitos) ?? 0) / 100
    return valor.formatted(.number.precision(.fractionLength(2)).locale(ptBR))
}

/// Valor já existente no formato do campo com máscara ("1.000,00")
func textoDinheiro(_ v: Double) -> String {
    v > 0 ? v.formatted(.number.precision(.fractionLength(2)).locale(ptBR)) : ""
}

extension View {
    /// Aplica a máscara de dinheiro num campo de texto enquanto a pessoa digita
    func mascaraDinheiro(_ texto: Binding<String>) -> some View {
        self.keyboardType(.numberPad)
            .onChange(of: texto.wrappedValue) { _, novo in
                let f = TheBox.mascaraDinheiro(novo)
                if f != novo { texto.wrappedValue = f }
            }
    }
}

/// Converte "1.234,56" ou "12,5" em número
func lerValor(_ s: String) -> Double? {
    let limpo = s.replacingOccurrences(of: Moeda.atual.simbolo, with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: ",", with: ".")
    return Double(limpo)
}

func porcento(_ p: Double) -> String {
    guard p.isFinite else { return "0%" }
    return "\(Int((p * 100).rounded()))%"
}

func corPorcentagem(_ p: Double) -> Color {
    if p >= 1 { return .red }
    if p >= 0.8 { return .orange }
    return .green
}

// MARK: - Cores (se adaptam ao tema claro e escuro)

extension Color {
    static func dinamica(_ escuro: UIColor, _ claro: UIColor) -> Color {
        Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? escuro : claro })
    }
    static let fundo = dinamica(UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                                UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1))
    static let cartao = dinamica(UIColor(red: 0.125, green: 0.125, blue: 0.135, alpha: 1), .white)
    static let cartao2 = dinamica(UIColor(white: 0.2, alpha: 1), UIColor(white: 0.9, alpha: 1))
    static let borda = dinamica(UIColor(white: 1, alpha: 0.07), UIColor(white: 0, alpha: 0.06))
    /// Botão principal: branco no escuro, preto no claro
    static let destaque = dinamica(UIColor(white: 0.96, alpha: 1), UIColor(white: 0.08, alpha: 1))
    static let sobreDestaque = dinamica(UIColor(white: 0.08, alpha: 1), .white)
}

// MARK: - Estilos

struct EstiloCartao: ViewModifier {
    var padding: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.borda))
    }
}

struct EstiloCampo: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(Color.cartao2.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.borda))
    }
}

struct EstiloPrincipal: ButtonStyle {
    var ativo = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.sobreDestaque)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.destaque.opacity(ativo ? 1 : 0.35), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct EstiloContorno: ButtonStyle {
    var ativo = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(ativo ? 1 : 0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .overlay(Capsule().stroke(Color.primary.opacity(ativo ? 0.35 : 0.15), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func cartao(_ padding: CGFloat = 22) -> some View { modifier(EstiloCartao(padding: padding)) }
    func campo() -> some View { modifier(EstiloCampo()) }
    func folha(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        self.presentationDetents(detents)
            .presentationBackground(Color.cartao)
            .presentationCornerRadius(32)
            .presentationDragIndicator(.visible)
    }
    func tituloGrande() -> some View {
        self.font(.system(size: 29, weight: .heavy)).tracking(-1.2)
    }
}

// MARK: - Componentes

struct Cabecalho<Acoes: View>: View {
    let sub: String
    let titulo: String
    @ViewBuilder var acoes: () -> Acoes

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sub).font(.system(size: 14)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(titulo)
                    .font(.system(size: 27, weight: .heavy)).tracking(-0.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                acoes()
            }
        }
        .padding(.top, 8)
    }
}

extension Cabecalho where Acoes == EmptyView {
    init(sub: String, titulo: String) {
        self.init(sub: sub, titulo: titulo) { EmptyView() }
    }
}

struct BotaoCirculo: View {
    let icone: String
    var acao: () -> Void
    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .background(Color.cartao, in: Circle())
                .overlay(Circle().stroke(Color.borda))
        }
        .buttonStyle(.plain)
    }
}

struct BotaoFechar: View {
    var icone = "xmark"
    var acao: () -> Void
    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.cartao2.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct SeletorMes: View {
    @Binding var mes: Int
    @State private var aberto = false
    var body: some View {
        Button { aberto = true } label: {
            HStack(spacing: 6) {
                Text(Mes.curto(mes).uppercased()).font(.system(size: 14, weight: .bold)).tracking(1.5)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Color.cartao, in: Capsule())
            .overlay(Capsule().stroke(Color.borda))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $aberto) { SeletorMesSheet(mes: $mes) }
    }
}

struct SeletorMesSheet: View {
    @Binding var mes: Int
    @Environment(\.dismiss) private var dismiss
    @State private var ano: Int

    init(mes: Binding<Int>) {
        _mes = mes
        _ano = State(initialValue: Mes.ano(mes.wrappedValue))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Selecionar mês").font(.system(size: 19, weight: .bold))
                    Spacer()
                    Button { ano -= 1 } label: { Image(systemName: "chevron.left").padding(8) }
                    Text(String(ano)).font(.system(size: 15, weight: .bold)).frame(width: 60)
                    Button { ano += 1 } label: { Image(systemName: "chevron.right").padding(8) }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)

                ForEach(0..<12, id: \.self) { m in
                    let i = ano * 12 + m
                    Button {
                        mes = i
                        dismiss()
                    } label: {
                        HStack {
                            Text(Mes.nomes[m])
                                .font(.system(size: 15, weight: i == mes ? .bold : .regular))
                                .foregroundStyle(i == mes ? Color.primary : Color.secondary)
                            Spacer()
                            if i == mes { Image(systemName: "checkmark") }
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if m < 11 { Divider().overlay(Color.borda) }
                }
            }
            .padding(24)
            .padding(.top, 10)
        }
        .folha()
    }
}

struct Chip: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.cartao2, in: Capsule())
    }
}

/// Botão de opção (categoria, carteira) que fica branco quando selecionado
struct ChipOpcao: View {
    let texto: String
    var icone: String? = nil
    let selecionado: Bool
    var cheio = true
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                if let icone { Image(systemName: icone).font(.system(size: 14)) }
                Text(texto)
                    .font(.system(size: 14, weight: selecionado ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selecionado ? Color.sobreDestaque : Color.secondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: cheio ? .infinity : nil, alignment: .leading)
            .frame(height: 50)
            .background(selecionado ? Color.destaque : Color.cartao2.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Legenda: View {
    let cor: Color
    let texto: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(cor).frame(width: 9, height: 9)
            Text(texto).foregroundStyle(.secondary)
        }
    }
}

struct LinhaStat: View {
    let titulo: String
    let valor: String
    var destaque = false
    var body: some View {
        HStack {
            Text(titulo).foregroundStyle(destaque ? .primary : .secondary)
            Spacer()
            Text(valor).fontWeight(destaque ? .bold : .semibold)
        }
        .padding(.vertical, 12)
    }
}

struct Vazio: View {
    var icone = "tray"
    let titulo: String
    let texto: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icone).font(.system(size: 27)).foregroundStyle(.secondary)
            Text(titulo).font(.system(size: 15, weight: .semibold))
            Text(texto).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct AnelProgresso: View {
    let p: Double
    var tamanho: CGFloat = 64
    var linha: CGFloat = 4
    var cor: Color = .green
    var mostrarTexto = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.cartao2, lineWidth: linha)
            Circle()
                .trim(from: 0, to: min(max(p, 0), 1))
                .stroke(cor, style: StrokeStyle(lineWidth: linha, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if mostrarTexto {
                Text(porcento(p)).font(.system(size: tamanho * 0.2, weight: .semibold))
            }
        }
        .frame(width: tamanho, height: tamanho)
    }
}

struct BarraProgresso: View {
    let p: Double
    var cor: Color = .green
    var altura: CGFloat = 5

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.cartao2)
                if p > 0 {
                    Capsule().fill(cor).frame(width: max(altura * 2, g.size.width * min(max(p, 0), 1)))
                }
            }
        }
        .frame(height: altura)
    }
}

struct LogoView: View {
    var tamanho: CGFloat = 96
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: tamanho, height: tamanho)
            .clipShape(RoundedRectangle(cornerRadius: tamanho * 0.23, style: .continuous))
    }
}

struct IconeQuadrado: View {
    let icone: String
    var tamanho: CGFloat = 48
    var body: some View {
        Image(systemName: icone)
            .font(.system(size: tamanho * 0.4, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: tamanho, height: tamanho)
            .background(Color.cartao2.opacity(0.7), in: RoundedRectangle(cornerRadius: tamanho * 0.28, style: .continuous))
    }
}

struct LinhaToggle: View {
    let titulo: String
    var sub: String? = nil
    @Binding var ligado: Bool
    var body: some View {
        Toggle(isOn: $ligado) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.system(size: 14))
                if let sub { Text(sub).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .tint(Color(white: 0.55))
        .padding(.vertical, 12)
    }
}

/// Folha simples com título, subtítulo, um valor em dinheiro e "Salvar"
struct EditarValorSheet: View {
    let titulo: String
    let subtitulo: String
    let salvar: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var texto: String
    @FocusState private var foco: Bool

    init(titulo: String, subtitulo: String, valor: Double, salvar: @escaping (Double) -> Void) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.salvar = salvar
        _texto = State(initialValue: textoDinheiro(valor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo).font(.system(size: 19, weight: .bold))
            Text(subtitulo).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(Moeda.atual.simbolo).font(.system(size: 25, weight: .bold)).foregroundStyle(.secondary)
                TextField("0,00", text: $texto)
                    .font(.system(size: 30, weight: .bold))
                    .mascaraDinheiro($texto)
                    .focused($foco)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            Button("Salvar") {
                salvar(lerValor(texto) ?? 0)
                dismiss()
            }
            .buttonStyle(EstiloPrincipal())
        }
        .padding(28)
        .folha([.height(330)])
        .onAppear { foco = true }
    }
}

struct PontoMes: Identifiable {
    let mes: Int
    let valor: Double
    var id: Int { mes }
}

struct Compartilhar: UIViewControllerRepresentable {
    let itens: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: itens, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Arrastar pro lado pra apagar

/// Arrastando o cartão pro lado aparece uma lixeira vermelha; tocando nela, apaga.
struct DeslizarParaApagar: ViewModifier {
    let acao: () -> Void
    @State private var deslocamento: CGFloat = 0
    private let largura: CGFloat = 76

    func body(content: Content) -> some View {
        ZStack {
            HStack {
                if deslocamento > 0 { lixeira }
                Spacer()
                if deslocamento < 0 { lixeira }
            }
            content
                .offset(x: deslocamento)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { g in
                            guard abs(g.translation.width) > abs(g.translation.height) * 1.4 else { return }
                            deslocamento = max(-largura * 1.3, min(largura * 1.3, g.translation.width))
                        }
                        .onEnded { g in
                            withAnimation(.snappy(duration: 0.25)) {
                                if g.translation.width < -largura * 0.6 {
                                    deslocamento = -largura
                                } else if g.translation.width > largura * 0.6 {
                                    deslocamento = largura
                                } else {
                                    deslocamento = 0
                                }
                            }
                        }
                )
        }
    }

    private var lixeira: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { deslocamento = 0 }
            acao()
        } label: {
            Image(systemName: "trash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: largura - 10)
                .frame(maxHeight: .infinity)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

extension View {
    func deslizarParaApagar(_ acao: @escaping () -> Void) -> some View {
        modifier(DeslizarParaApagar(acao: acao))
    }
}
