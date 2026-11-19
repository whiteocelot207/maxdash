import UIKit

/// Share extension maxdash: menerima teks/tautan dari Google Maps, mengurai tujuan,
/// lalu menyerahkannya ke aplikasi utama lewat pasteboard (tanpa perlu app group,
/// agar tetap bisa dipasang dengan Apple ID gratis).
final class ShareViewController: UIViewController {

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        label.text = "Mengirim ke maxdash…"

        extractText { [weak self] text in
            guard let self = self else { return }
            guard let text = text, !text.isEmpty else {
                label.text = "Tidak ada teks untuk dibagikan."
                self.finish(delay: 1.0)
                return
            }
            UIPasteboard.general.string = text
            label.text = Self.describe(ShareLink.parse(text))
            self.finish(delay: 1.2)
        }
    }

    private static func describe(_ result: ShareResult) -> String {
        switch result {
        case .coords(_, _, let name): return "Tujuan: \(name ?? "titik tujuan")"
        case .query(let q): return "Cari: \(q)"
        case .directions(let dest, let stops):
            let name = dest.name ?? dest.q ?? "tujuan"
            return stops.isEmpty ? "Rute ke \(name)" : "Rute via \(stops.count) perhentian → \(name)"
        case .redirect: return "Tautan diterima, membuka…"
        case .none: return "Tautan tidak dikenali."
        }
    }

    private func finish(delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func extractText(_ completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil); return
        }
        for item in items {
            // 1) Attachment URL / teks biasa.
            for provider in item.attachments ?? [] {
                for type in ["public.url", "public.plain-text", "public.utf8-plain-text", "public.text"] {
                    if provider.hasItemConformingToTypeIdentifier(type) {
                        provider.loadItem(forTypeIdentifier: type, options: nil) { data, _ in
                            let s: String?
                            if let url = data as? URL { s = url.absoluteString }
                            else if let str = data as? String { s = str }
                            else if let str = data as? NSString { s = str as String }
                            else { s = nil }
                            DispatchQueue.main.async { completion(s) }
                        }
                        return
                    }
                }
            }
            // 2) Fallback: teks berformat (biasanya berisi nama + tautan).
            if let s = item.attributedContentText?.string, !s.isEmpty {
                completion(s)
                return
            }
        }
        DispatchQueue.main.async { completion(nil) }
    }
}