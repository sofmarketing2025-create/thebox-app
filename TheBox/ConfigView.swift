import SwiftUI
import SwiftData

struct ConfigView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("avisosAtivos") private var avisosAtivos = true
    @AppStorage("diasAntes") private var diasAntes = 2
    @AppStorage("horaAviso") private var horaAviso = 9
    @State private var apagarGastos = false
    @State private var apagarContas = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Avisar contas a vencer", isOn: $avisosAtivos).tint(.green)
                    if avisosAtivos {
                        Stepper(value: $diasAntes, in: 0...10) {
                            Text(diasAntes == 0 ? "Só no dia do vencimento" :
                                 (diasAntes == 1 ? "1 dia antes" : "\(diasAntes) dias antes"))
                        }
                        Picker("Horário do aviso", selection: $horaAviso) {
                            ForEach(6...22, id: \.self) { h in
                                Text(String(format: "%02d:00", h)).tag(h)
                            }
                        }
                    }
                } header: {
                    Text("Notificações")
                } footer: {
                    Text("Você também recebe um aviso no dia do vencimento. Contas marcadas como pagas não geram aviso.")
                }

                Section {
                    NavigationLink("Como configurar") { GuiaAutomacao() }
                } header: {
                    Text("Automação da maquininha")
                }

                Section {
                    Button("Apagar todos os gastos", role: .destructive) { apagarGastos = true }
                    Button("Apagar todas as contas", role: .destructive) { apagarContas = true }
                } header: {
                    Text("Dados")
                }

                Section {
                    LabeledContent("Versão", value: "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo)
            .navigationTitle("Config")
            .onChange(of: avisosAtivos) { _, _ in Notificacoes.reagendar(ctx) }
            .onChange(of: diasAntes) { _, _ in Notificacoes.reagendar(ctx) }
            .onChange(of: horaAviso) { _, _ in Notificacoes.reagendar(ctx) }
            .confirmationDialog("Apagar todos os gastos? Isso não pode ser desfeito.",
                                isPresented: $apagarGastos, titleVisibility: .visible) {
                Button("Apagar gastos", role: .destructive) {
                    try? ctx.delete(model: Gasto.self)
                    try? ctx.save()
                }
            }
            .confirmationDialog("Apagar todas as contas? Isso não pode ser desfeito.",
                                isPresented: $apagarContas, titleVisibility: .visible) {
                Button("Apagar contas", role: .destructive) {
                    try? ctx.delete(model: Conta.self)
                    try? ctx.save()
                    Notificacoes.reagendar(ctx)
                }
            }
        }
    }
}

struct GuiaAutomacao: View {
    private let passos: [String] = [
        "Abra este app pelo menos uma vez, para o iPhone conhecer a ação \"Registrar gasto\".",
        "Abra o app Atalhos e vá em Automação.",
        "Toque em + e escolha \"Transação\".",
        "Selecione seus cartões da Carteira, marque \"Executar Imediatamente\" e avance.",
        "Adicione a ação \"Registrar gasto\" do The Box App.",
        "Em Valor, escolha a variável da transação que traz o valor da compra.",
        "Em Descrição, escolha \"Perguntar Sempre\" (ou a variável do estabelecimento, se preferir que venha preenchida).",
        "Em Categoria e Tipo de pagamento, escolha \"Perguntar Sempre\".",
        "Salve. Na próxima compra por aproximação com o iPhone, o formulário aparece sozinho."
    ]

    var body: some View {
        List {
            ForEach(Array(passos.enumerated()), id: \.offset) { i, passo in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(i + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Color.white, in: Circle())
                    Text(passo)
                }
                .padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fundo)
        .navigationTitle("Automação")
        .navigationBarTitleDisplayMode(.inline)
    }
}
