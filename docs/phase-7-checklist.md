# Phase 7 Checklist

## Scope

- Stored custom order for modules, categories, direct lessons, and category lessons
- Merge saved order with discovered content
- Ignore missing ordering references
- Append newly discovered items after saved items using natural sort
- Sidebar reorder actions and drag move handlers
- Reset order for selected scopes

## Automated Verification

- `swift test`
- `swift run ClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run Classroom` or open `Classroom.app`.
- Open a classroom.
- Reorder modules from the sidebar context menu or drag move support.
- Reorder direct lessons and category lessons.
- Add new files in Finder and refresh.
- Verify new files appear after manually ordered items.
- Reset one scope without affecting other scopes.
