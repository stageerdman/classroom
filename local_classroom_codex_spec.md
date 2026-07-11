# Local Classroom for macOS — Product and Engineering Specification

## 1. Product Summary

Build a local macOS application that turns any selected folder into a video classroom.

The application does not import, duplicate, or upload videos. The folder structure remains the source of truth. The app reads the existing folders and video files, presents them in a polished classroom interface, and stores lightweight metadata such as lesson order, completion state, and playback position.

The application should be built incrementally. Every phase must include automated tests and a manual verification checklist before development continues to the next phase.

---

## 2. Core Product Principles

1. **Local-first**
   - All content stays on the user's Mac.
   - No server, account, login, or cloud dependency.
   - No media upload or duplication.

2. **Folder-driven**
   - The selected folder defines the classroom.
   - Folder names define classroom, module, and category names.
   - Video filenames define lesson names.

3. **Non-destructive**
   - The app must never silently delete or overwrite user files.
   - Renames and moves must be validated before execution.
   - Metadata may be removed when its corresponding content no longer exists, but only according to the cleanup rules defined below.

4. **Test-first and incremental**
   - Do not build the whole application before testing.
   - Each phase must compile, run, and pass its own tests.
   - Do not begin the next phase until the current phase is verified.

5. **Simple identity model**
   - Lessons are tracked by relative file path and filename.
   - No UUID, inode, file hash, or persistent file identifier is required in version 1.
   - Renaming or moving a lesson outside the app may cause it to be treated as a new lesson.

---

## 3. Supported Classroom Structure

The app supports exactly four logical depths.

```text
Classroom Root/                     Depth 1: Classroom
├── Module A/                       Depth 2: Module
│   ├── Lesson 1.mp4                Depth 3: Direct lesson
│   ├── Lesson 1.md                 Matching lesson notes
│   ├── Category A/                 Depth 3: Category
│   │   ├── Lesson 2.mp4            Depth 4: Lesson
│   │   ├── Lesson 2.md             Matching lesson notes
│   │   └── Lesson 3.mov
│   └── Lesson 4.m4v
└── Module B/
    └── ...
```

### Structural Rules

- The selected root folder is the classroom.
- The classroom name is the root folder name.
- Immediate child folders of the root are modules.
- A module may contain:
  - video files directly, or
  - category folders.
- A category may contain video files.
- Folders deeper than category level are unsupported in version 1.
- Files other than supported videos and matching note files are ignored.
- Hidden files and hidden folders are ignored, except the app's own metadata folder.

### Supported Video Formats for Version 1

- `.mp4`
- `.mov`
- `.m4v`

Extensions must be matched case-insensitively.

### Notes File Convention

For a video:

```text
Lesson Name.mp4
```

the associated notes file is:

```text
Lesson Name.md
```

A `.txt` file may be read as a fallback in a later version, but version 1 should use Markdown only.

---

## 4. Metadata Storage Decision

### Recommended Approach

Store classroom-specific metadata inside the classroom root:

```text
Classroom Root/
└── .local-classroom/
    └── classroom.json
```

This is preferable to storing all classroom state only in the application because:

- The classroom remains portable.
- Moving the whole classroom folder preserves lesson order and progress.
- The app does not depend on the original absolute path.
- Backups include both content and classroom state.
- Multiple classroom folders can each carry their own configuration.

The app may separately store a global list of recently opened classroom paths in the normal macOS application support directory.

### Metadata Must Not Be Stored Beside Every Video

Do not create one metadata file per lesson. Use one classroom metadata file.

### Example Metadata

```json
{
  "schemaVersion": 1,
  "moduleOrder": [
    "01 Foundations",
    "02 Prospecting"
  ],
  "categoryOrder": {
    "01 Foundations": [
      "Mindset",
      "Planning"
    ]
  },
  "lessonOrder": {
    "01 Foundations": [
      "Welcome.mp4",
      "Goal Setting.mp4"
    ],
    "01 Foundations/Mindset": [
      "Fear of Rejection.mp4",
      "Identity.mp4"
    ]
  },
  "lessonState": {
    "01 Foundations/Welcome.mp4": {
      "playbackPositionSeconds": 315.4,
      "completed": false,
      "lastOpenedAt": "2026-07-11T10:30:00Z"
    }
  }
}
```

