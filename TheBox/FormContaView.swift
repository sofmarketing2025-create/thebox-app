import SwiftUI
import SwiftData

struct FormContaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    let conta: Conta?

    @State private var nome: String
    @State private var valorTexto: String
    @State private var diaTexto: String
    @State private var inicio: Int
    @State private var venceMesSeguinte: Bool
    @State private var categoria: String
    @State private var repetir: Bool
    @State private var parcelaTexto: String
    @State private var totalTexto: String
    @State private var confirmarExclusao = false

    init(conta: Conta?, mesInicial: Int) {
        self.conta = conta
        _nome = State(initialValue: conta?.nome ?? "")
        _valorTexto = State(initialValue: conta?.valor.textoCampo ?? "")
        _diaTexto = State(initialValue: conta.map { String($0.dia) } ?? "")
        _inicio = State(initialValue: conta?.inicio ?? mesInicial)
        _venceMesSeguinte = State(initialValue: conta?.venceMesSeguinte ?? false)
        _categoria = State(initialValue: conta?.categoria ?? "")
        _repetir = State(initialValue: conta?.repetir ?? true)
        let p = conta?.parcelaAtual ?? 0
        let t = conta?.totalParcelas ?? 0
        _parcelaTexto = State(initialValue: p > 0 ? String(p) : "")
        _totalTexto = State(initialValue: t > 0 ? String(t) : "")
    }

    private var valor: Double? { lerValor(valorTexto) }
    private var dia: Int? { Int(diaTexto).flatMap { (1...31).contains($0) ? $0 : nil } }
    private var total: Int { Int(totalTexto) ?? 0 }
    private var parcela: Int { max(Int(parcelaTexto) ?? 1, 1) }
    private var valido: Bool {
        !nome.trimmingCharacters(in: .whitespaces).isEmpty
            && (valor ?? 0) > 0
            && dia != nil
            && (total == 0 || parcela <= total)
    }
    private var cats: [Categoria] { categorias.filter { $0.tipo == .gasto } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nome da conta", text: $nome).campo()
                    HStack(spacing: 10) {
                        Text(Moeda.atual.simbolo).fontWeight(.semibold).foregroundStyle(.secondary)
                        TextField("Valor (ex: 150,00)", text: $valorTexto).keyboardType(.decimalPad)
                    }
                    .campo()
                    HStack(spacing: 12) {
                        TextField("Dia de vencimento (ex: 10)", text: $diaTexto)
                            .keyboardType(.numberPad)
                            .campo()
                        SeletorMes(mes: $inicio)
                    }

                    Divider().overlay(Color.borda).padding(.vertical, 4)
                    LinhaToggle(titulo: "Vence no mês seguinte",
                                sub: "Ligue se o dia digitado for do próximo mês",
                                ligado: $venceMesSeguinte)

                    Text("Categoria").font(.subheadline.weight(.medium)).foregroundStyle(.secondary).padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(cats) { c in
                            ChipOpcao(texto: c.nome, icone: c.icone, selecionado: categoria == c.nome) {
                                categoria = c.nome
                            }
                        }
                    }

                    Divider().overlay(Color.borda).padding(.vertical, 4)
                    LinhaToggle(titulo: "Repetir nos próximos meses",
                                sub: "Renova automaticamente todo mês",
                                ligado: $repetir)

                    HStack(spacing: 12) {
                        TextField("Parcela atual", text: $parcelaTexto)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .campo()
                        TextField("Nº de parcelas", text: $totalTexto)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .campo()
                    }
                    Text("Parcelado? Preencha a parcela deste mês e o total (ex.: 3 de 12). Senão, deixe em branco.")
                        .font(.footnote).foregroundStyle(.secondary)

                    Button("Salvar") { salvar() }
                        .buttonStyle(EstiloPrincipal(ativo: valido))
                        .disabled(!valido)
                        .padding(.top, 10)

                    if conta != nil {
                        Button("Excluir conta", role: .destructive) { confirmarExclusao = true }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.cartao)
            .navigationTitle(conta == nil ? "Nova conta" : "Editar conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cartao, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(.secondary)
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
        .folha()
        .onAppear {
            if categoria.isEmpty { categoria = cats.first?.nome ?? "Outros" }
        }
    }

    private func salvar() {
        guard valido, let v = valor, let d = dia else { return }
        let nomeLimpo = nome.trimmingCharacters(in: .whitespaces)
        let p = total > 0 ? parcela : 0
        if let conta {
            conta.nome = nomeLimpo
            conta.valor = v
            conta.dia = d
            conta.venceMesSeguinte = venceMesSeguinte
            conta.categoria = categoria
            conta.repetir = repetir
            conta.parcelaAtual = p
            conta.totalParcelas = total
            conta.inicio = inicio
        } else {
            ctx.insert(Conta(nome: nomeLimpo, valor: v, dia: d, venceMesSeguinte: venceMesSeguinte,
                             categoria: categoria, repetir: repetir, parcelaAtual: p,
                             totalParcelas: total, inicio: inicio))
        }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        dismiss()
    }
}
