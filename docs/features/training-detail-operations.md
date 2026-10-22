# Training Detail Operations

## 1. Summary
- Clear description: Training detail screen with attendance, roles, drills, metadata edits, and status updates.
- User problem solved: Coaches can run session operations directly from mobile.
- Product value: Mobile parity for core training workflow.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Coaches need on-field friendly controls for session management.
- Target users: admin/coach primarily.
- Context of use: `TrainingDetailView`.
- Expected outcome: accurate, up-to-date training operational state.

## 3. Scope
Included
- Load training + players + attendance + drills + roles + intents.
- Update training metadata/status.
- Attendance toggles, role assignment, drill add/remove/reorder.

Excluded
- Planning list creation behavior.

## 4. Actors
- Admin
Permissions: full detail editing.
Actions: all operations.
Restrictions: scoped.
- Coach
Permissions: same in managed teams.
Actions: all scoped operations.
Restrictions: scope boundaries.
- Parent
Permissions: read-only context (intent handled elsewhere).
Actions: minimal interactions.
Restrictions: no structural edits.
- Player
Permissions: read-only context.
Actions: minimal interactions.
Restrictions: no structural edits.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: no screen.
- System
Permissions: orchestrates multi-request loading and synchronization.
Actions: keeps detail sub-sections consistent.
Restrictions: relies on backend contract stability.

## 5. Entry Points
- UI: navigation from planning list.
- API: training, attendance, roles, drills and drill-order endpoints.

## 6. User Flows
- Main flow: open detail -> update session info -> manage participants -> save.
- Variants: assign/remove drills and reorder.
- Back navigation: return to planning tab.
- Interruptions: partial fetch failure per section.
- Errors: mutation errors in sheets/alerts.
- Edge cases: no available players/drills.

## 7. Functional Behavior
- UI behavior: sheet-based editors for attendance, exercises, and metadata.
- Actions: save updates through dedicated API methods.
- States: loading, editing, persisting, error.
- Conditions: role and scope checks.
- Validations: field constraints and id presence.
- Blocking rules: disable controls during persistence.
- Automations: refresh dependent data after writes.

## 8. Data Model
- `Training`, `AttendanceRow`, `TrainingDrill`, `TrainingRoleAssignment`, `Drill`.
Source: endpoint aggregation.
Purpose: complete training operation context.
Format: codable structs in `APIModels.swift`.
Constraints: scope and relation integrity.

## 9. Business Rules
- Attendance updates use dedicated training attendance endpoint.
- Role updates submitted as assignment set.
- Drill order persisted item by item.

## 10. State Machine
- Detail states: loading/ready/error.
- Persist states: idle/persisting/success/failure.
- Training status transitions include planned/cancelled.
- Invalid transitions: save actions without loaded training object.

## 11. UI Components
- Detail header and metadata section.
- Attendance sheet.
- Exercise sheet.
- Role assignment editor.

## 12. Routes / API / Handlers
- Native: `TrainingDetailView` actions.
- API: `trainings.byID`, `trainings.attendance`, `trainings.roles`, `trainings.drills`.

## 13. Persistence
- Client: local state in view model/view.
- Backend: training-linked relational tables.

## 14. Dependencies
- Upstream: planning navigation and team scope.
- Downstream: stats and session execution.
- Cross-repo: aligned with web training detail intent.

## 15. Error Handling
- Validation: local input checks.
- Network: alerts for failed actions.
- Missing data: fallback rendering for absent optional payloads.
- Permissions: backend forbidden responses.
- Current vs expected: limited granular error typing.

## 16. Security
- Access control: auth and backend role checks.
- Data exposure: scoped data loading.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: clear save/progress indicators in sheets.
- Empty states: no players/no drills messaging.
- Loading: section-level progress feedback.
- Responsive: native sheet ergonomics on smaller devices.

## 18. Ambiguities & Gaps
- Observed
- Complex sheet orchestration in one large view file.
- Inferred
- Further modularization needed for long-term maintainability.
- Missing
- Unified conflict-resolution UX for concurrent edits.
- Tech debt
- High coupling between UI state and API response shape.

## 19. Recommendations
- Product: define minimal offline behavior expectations.
- UX: improve section-level retry affordances.
- Tech: split view into smaller components and state reducers.
- Security: preserve strict backend authorization checks.

## 20. Acceptance Criteria
1. Training detail loads all required related data.
2. Admin/coach can update attendance, roles, and drills.
3. Save failures are visible and recoverable.
4. Unauthorized users cannot perform restricted actions.

## 21. Test Scenarios
- Happy path: adjust attendance and roles in one session.
- Permissions: parent cannot edit metadata.
- Errors: drill reorder persistence failure.
- Edge cases: empty roster training.