### Tracking Key

Use the lesson's relative path from the classroom root:

```text
01 Foundations/Mindset/Fear of Rejection.mp4
```

The relative path is the lesson key.

### External Rename Behavior

If a user renames or moves a video in Finder:

- the old relative path no longer exists;
- the app treats the renamed or moved file as a new lesson;
- the previous metadata becomes orphaned;
- orphan cleanup rules apply.

### In-App Rename Behavior

When the app renames or moves a lesson:

- rename or move the physical video file;
- rename or move the matching Markdown file;
- update the lesson key in metadata;
- preserve playback state, completion state, and ordering.

---

## 5. Orphaned Metadata Rules

Do not immediately erase metadata during every scan.

Use this behavior:

1. When a lesson is missing, mark its metadata entry as orphaned.
2. Store `missingSince`.
3. Hide the missing lesson from the classroom UI.
4. Keep the metadata for 30 days.
5. If the exact same relative path reappears within 30 days, restore its previous state.
6. After 30 days, remove the orphaned metadata during cleanup.

Example:

```json
{
  "lessonState": {
    "01 Foundations/Welcome.mp4": {
      "playbackPositionSeconds": 315.4,
      "completed": false,
      "missingSince": "2026-07-11T10:30:00Z"
    }
  }
}
```

Also provide a manual command:

- **Clean Missing Lesson Data**

This command must show how many orphaned entries will be removed and require confirmation.

---

## 6. Functional Requirements

## 6.1 Classroom Management

The user can:

- Open a folder as a classroom.
- Reopen recent classrooms.
- Remove a classroom from the recent list without deleting it.
- Reveal the classroom root in Finder.
- Refresh or rescan the classroom.
- View structural warnings.

The app must remember access to selected folders across launches using the appropriate macOS persistent folder-access mechanism.

## 6.2 Classroom Navigation

The main interface contains:

- Classroom title
- Module navigation
- Category navigation
- Lesson list
- Main video viewer
- Notes editor
- Progress indication

Suggested layout:

```text
┌─────────────────────────────────────────────────────────┐
│ Classroom Name                                          │
├───────────────┬─────────────────────────────────────────┤
│ Modules       │ Video                                   │
│               │                                         │
│ Module 1      │                                         │
│   Category A  ├─────────────────────────────────────────┤
│   Lesson 1    │ Lesson title                            │
│   Lesson 2    │ Notes editor                            │
│               │                                         │
└───────────────┴─────────────────────────────────────────┘
```

A direct lesson under a module should appear at the same navigation level as category entries.

## 6.3 Video Playback

The user can:

- Play and pause.
- Seek.
- Change volume.
- Enter full screen.
- Change playback speed.
- Jump backward 10 seconds.
- Jump forward 10 seconds.
- Use standard keyboard shortcuts.
- Resume from the last saved position.
- Mark the lesson complete.
- Mark the lesson incomplete.
- Move to the next or previous lesson.

Suggested keyboard shortcuts:

- Space: play or pause
- Left Arrow: back 10 seconds
- Right Arrow: forward 10 seconds
- Command + Left Arrow: previous lesson
- Command + Right Arrow: next lesson
- Command + S: save notes
- Command + R: rescan classroom

Playback position should be saved:

- every 10 seconds while playing;
- when paused;
- when switching lessons;
- when closing the classroom;
- when quitting the app.

A lesson is not automatically completed merely because it was opened.

Optional version 1 rule:

- Automatically mark completed after 90% of the video has been watched.
- The user can override completion manually.

## 6.4 Notes

For every lesson, display a Markdown editor under or beside the video.

Behavior:

- If the matching `.md` file exists, load it.
- If it does not exist, show an empty editor.
- Create the `.md` file only after the user enters content or explicitly saves.
- Autosave after a short debounce, such as 800 milliseconds.
- Save when changing lessons.
- Save when closing the classroom.
- Save when quitting.

The notes file must use UTF-8 encoding.

The first version only requires plain Markdown text editing. Rendered Markdown preview may be added later.

