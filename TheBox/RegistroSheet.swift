import SwiftUI
import SwiftData

/// Tela de registrar (botão +, toque duplo nas costas ou tocando numa transação pra editar)
struct RegistroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]

    let editando: Transacao?
    @State private var tipo: TipoTransacao
    @State private var digitos: String
    @State private var categoria: String?
    @State private var carteira: String?
    @State private var descricao: String
    @State private var data: Date
    @State private var mostrarData = false
    @State private var confirmarExclusao = false
    @FocusState private var focoValor: Bool
    @FocusState private var focoDescricao: Bool

    init(editando: Transacao? = nil) {
        self.editando = editando
        _tipo = State(initialValue: editando?.tipo ?? .gasto)
        _digitos = State(initialValue: editando.map { String(Int(($0.valor * 100).rounded())) } ?? "")
        _categoria = State(initialValue: editando?.categoria)
        _carteira = State(initialValue: editando?.carteira)
        _descricao = State(initialValue: editando?.descricao ?? "")
        _data = State(initialValue: editando?.data ?? .now)
    }

    private var valor: Double { Double(Int(digitos) ?? 0) / 100 }
    private var cats: [Categoria] { categorias.filter { $0.tipo == tipo } }
    private var valido: Bool { valor > 0 && categoria != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topo
                    if mostrarData {
                        DatePicker("Data", selection: $data, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    SeletorTipo(tipo: $tipo)
                    campoValor
                    gradeCategorias
                    if tipo == .gasto { impacto }
                    pagamentos
                    TextField(tipo == .gasto ? "Onde foi? (opcional)" : "De onde veio? (opcional)", text: $descricao)
                        .focused($focoDescricao)
                        .submitLabel(.done)
                        .campo()
                    Button(editando == nil ? "Registrar" : "Salvar") { salvar() }
                        .buttonStyle(EstiloPrincipal(ativo: valido))
                        .disabled(!valido)
                    if editando != nil {
                        Button("Excluir", role: .destructive) { confirmarExclusao = true }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.cartao)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        focoValor = false
                        focoDescricao = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .folha()
        .onChange(of: tipo) { _, _ in
            if !cats.contains(where: { $0.nome == categoria }) { categoria = nil }
        }
        .onChange(of: digitos) { _, novo in
            let limpo = String(novo.filter(\.isNumber).prefix(9))
            if limpo != novo { digitos = limpo }
        }
        .onAppear {
            if carteira == nil { carteira = carteiras.first?.nome }
            if editando == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focoValor = true }
            }
        }
        .confirmationDialog("Excluir esta transação?", isPresented: $confirmarExclusao, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                if let editando { Exclusao.transacao(editando, ctx: ctx) }
                dismiss()
            }
        }
    }

    // MARK: Partes

    private var topo: some View {
        HStack {
            Button {
                withAnimation { mostrarData.toggle() }
            } label: {
                Label(textoData, systemImage: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color.cartao2.opacity(0.6), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            BotaoFechar { dismiss() }
        }
    }

    private var textoData: String {
        let cal = Calendar.current
        if cal.isDateInToday(data) { return "Hoje" }
        if cal.isDateInYesterday(data) { return "Ontem" }
        if cal.isDateInTomorrow(data) { return "Amanhã" }
        return data.formatted(.dateTime.day().month(.abbreviated).locale(ptBR))
    }

    private var campoValor: some View {
        VStack(spacing: 2) {
            Text(Moeda.atual.simbolo).font(.system(size: 14)).foregroundStyle(.secondary)
            ZStack {
                TextField("", text: $digitos)
                    .keyboardType(.numberPad)
                    .focused($focoValor)
                    .opacity(0.02)
                    .frame(width: 2, height: 2)
                Text(valor.formatted(.number.precision(.fractionLength(2)).locale(ptBR)))
                    .font(.system(size: 52, weight: .heavy)).tracking(-2.5)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(valor > 0 ? Color.primary : Color.secondary.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focoValor = true }
    }

    private var gradeCategorias: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(cats) { c in
                ChipOpcao(texto: c.nome, icone: c.icone, selecionado: categoria == c.nome) {
                    categoria = c.nome
                    focoValor = false
                }
            }
        }
    }

    @ViewBuilder
    private var impacto: some View {
        if let nome = categoria, let cat = cats.first(where: { $0.nome == nome }), cat.limite > 0, valor > 0 {
            let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
            let anterior = editando?.categoria == nome ? (editando?.valor ?? 0) : 0
            let ja = (fin.gastoPorCategoria(em: Mes.indice(data))[nome] ?? 0) - anterior
            let p = (ja + valor) / cat.limite
            VStack(alignment: .leading, spacing: 8) {
                BarraProgresso(p: p, cor: corPorcentagem(p), altura: 4)
                Text("Isso deixa \(nome) em \(porcento(p)) do orçamento do mês.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pagamentos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tipo == .gasto ? "Como você pagou?" : "Onde entrou?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(carteiras) { c in
                        ChipOpcao(texto: c.nome, icone: c.tipo.icone, selecionado: carteira == c.nome, cheio: false) {
                            carteira = c.nome
                        }
                    }
                }
            }
        }
    }

    private func salvar() {
        guard valido, let categoria else { return }
        let desc = descricao.trimmingCharacters(in: .whitespaces)
        let cart = carteira ?? ""
        if let t = editando {
            t.tipoRaw = tipo.rawValue
            t.valor = valor
            t.categoria = categoria
            t.carteira = cart
            t.descricao = desc
            t.data = data
            try? ctx.save()
        } else {
            ctx.insert(Transacao(tipo: tipo, valor: valor, categoria: categoria, carteira: cart, descricao: desc, data: data))
            try? ctx.save()
            Notificacoes.registrado(valor: valor, titulo: desc.isEmpty ? tipo.nome : desc, categoria: categoria)
            if tipo == .gasto {
                Notificacoes.verificarLimite(categoria: categoria, valor: valor, data: data, ctx: ctx)
            }
        }
        Notificacoes.reagendar(ctx)
        dismiss()
    }
}

struct SeletorTipo: View {
    @Binding var tipo: TipoTransacao

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TipoTransacao.allCases) { t in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { tipo = t }
                } label: {
                    Text(t.nome)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tipo == t ? Color.sobreDestaque : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            if tipo == t {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.destaque)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.cartao2.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