## 22. Technical References
- `izifoot/Features/Planning/TrainingDetailView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`

## Training summary PDF

Coaches and direction open the session’s three-dot “Actions de la séance” menu and choose its first action, “Résumé” (native `doc.richtext` document icon), including for cancelled sessions. A divider separates this action from cancellation/reactivation and deletion. The standalone PDF button and its help text are removed. A toolbar progress indicator remains visible while downloading; the menu action is disabled during generation, loading, saves and drill reordering. Editors are modal: dismiss or save them before exporting; the summary always uses saved server data.

- Contract: authenticated `GET /trainings/:id/summary.pdf?timeZone=Europe%2FParis`, no request body. Uses existing Bearer token and active team headers.
- Success: binary `application/pdf` containing date, hours, actual recorded present players and attached exercises in saved order, each with full title and description. Attached exercises have no completion flag; attendance intentions are excluded.
- The downloaded PDF opens a large preview sheet titled “Résumé de la séance”, with “Fermer” on the left and “Partager le PDF” on the right. Native PDFKit displays the document with automatic scaling, continuous vertical scrolling and pinch zoom. The share button opens the native share sheet (including Save to Files) above the preview; closing sharing returns to the same preview. Both use the same local file without another API request. Temporary files use complete file protection and are removed only when the preview closes. An unreadable or empty PDF displays “Impossible d’afficher le PDF.” and disables sharing. Requests bypass the system HTTP response cache; the PDF response is private/no-cache/max-age=0/must-revalidate, and version metadata is private/no-store.
- Errors: 400 invalid timezone, 401 expired session (existing sign-in handling), 403 access denied, 404 missing training and 500 generation failure remain recoverable with the same button. Invalid/non-PDF successful responses are rejected.
- Manual acceptance: export a saved session and cancelled session; verify accented names, exercise order, long descriptions, empty attendance/exercises, Europe/Paris timezone, native sharing/cancel, network failure/retry and restricted-role visibility. Export must remain disabled until saves/reorder complete.

### Verification

The standalone networking check compiles the production API client against a stub URL protocol and verifies PDF bytes, authentication/team headers, cache bypass, malformed payload rejection, generation errors and session expiry:

```sh
swiftc -module-cache-path /tmp/izifoot-summary-swift-cache izifoot/Core/Networking/APIClient.swift tests/TrainingSummaryDownloadChecks.swift -o /tmp/check-training-summary
/tmp/check-training-summary
```

Swift syntax parsing and this networking check pass. Full iOS compilation and simulator share-sheet checks require a full Xcode installation; this environment only has Command Line Tools.

## Training observations

Observations has its own card between Informations and Exercices, with the same heading level and Modifier action. Its dedicated sheet contains the optional multiline editor, using the existing schedule-edit permissions (no editing for readers or cancelled sessions). Saved text appears in full in the Observations card, including for readers. Empty values display “Aucune observation”. Accents and line breaks remain unchanged; there is no client-side length limit.

`Training.observations` decodes as an optional string, including older responses omitting the key. `createTraining` and `updateTraining` accept optional observations. An omitted update leaves existing observations unchanged; the Observations editor sends only its string and sends an empty string to clear the field. Schedule and status updates omit observations; observation updates omit date, end time and status. The existing PDF endpoint includes saved observations without a new query parameter.

The modal editor blocks PDF access while editing. “Enregistrer” awaits success before dismissing. A failed save keeps the draft and displays a retry message. Closing explicitly confirms abandonment of unsaved changes; swipe dismissal is disabled. Saving disables all fields and dismissal. PDF help text states that only saved information is included.

