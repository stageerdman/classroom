# Phase 3 Checklist

## Scope

- `.local-classroom/classroom.json`
- Schema version 1 metadata model
- Atomic metadata save
- Default metadata creation
- Malformed or unsupported metadata backup
- Lesson state merge with scan results
- Missing lesson orphan marking
- 30-day orphan cleanup

## Automated Verification

- `swift test`
- `swift run LocalClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run LocalClassroom`.
- Open a classroom folder.
- Inspect `.local-classroom/classroom.json`.
- Manually corrupt the JSON.
- Reopen or refresh the classroom.
- Verify a malformed backup file exists and the classroom remains usable.