## 6.5 Ordering

Default order:

1. Use saved custom order from metadata.
2. Items not present in metadata appear after saved items.
3. New unsorted items are ordered using localized natural filename sorting.

Natural sorting should place:

```text
Lesson 2
Lesson 10
```

in that order, rather than placing `Lesson 10` before `Lesson 2`.

The user can reorder:

- modules;
- categories within modules;
- direct lessons within modules;
- lessons within categories.

Use drag and drop.

Ordering changes affect metadata only. They do not rename files or folders.

Provide an optional command:

- **Reset to Filename Order**

Resetting must apply only to the selected scope and require confirmation if it discards custom ordering.

## 6.6 Rename

The user can rename:

- classroom root folder;
- modules;
- categories;
- lessons.

For lesson rename:

```text
Old Name.mp4
Old Name.md
```

must become:

```text
New Name.mp4
New Name.md
```

If the note file does not exist, rename only the video.

Rename validation:

- No empty names.
- Do not permit `/` or `:`.
- Do not overwrite an existing file.
- Do not create duplicate basenames in the same folder.
- Preserve the original video extension.
- Trim leading and trailing whitespace.
- Show an error instead of partially completing an unsafe rename.

If the video rename succeeds but note rename fails, attempt rollback. Report clearly if rollback also fails.

## 6.7 Move Lesson

The user can move a lesson:

- between categories in the same module;
- from a category directly into its module;
- from one module to another;
- into a category in another module.

Move both:

- video file;
- matching Markdown file.

Update metadata and preserve lesson state.

Do not overwrite destination files.

## 6.8 Delete

For version 1, do not permanently delete files from inside the app.

Provide:

- **Move to Trash**

This action must:

- move the video to macOS Trash;
- move the matching Markdown note to Trash;
- require confirmation;
- retain orphaned metadata for 30 days.

Do not implement irreversible deletion.

## 6.9 File-System Refresh

The app must detect changes made through Finder.

The simplest acceptable version 1 approach:

- rescan when the app becomes active;
- rescan when the user presses Refresh;
- optionally watch the classroom folder for changes and debounce rescans.

After rescanning:

- add new modules, categories, and lessons;
- remove missing content from the visible UI;
- preserve metadata for missing lessons according to orphan rules;
- merge new items into saved order;
- reload notes if they changed externally.

If the currently playing video disappears:

- stop playback;
- show a non-destructive error message;
- return to the lesson list.

## 6.10 Search

Provide classroom-wide search by:

- lesson filename;
- module name;
- category name.

Version 1 does not need to search inside notes.

Search results should display the lesson's module and category context.

## 6.11 Progress

Show:

- completed lessons;
- total lessons;
- completion percentage by module;
- completion percentage for the classroom;
- current lesson playback progress.

A category does not need its own manually stored completion state. Derive category and module progress from lesson state.

---

## 7. Error and Warning States

The app must handle these conditions without crashing:

- Selected folder does not exist.
- Folder access permission expired.
- Classroom is read-only.
- Video file is unreadable.
- Video codec is unsupported.
- Notes file cannot be decoded.
- Notes file cannot be saved.
- Duplicate video basenames exist in the same directory.
- Metadata JSON is missing.
- Metadata JSON is malformed.
- Metadata schema version is unsupported.
- File disappears during playback.
- Rename destination already exists.
- Move destination already exists.
- Classroom contains folders deeper than supported.
- Classroom contains symbolic links.

For malformed metadata:

1. Keep the classroom usable.
2. Back up the malformed file.
3. Create fresh default metadata.
4. Show a warning describing what happened.

Do not silently discard malformed metadata without backup.

---

## 8. Non-Goals for Version 1

Do not build these features initially:

- User accounts
- Cloud synchronization
- Web application
- Mobile application
- Comments
- Community feed
- Quizzes
- Certificates
- AI summaries
- Speech transcription
- Video uploading
- Video conversion
- DRM
- Multi-user collaboration
- Automatic duplicate detection
- File hashes or persistent file identifiers
- Rich text editor
- Embedded attachments inside notes
- Internet video links

---