Verification: unsigned Debug iPhoneOS arm64 build passes with Xcode (explicit `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); Swift syntax parsing passes; decoding checked with absent/null/empty/multiline accented observations. The existing production API client PDF networking check passes (including auth, team scope, PDF validation and errors). Manual device acceptance remains: save/reopen multiline text, clear/reopen, retry failed save, discard confirmation, inspect generated PDF, and compare coach/reader/cancelled-session permissions with schedule editing.

## PDF preview sheet verification

The preview uses the existing PDF endpoint unchanged. Verify a multipage document, scrolling, pinch zoom, toolbar accessibility labels, Share then Cancel returning to the preview, repeated sharing without downloading again, Close/swipe cleanup, and generation error/retry. The unreadable-document fallback keeps Close available and disables Share. No persistence or permission changes.

Validation: unsigned Debug iPhoneOS arm64 build and Swift syntax parsing pass. UX code review passes; simulator/device visual and sharing acceptance remains manual.

## PDF sheet transition responsiveness

The document is prepared once during generation, before presenting the preview. The preview initializer performs no PDF parsing. A lightweight native loading indicator occupies the preview area during the native sheet transition; the PDF view is mounted in its view controller’s `viewDidAppear`, after presentation completes. Mounting is idempotent so returning from sharing preserves zoom and scroll. Close, interactive dismissal, accessibility Reduce Motion behavior and file cleanup on preview dismissal remain native and unchanged.

Diagnostic: an isolated copy of the complete RootView → MainShell/TabView → TrainingDetailView hierarchy, using a real exported PDF, reported UIKit presentation/dismissal `animated=true` and no disabled SwiftUI transaction. Before the change, document parsing took about 27 ms and assigning the PDF view document about 48 ms on the simulator host, with document parsing repeated during recomposition. PDFKit work therefore occupied the presentation path beyond a 60 Hz frame budget. This supports removing that work from the transition; the user’s physical-iPhone symptom was not directly reproduced. No custom animation duration or forced transaction is introduced.

Acceptance: open and close using Fermer and swipe on a physical iPhone, compare Reduce Motion enabled/disabled, close during the loading indicator, and share/cancel/reopen sharing while verifying the existing zoom/position and saved PDF contents. The same downloaded file remains available until preview dismissal; no additional network request occurs.

Validation after the change: Debug iPhoneOS arm64 and simulator builds pass; UX code review passes. In the complete-hierarchy simulator diagnostic, native presentation remained animated and the PDF controller’s `viewDidAppear` occurred about 689 ms after presentation began; PDF mounting followed this callback rather than running during the transition. Physical-device smoothness, Reduce Motion and interactive dismissal still require device acceptance.

## Summary menu verification

The existing PDF request, native animated preview, sharing and cleanup remain unchanged. “Résumé” is available only with existing writable permissions and remains available on cancelled sessions. Unsaved editors remain modal. Check the first menu action, document icon, toolbar loading feedback, repeated taps while downloading, generation error/retry and reader-role visibility.

Validation: Swift syntax parsing and unsigned Debug iPhoneOS arm64 build pass; UX code review passes. Physical-device menu interaction remains manual.

## Versioned private PDF cache

Opening Résumé first calls authenticated `GET /trainings/:id/summary-version?timeZone=Europe%2FParis`. Its `{version,timeZone}` identifies the current PDF snapshot including related players, attendance, drills, diagrams, observations, timezone and renderer version. This lightweight request does not render a PDF. A valid local PDF with the same version opens without calling the generation endpoint. Missing, corrupt or changed files trigger the existing PDF download; `X-Training-Summary-Version` from that exact response labels the stored bytes, covering a change between metadata and generation requests. Invalid/missing version headers or unreadable/empty PDFs are never cached.

The durable cache is separate from preview/share files, in private Application Support with complete file protection and backup exclusion. Keys include account, club, active team, training, server-canonical timezone, client cache format and server snapshot version. A valid replacement is written atomically before older versions of the same scope are removed. Concurrent opens of the same scope share one request. Closing preview deletes only its protected temporary copy; the durable PDF survives app relaunch. Normal session restoration preserves this cache. Logout/account changes cancel pending cache work and purge durable and temporary PDFs; changed sessions cannot write or open old results. Deleted/inaccessible sessions (403/404) invalidate their cached PDFs. Version checks happen every opening, so local and remote edits are both detected. Offline/failed checks show an explicit retry error and never silently open an unverified old snapshot.

The toolbar uses generic loading while checking metadata and generation feedback only on a cache miss. Menu placement, animated preview, sharing and permissions are unchanged.

Targeted verification:

```sh
swiftc -module-cache-path /tmp/izifoot-summary-cache-swift-cache izifoot/Core/Networking/APIClient.swift izifoot/Core/Storage/TrainingSummaryCache.swift tests/TrainingSummaryCacheChecks.swift -o /tmp/check-training-summary-cache
/tmp/check-training-summary-cache
```

The real-file service harness verifies persistent hits with zero PDF download calls, missing/corrupt/changed cache, metadata/render version races, offline rejection, canonical timezone aliases, account/club/team/timezone isolation, request deduplication, invalid/missing headers, expired-session rejection and 403/404/purge cleanup. The existing API client PDF harness also verifies extraction of the server version header. Manual device acceptance: reopen unchanged PDF, edit local and remote training dependencies, retry offline, relaunch app, share/close, switch accounts, log out and verify data protection on a locked device.

Validation: targeted cache and API client networking harnesses pass; unsigned Debug iPhoneOS arm64 build passes; UX review confirms unchanged preview and transparent cache behavior.

### Observations section verification (2026-10-22)

Debug iOS Simulator build passes with Xcode and signing disabled. UX source review confirms peer card order, dedicated editor, multiline/empty rendering, read-only and cancelled-session restrictions, failure draft retention and explicit discard. Device interaction remains a manual acceptance check.
