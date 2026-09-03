import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusImage = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var importTask: Task<Void, Never>?
    private var enqueuedURL: URL?
    private var isReadyToComplete = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importTask = Task { await importSharedContent() }
    }

    private func configureView() {
        view.backgroundColor = .black
        preferredContentSize = CGSize(width: 360, height: 280)

        statusImage.image = UIImage(systemName: "ellipsis")
        statusImage.tintColor = .black
        statusImage.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 28,
            weight: .semibold
        )
        statusImage.contentMode = .center
        statusImage.backgroundColor = .white
        statusImage.layer.cornerRadius = 35
        statusImage.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Remembering…"
        titleLabel.textColor = .white
        titleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 25, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.text = "Adding this to Speak It"
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        detailLabel.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .regular))
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setTitle("Cancel", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        closeButton.titleLabel?.adjustsFontForContentSizeCategory = true
        closeButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusImage)
        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            statusImage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 34),
            statusImage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusImage.widthAnchor.constraint(equalToConstant: 70),
            statusImage.heightAnchor.constraint(equalToConstant: 70),
            titleLabel.topAnchor.constraint(equalTo: statusImage.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            closeButton.topAnchor.constraint(greaterThanOrEqualTo: detailLabel.bottomAnchor, constant: 18),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @MainActor
    private func importSharedContent() async {
        do {
            let content = await sharedContent()
            try Task.checkCancellation()
            let captureText = content.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !captureText.isEmpty || content.url != nil else {
                throw ShareImportError.unsupportedContent
            }

            let safeText = CaptureTextLimit.clamp(captureText)
            let destination = try SharedCaptureInbox.enqueue(
                SharedCapturePayload(text: safeText, sourceURL: content.url)
            )
            enqueuedURL = destination
            try Task.checkCancellation()
            isReadyToComplete = true

            statusImage.image = UIImage(systemName: "checkmark")
            titleLabel.text = "Ready in Speak It"
            detailLabel.text = "It will be organized when Speak It opens"
            closeButton.setTitle("Done", for: .normal)

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try await Task.sleep(for: .milliseconds(900))
            try Task.checkCancellation()
            extensionContext?.completeRequest(returningItems: nil)
        } catch is CancellationError {
            if !isReadyToComplete, let enqueuedURL {
                SharedCaptureInbox.remove(at: enqueuedURL)
            }
            return
        } catch {
            statusImage.image = UIImage(systemName: "exclamationmark")
            titleLabel.text = "Couldn’t remember this"
            detailLabel.text = error.localizedDescription
            closeButton.setTitle("Close", for: .normal)
        }
    }

    private func sharedContent() async -> (text: String, url: URL?) {
        let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var text = extensionItems
            .compactMap { $0.attributedContentText?.string }
            .first ?? ""
        var sharedURL: URL?

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if text.isEmpty,
                   provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = await provider.loadedText() {
                    text = value
                }

                if sharedURL == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = await provider.loadedURL() {
                    sharedURL = value
                }
            }
        }

        return (text, sharedURL)
    }

    @objc private func cancel() {
        importTask?.cancel()
        if isReadyToComplete {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            if let enqueuedURL { SharedCaptureInbox.remove(at: enqueuedURL) }
            extensionContext?.cancelRequest(withError: ShareImportError.cancelled)
        }
    }
}

private extension NSItemProvider {
    @MainActor
    func loadedText() async -> String? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text = (item as? String) ?? (item as? NSAttributedString)?.string
                continuation.resume(returning: text)
            }
        }
    }

    @MainActor
    func loadedURL() async -> URL? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
                continuation.resume(returning: url)
            }
        }
    }
}

private enum ShareImportError: LocalizedError {
    case unsupportedContent
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            "Share selected text or a link to save it in Speak It."
        case .cancelled:
            "Share cancelled."
        }
    }
}
