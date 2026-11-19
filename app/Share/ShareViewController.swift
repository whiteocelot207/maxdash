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
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    provider.loadItem(forTypeIdentifier: "public.url", options: nil) { data, _ in
                        let s = (data as? URL)?.absoluteString
                        DispatchQueue.main.async { completion(s) }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                        let s = data as? String
                        DispatchQueue.main.async { completion(s) }
                    }
                    return
                }
            }
        }
        DispatchQueue.main.async { completion(nil) }
    }
}