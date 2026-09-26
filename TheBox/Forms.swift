import SwiftUI
import SwiftData

struct FormConta: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let conta: Conta?

    @State private var nome: String
    @State private var valorTexto: String
    @State private var dia: Int
    @State private var tipo: TipoConta
    @State private var mesesTexto: String
    @State private var inicio: Int
    @State private var confirmarExclusao = false

    init(conta: Conta?, mesInicial: Int) {
        self.conta = conta
        _nome = State(initialValue: conta?.nome ?? "")
        _valorTexto = State(initialValue: conta?.valor.textoCampo ?? "")
        _dia = State(initialValue: conta?.dia ?? 10)
        _tipo = State(initialValue: conta?.tipo ?? .fixo)
        let m = conta?.meses ?? 0
        _mesesTexto = State(initialValue: m > 0 ? String(m) : "")
        _inicio = State(initialValue: conta?.inicio ?? mesInicial)
    }

    private var valor: Double? { lerValor(valorTexto) }
    private var meses: Int { Int(mesesTexto) ?? 0 }
    private var valido: Bool {
        !nome.trimmingCharacters(in: .whitespaces).isEmpty
            && (valor ?? 0) > 0
            && (tipo != .parcelado || meses > 0)
    }
    private var dica: String {
        switch tipo {
        case .fixo: return "Repete todo mês. Deixe a quantidade de meses em branco para não ter fim."
        case .parcelado: return "Mostra a parcela atual, como 3/12."
        case .unico: return "Aparece só no mês escolhido."
        }
    }

    var body: some View {
        let hoje = Mes.indice()
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (ex.: Wi-Fi, aluguel)", text: $nome)
                    TextField("Valor (R$)", text: $valorTexto).keyboardType(.decimalPad)
                    Picker("Dia de vencimento", selection: $dia) {
                        ForEach(1...31, id: \.self) { d in Text("\(d)").tag(d) }
                    }
                }

                Section {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoConta.allCases) { t in Text(t.nome).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Começa em", selection: $inicio) {
                        ForEach((hoje - 12)...(hoje + 12), id: \.self) { i in
                            Text("\(Mes.nome(i)) \(String(Mes.ano(i)))").tag(i)
                        }
                    }
                    if tipo != .unico {
                        TextField(tipo == .parcelado ? "Nº de parcelas" : "Por quantos meses (opcional)",
                                  text: $mesesTexto)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text(dica)
                }

                if conta != nil {
                    Section {
                        Button("Excluir conta", role: .destructive) { confirmarExclusao = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo)
            .navigationTitle(conta == nil ? "Nova conta" : "Editar conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { salvar() }.bold().disabled(!valido)
                }
            }
            .confirmationDialog("Excluir esta conta de todos os meses?",
                                isPresented: $confirmarExclusao, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let conta { ctx.delete(conta) }
                    try? ctx.save()
                    Notificacoes.reagendar(ctx)
                    dismiss()
                }
            }
        }
    }

    private func salvar() {
        guard let v = valor, v > 0 else { return }
        let nomeLimpo = nome.trimmingCharacters(in: .whitespaces)
        let m = tipo == .unico ? 0 : meses
        if let conta {
            conta.nome = nomeLimpo
            conta.valor = v
            conta.dia = dia
            conta.tipo = tipo
            conta.meses = m
            conta.inicio = inicio
        } else {
            ctx.insert(Conta(nome: nomeLimpo, valor: v, dia: dia, tipo: tipo, meses: m, inicio: inicio))
        }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        dismiss()
    }
}

struct FormGasto: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let gasto: Gasto?

    @State private var valorTexto: String
    @State private var descricao: String
    @State private var categoria: Categoria
    @State private var pagamento: Pagamento
    @State private var data: Date
    @State private var confirmarExclusao = false

    init(gasto: Gasto?) {
        self.gasto = gasto
        _valorTexto = State(initialValue: gasto?.valor.textoCampo ?? "")
        _descricao = State(initialValue: gasto?.descricao ?? "")
        _categoria = State(initialValue: gasto?.categoria ?? .alimentacao)
        _pagamento = State(initialValue: gasto?.pagamento ?? .credito)
        _data = State(initialValue: gasto?.data ?? .now)
    }

    private var valor: Double? { lerValor(valorTexto) }
    private let colunas = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Valor (R$)", text: $valorTexto).keyboardType(.decimalPad)
                    TextField("Descrição", text: $descricao)
                }

                Section("Categoria") {
                    LazyVGrid(columns: colunas, spacing: 12) {
                        ForEach(Categoria.allCases) { c in
                            Button { categoria = c } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: c.icone)
                                        .font(.system(size: 18))
                                        .foregroundStyle(categoria == c ? Color.black : Color.white)
                                        .frame(width: 46, height: 46)
                                        .background(categoria == c ? Color.white : Color.cartao2,
                                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    Text(c.nome)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Tipo de pagamento") {
                    Picker("Tipo de pagamento", selection: $pagamento) {
                        ForEach(Pagamento.allCases) { p in Text(p.nome).tag(p) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    DatePicker("Data", selection: $data)
                }

                if gasto != nil {
                    Section {
                        Button("Excluir gasto", role: .destructive) { confirmarExclusao = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo)
            .navigationTitle(gasto == nil ? "Novo gasto" : "Editar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { salvar() }.bold().disabled((valor ?? 0) <= 0)
                }
            }
            .confirmationDialog("Excluir este gasto?", isPresented: $confirmarExclusao, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let gasto { ctx.delete(gasto) }
                    try? ctx.save()
                    dismiss()
                }
            }
        }
    }

    private func salvar() {
        guard let v = valor, v > 0 else { return }
        let desc = descricao.trimmingCharacters(in: .whitespaces)
        if let gasto {
            gasto.valor = v
            gasto.descricao = desc
            gasto.categoria = categoria
            gasto.pagamento = pagamento
            gasto.data = data
        } else {
            ctx.insert(Gasto(valor: v, descricao: desc, categoria: categoria, pagamento: pagamento, data: data))
        }
        try? ctx.save()
        dismiss()
    }
}