## 9. Suggested Technical Architecture

Recommended stack:

- Swift
- SwiftUI
- AVKit / AVFoundation
- FileManager
- Codable JSON metadata
- XCTest
- macOS security-scoped bookmarks for persistent folder access

Suggested logical components:

```text
App
├── ClassroomRepository
├── ClassroomScanner
├── MetadataStore
├── OrderingService
├── LessonFileService
├── NotesService
├── PlaybackService
├── ClassroomViewModel
└── Views
```

### ClassroomScanner

Responsibilities:

- scan the root folder;
- validate depth rules;
- identify modules, categories, videos, and notes;
- return a pure in-memory classroom model;
- generate warnings;
- perform no UI work;
- modify no user files.

### MetadataStore

Responsibilities:

- load metadata;
- validate schema version;
- write metadata atomically;
- create backups on corruption;
- merge metadata with scan results;
- handle orphan cleanup.

### LessonFileService

Responsibilities:

- rename lessons;
- move lessons;
- rename and move matching notes;
- move lessons to Trash;
- validate destination conflicts;
- attempt rollback on partial failure.

### NotesService

Responsibilities:

- locate matching notes;
- load UTF-8 Markdown;
- save atomically;
- debounce autosave through the view model or dedicated controller.

### PlaybackService

Responsibilities:

- load local video;
- expose playback position;
- save progress events;
- resume playback;
- detect video duration;
- calculate watched percentage.

### OrderingService

Responsibilities:

- merge saved order with discovered content;
- natural sort unsaved items;
- update order after drag and drop;
- remove invalid ordering references after the orphan retention period.

---

## 10. Data Models

Example conceptual models:

```swift
struct Classroom {
    let rootURL: URL
    let name: String
    var modules: [Module]
    var warnings: [ClassroomWarning]
}

struct Module {
    let relativePath: String
    var name: String
    var directLessons: [Lesson]
    var categories: [Category]
}

struct Category {
    let relativePath: String
    var name: String
    var lessons: [Lesson]
}

struct Lesson {
    let relativePath: String
    let videoURL: URL
    let notesURL: URL
    let title: String
    let fileExtension: String
    var state: LessonState
}

struct LessonState: Codable {
    var playbackPositionSeconds: Double
    var completed: Bool
    var lastOpenedAt: Date?
    var missingSince: Date?
}
```

The exact code may differ, but keep parsing models, metadata models, and UI state clearly separated.

---

# 11. Mandatory Incremental Development Plan

Codex must implement the application in phases.

At the end of every phase:

1. Run all automated tests.
2. Build the app.
3. Perform the manual checklist.
4. Fix all failures.
5. Summarize what was implemented.
6. Only then proceed.

Do not start several phases simultaneously.

---

## Phase 0 — Project Skeleton

Implement:

- macOS SwiftUI project;
- basic window;
- test target;
- temporary home screen;
- project folders for models, services, views, and tests.

Automated tests:

- test target executes successfully;
- one trivial smoke test passes.

Manual verification:

- app launches;
- window appears;
- no crash;
- test suite passes.

Exit criterion:

- clean build and green tests.

---

## Phase 1 — Pure Folder Parser

Implement only the folder scanner and in-memory models.

Do not implement video playback or metadata yet.

Create fixture folders inside the test target for:

- one valid classroom;
- empty classroom;
- direct lessons;
- categories;
- mixed direct lessons and categories;
- unsupported file extensions;
- folders deeper than four logical depths;
- uppercase video extensions;
- duplicate basenames.

Automated tests:

- root name becomes classroom name;
- child folders become modules;
- module videos become direct lessons;
- third-level folders become categories;
- category videos become lessons;
- unsupported files are ignored;
- hidden files are ignored;
- over-deep folders generate warnings;
- natural sorting works;
- duplicate basenames generate warnings.

Manual verification:

- add a temporary developer screen showing parsed hierarchy as text;
- select several folders;
- confirm hierarchy matches Finder.

Exit criterion:

- scanner is correct and independent from UI.

---

## Phase 2 — Classroom Picker and Sidebar

Implement:

- folder picker;
- persistent access to selected folder;
- classroom hierarchy UI;
- recent classroom list;
- refresh button.

