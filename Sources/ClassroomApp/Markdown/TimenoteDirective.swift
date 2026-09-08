import AppKit
import MarkdownEngine

/// Renders `> @timenote(at: SECONDS){HH:MM:SS.mmm} text` (see
/// `TimenoteFormat` in ClassroomCore) as a clickable, always-visible
/// timestamp pill.
///
/// The seconds value lives in the directive's *arguments* — muted/hidden by
/// the engine except while the caret is inside — and the human-readable
/// timestamp is the directive's *body*, the one part of a directive that
/// stays visible regardless of caret position. That split is what makes the
/// pill readable at rest instead of disappearing like ordinary markdown
/// syntax.
///
/// `.link`'s value here MUST be a `String`, not a `URL`: MarkdownEngine
/// routes a clicked `.link` through `WikiLinkService.resolveIdentifier`,
/// which only recognizes `String`-valued links (a `URL` value is treated as
/// an ordinary web link and handed to `NSWorkspace` instead of firing
/// `onLinkClick`) — confirmed by reading
/// `NativeTextViewCoordinator+TextDelegate.swift` directly, since this isn't
/// documented anywhere in the package.
struct TimenoteDirective: MarkdownDirective {
    /// `onLinkClick` target prefix — `MarkdownNotesView` strips this back off
    /// to recover the seconds value. Keep the two in sync.
    static let clickTargetPrefix = "classroom-timenote:"

    var id: String { "timenote" }

    var syntax: DirectiveSyntax {
        DirectiveSyntax(
            name: "timenote",
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
            .link: "\(Self.clickTargetPrefix)\(seconds)",
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.15)
        ])
    }

    func html(arguments: DirectiveArguments, bodyHTML: String) -> String {
        bodyHTML
    }
}
