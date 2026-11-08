import SwiftUI
import UIKit

/// UITextView-backed rich text editor (RTL, white "paper", attribute editing).
/// External content replacements are pushed only when `revision` changes, so typing never
/// round-trips through SwiftUI state.
struct RichTextEditor: UIViewRepresentable {
    let controller: RichTextController
    let content: NSAttributedString
    let revision: Int
    let typingAttributes: [NSAttributedString.Key: Any]
    let tint: UIColor
    var spellCheck = true

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.overrideUserInterfaceStyle = .light
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.tintColor = tint
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 48, right: 16)
        textView.semanticContentAttribute = .forceRightToLeft
        textView.allowsEditingTextAttributes = true
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = false
        textView.spellCheckingType = spellCheck ? .yes : .no
        textView.autocorrectionType = spellCheck ? .default : .no
        textView.attributedText = content
        textView.typingAttributes = typingAttributes
        context.coordinator.appliedRevision = revision
        controller.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        controller.attach(textView)
        textView.tintColor = tint
        let spelling: UITextSpellCheckingType = spellCheck ? .yes : .no
        if textView.spellCheckingType != spelling {
            textView.spellCheckingType = spelling
            textView.autocorrectionType = spellCheck ? .default : .no
            if textView.isFirstResponder { textView.reloadInputViews() }
        }
        guard context.coordinator.appliedRevision != revision else { return }
        context.coordinator.appliedRevision = revision

        let selection = textView.selectedRange
        textView.attributedText = content
        let location = min(selection.location, content.length)
        textView.selectedRange = NSRange(location: location, length: min(selection.length, content.length - location))
        if content.length == 0 {
            textView.typingAttributes = typingAttributes
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: RichTextController
        var appliedRevision = -1

        init(controller: RichTextController) {
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            controller.textDidChange(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            controller.selectionDidChange(textView)
        }
    }
}