Do not implement notes or video playback yet.

Automated tests:

- view model maps classroom model into sidebar sections;
- recent classroom storage adds, removes, and de-duplicates paths;
- inaccessible paths produce a recoverable error state.

Manual verification:

- open classroom;
- quit and reopen app;
- reopen recent classroom;
- navigate modules and categories;
- refresh after adding a video in Finder.

Exit criterion:

- navigation works reliably with real folders.

---

## Phase 3 — Metadata Foundation

Implement:

- `.local-classroom/classroom.json`;
- schema version;
- atomic save;
- default metadata creation;
- malformed metadata backup;
- lesson-state merging;
- orphan marking;
- 30-day cleanup logic.

Do not implement drag-and-drop ordering yet.

Automated tests:

- missing metadata creates defaults;
- valid metadata loads;
- malformed metadata is backed up;
- unknown lessons are added;
- missing lessons are marked orphaned;
- restored paths recover old state;
- old orphaned entries are removed after 30 days;
- metadata writes can be read back identically.

Manual verification:

- open classroom;
- inspect generated JSON;
- manually corrupt JSON;
- reopen app;
- verify backup and warning;
- verify classroom still opens.

Exit criterion:

- metadata cannot destroy classroom usability.

---

## Phase 4 — Basic Video Playback

Implement:

- local video playback;
- play and pause;
- seek;
- full screen;
- playback speed;
- previous and next lesson;
- unsupported media error.

Do not implement automatic progress saving yet.

Automated tests:

- playback service initializes with a valid local URL;
- view model selects lessons;
- next and previous lesson logic respects visible order;
- missing file produces a safe error.

Manual verification:

- play MP4, MOV, and M4V samples;
- seek;
- switch lessons;
- enter full screen;
- test unsupported or damaged video;
- remove a playing file and verify graceful recovery.

Exit criterion:

- stable playback without progress persistence.

---

## Phase 5 — Playback Progress

Implement:

- periodic progress saving;
- save on pause;
- save on lesson switch;
- resume position;
- manual completion;
- optional 90% automatic completion;
- classroom and module progress.

Automated tests:

- saved position is restored;
- progress is clamped between zero and duration;
- completion percentage is correct;
- manual completion overrides automatic state;
- state survives metadata reload.

Manual verification:

- play a lesson;
- quit midway;
- reopen;
- confirm resume;
- complete and uncomplete lesson;
- verify progress summaries.

Exit criterion:

- progress is reliable across launches.

---

## Phase 6 — Markdown Notes

Implement:

- matching `.md` lookup;
- load existing notes;
- empty editor for missing notes;
- create on first save;
- debounce autosave;
- save before lesson changes;
- save errors.

Automated tests:

- note URL is derived correctly;
- existing note loads;
- missing note stays absent until content is saved;
- note saves as UTF-8;
- atomic save preserves previous file if write fails;
- switching lessons triggers save.

Manual verification:

- write notes;
- inspect Markdown file in Finder;
- edit note externally;
- rescan and verify updated content;
- test read-only folder.

Exit criterion:

- notes are safe and portable.

---

## Phase 7 — Custom Ordering

Implement:

- stored order for modules, categories, and lessons;
- drag-and-drop reordering;
- merge new items after saved items;
- natural sorting for new items;
- reset to filename order.

Automated tests:

- saved ordering is respected;
- missing references do not appear;
- new items append naturally;
- drag-and-drop updates only the correct scope;
- reset affects only selected scope;
- order survives app restart.

Manual verification:

- reorder modules;
- reorder category lessons;
- add new files in Finder;
- verify new files appear after manually ordered items;
- reset one category without affecting others.

Exit criterion:

- custom ordering is deterministic and persistent.

---

## Phase 8 — Rename and Move

Implement:

- rename lesson;
- rename matching notes;
- rename module and category;
- move lesson between valid destinations;
- update metadata keys;
- preserve progress and ordering;
- rollback after partial failure.

Automated tests:

- lesson and note rename together;
- note absence is handled;
- extension is preserved;
- destination conflict blocks operation;
- invalid names are rejected;
- metadata key migrates;
- playback state survives rename;
- move preserves state;
- simulated note rename failure triggers rollback.

