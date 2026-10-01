import SwiftUI
import PhotosUI
import UIKit

/// Diminui a foto pra não pesar no iPhone (lado maior 1400px, JPEG)
func comprimirFoto(_ img: UIImage) -> Data? {
    let maior = max(img.size.width, img.size.height)
    let escala = maior > 1400 ? 1400 / maior : 1
    let tamanho = CGSize(width: img.size.width * escala, height: img.size.height * escala)
    let r = UIGraphicsImageRenderer(size: tamanho)
    let pequena = r.image { _ in img.draw(in: CGRect(origin: .zero, size: tamanho)) }
    return pequena.jpegData(compressionQuality: 0.6)
}

/// Câmera do iPhone
struct CameraView: UIViewControllerRepresentable {
    var tirou: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordenador { Coordenador(self) }

    final class Coordenador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let pai: CameraView
        init(_ pai: CameraView) { self.pai = pai }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { pai.tirou(img) }
            pai.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            pai.dismiss()
        }
    }
}

/// Foto em tela cheia
struct FotoTelaCheia: View {
    let dados: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let img = UIImage(data: dados) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            BotaoFechar { dismiss() }
                .padding(20)
        }
    }
}

/// Bloco "Comprovante" na tela de registrar: tirar foto, escolher da galeria, ver e remover
struct CampoFoto: View {
    @Binding var foto: Data?
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    @State private var ampliar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comprovante (opcional)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if let foto, let img = UIImage(data: foto) {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture { ampliar = true }
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Ver") { ampliar = true }
                        Button("Remover", role: .destructive) { self.foto = nil }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Button { camera = true } label: {
                        Label("Tirar foto", systemImage: "camera")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color.cartao2.opacity(0.6), in: Capsule())
                    }
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Galeria", systemImage: "photo")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color.cartao2.opacity(0.6), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraView { img in foto = comprimirFoto(img) }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $ampliar) {
            if let foto { FotoTelaCheia(dados: foto) }
        }
        .onChange(of: item) { _, novo in
            guard let novo else { return }
            Task {
                if let d = try? await novo.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    foto = comprimirFoto(img)
                }
                item = nil
            }
        }
    }
}
