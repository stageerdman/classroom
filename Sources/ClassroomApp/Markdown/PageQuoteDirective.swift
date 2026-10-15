import AppKit
import ClassroomCore
import MarkdownEngine

/// Renders `> @pagequote(ref: "<base64>"){“preview”}` (see `PageQuoteFormat`
/// in ClassroomCore) as a clickable quote chip in Notes. Clicking it links
/// back to where the quoted passage appears in the lesson's Page.
///
/// Like `TimenoteDirective`, the clickable value must be a `String` (routed
/// through the engine's `onLinkClick`), and the displayed text is the
/// directive's *body* (the preview), which stays visible at rest.
struct PageQuoteDirective: MarkdownDirective {
    var id: String { "pagequote" }

    var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: "pagequote",
            form: .container,
            parameters: [
                DirectiveParameter(label: "ref", kind: .string, isRequired: true)
            ],
            parsesBody: false
        )
    }

    func style(arguments: DirectiveArguments, context: DirectiveContext) -> DirectiveStyle {
        guard let ref = arguments.string("ref") else {
            return DirectiveStyle(attributes: [.foregroundColor: context.theme.disabledText])
        }

        return DirectiveStyle(attributes: [
            .link: "\(PageQuoteFormat.clickTargetPrefix)\(ref)",
            .foregroundColor: NSColor.controlAccentColor,
            .obliqueness: 0.1
        ])
    }

    func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        bodyHTML
    }
}
