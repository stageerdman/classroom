import AppKit
import MarkdownEngine

/// Renders an inline `@timeref(at: SECONDS){[MM:SS]}` as a clickable timestamp
/// pill, mid-sentence. This is what a bare `[MM:SS]` typed in Notes is
/// auto-converted to (see `MarkdownNotesView.handleTextMutation` and
/// `TimenoteFormat.inlineTimeRef`). Reuses `TimenoteDirective`'s click target,
/// so clicking it seeks playback exactly like a blockquote timenote.
struct TimeRefDirective: MarkdownDirective {
    var id: String { "timeref" }

    var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: "timeref",
            form: .container,
            parameters: [
                DirectiveParameter(label: "at", kind: .number, isRequired: true)
            ],
            parsesBody: false
        )
    }

    func style(arguments: DirectiveArguments, context: DirectiveContext) -> DirectiveStyle {
        guard let seconds = arguments.number("at") else {
            return DirectiveStyle(attributes: [.foregroundColor: context.theme.disabledText])
        }

        return DirectiveStyle(attributes: [
            .link: "\(TimenoteDirective.clickTargetPrefix)\(seconds)",
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.15)
        ])
    }

    func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        bodyHTML
    }
}
