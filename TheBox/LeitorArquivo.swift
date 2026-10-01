import Foundation
import UIKit
import PDFKit
import Vision
import AppIntents
import UniformTypeIdentifiers

/// Tira o texto de um comprovante (PDF ou imagem) pra depois o LeitorTexto achar valor e nome
enum LeitorArquivo {
    /// Imagem do comprovante pra guardar junto do gasto (1ª página, se for PDF)
    static func foto(de arquivo: IntentFile) -> Data? {
        let data = arquivo.data
        if let img = UIImage(data: data) { return comprimirFoto(img) }
        if let doc = PDFDocument(data: data), let pagina = doc.page(at: 0) {
            let caixa = pagina.bounds(for: .mediaBox)
            let escala = 1400 / max(caixa.width, caixa.height, 1)
            let img = pagina.thumbnail(of: CGSize(width: caixa.width * escala, height: caixa.height * escala), for: .mediaBox)
            return comprimirFoto(img)
        }
        return nil
    }

    static func texto(de arquivo: IntentFile) async -> String {
        let data = arquivo.data
        let ehPDF = arquivo.type?.conforms(to: .pdf) == true || data.starts(with: [0x25, 0x50, 0x44, 0x46]) // "%PDF"
        if ehPDF, let doc = PDFDocument(data: data) {
            if let s = doc.string, s.contains("R$") { return s }
            // PDF que é só uma imagem: renderiza a 1ª página e lê
            if let pagina = doc.page(at: 0) {
                let caixa = pagina.bounds(for: .mediaBox)
                let escala = 1600 / max(caixa.width, 1)
                let img = pagina.thumbnail(of: CGSize(width: caixa.width * escala, height: caixa.height * escala), for: .mediaBox)
                if let cg = img.cgImage { return await ocr(cg) }
            }
            return doc.string ?? ""
        }
        guard let img = UIImage(data: data), let cg = img.cgImage else { return "" }
        return await ocr(cg)
    }

    /// Lê o texto de uma imagem (o mesmo "Texto ao Vivo" do iPhone)
    static func ocr(_ cg: CGImage) async -> String {
        await withCheckedContinuation { cont in
            var respondeu = false
            let pedido = VNRecognizeTextRequest { req, _ in
                guard !respondeu else { return }
                respondeu = true
                let linhas = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: linhas.joined(separator: "\n"))
            }
            pedido.recognitionLevel = .accurate
            pedido.recognitionLanguages = ["pt-BR"]
            pedido.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: cg).perform([pedido])
            } catch {
                if !respondeu {
                    respondeu = true
                    cont.resume(returning: "")
                }
            }
        }
    }
}