Manual verification:

- rename lessons with and without notes;
- rename modules and categories;
- move lessons between modules and categories;
- verify Finder structure;
- verify notes and progress remain connected;
- test conflicts.

Exit criterion:

- file operations are safe and reversible where possible.

---

## Phase 9 — Finder Change Detection

Implement:

- rescan when app becomes active;
- optional file-system watcher;
- debounced updates;
- current lesson disappearance handling;
- external note change detection.

Automated tests:

- rescan adds new files;
- rescan hides removed files;
- repeated change events result in one debounced rescan;
- current lesson removal clears playback safely;
- external note modification reload policy works.

Manual verification:

- add, remove, and rename content in Finder while app is open;
- return focus to app;
- verify UI refreshes;
- verify external rename is treated as a new lesson;
- verify old metadata becomes orphaned.

Exit criterion:

- Finder and app stay reasonably synchronized.

---

## Phase 10 — Search, Trash, and Polish

Implement:

- classroom-wide search;
- move lesson and notes to Trash;
- structural warning panel;
- clean missing lesson data;
- empty states;
- accessibility labels;
- keyboard shortcuts;
- basic visual polish.

Automated tests:

- search matches lesson, module, and category names;
- search returns correct context;
- Trash action includes matching notes;
- cleanup requires an explicit action;
- warning counts are accurate.

Manual verification:

- search across multiple modules;
- move a test lesson to Trash;
- recover it using Finder;
- inspect empty classroom state;
- test keyboard-only navigation;
- test larger folder structures.

Exit criterion:

- usable version 1 release candidate.

---

# 12. Testing Standards

## Unit Tests

Required for:

- folder parsing;
- sorting;
- metadata loading and saving;
- orphan handling;
- note URL derivation;
- ordering merge logic;
- rename validation;
- metadata key migration;
- progress calculations.

## Integration Tests

Use temporary directories for:

- scanning actual files;
- renaming video and note pairs;
- moving lesson pairs;
- metadata read/write;
- malformed metadata recovery;
- simulated file disappearance.

Never use the developer's real classroom folders in automated tests.

## UI Tests

At minimum test:

- opening a fixture classroom;
- selecting a lesson;
- navigating sidebar;
- marking complete;
- editing notes;
- reordering one lesson;
- showing a rename conflict.

## Failure Injection

Where practical, design services so tests can simulate:

- permission denied;
- write failure;
- file missing;
- malformed JSON;
- rename conflict;
- rollback failure.

---

# 13. Codex Working Rules

Codex must follow these rules while implementing:

1. Work on one phase only.
2. Before coding, summarize the current phase and list the files expected to change.
3. Write tests before or alongside implementation.
4. Run tests after each meaningful change.
5. Do not ignore failing tests.
6. Do not replace tested code with large speculative rewrites.
7. Prefer small services with explicit responsibilities.
8. Keep file-system logic outside SwiftUI views.
9. Keep metadata logic outside playback and UI code.
10. Never perform destructive file operations without validation.
11. Use temporary directories in tests.
12. Do not add features outside this specification unless required for correctness.
13. At the end of each phase, provide:
    - implemented functionality;
    - tests added;
    - test results;
    - manual checks performed;
    - known limitations;
    - exact next phase.

---

# 14. Definition of Done for Version 1

Version 1 is complete when:

- Any valid folder can be opened as a classroom.
- The four-depth hierarchy is displayed correctly.
- Local videos play reliably.
- Notes are stored as matching Markdown files.
- Playback position persists.
- Completion state persists.
- Modules, categories, and lessons can be manually reordered.
- Ordering is stored in classroom metadata.
- Lessons can be renamed and moved safely.
- Matching notes move and rename with lessons.
- Finder changes are detected through refresh or app activation.
- Missing lesson metadata is retained temporarily and later cleaned.
- Search works.
- Files can be moved to Trash with confirmation.
- Automated tests cover all core non-UI logic.
- Every implementation phase has passed its manual checklist.
- No user video or note is silently overwritten or deleted.
