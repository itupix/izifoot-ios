# Présences — Mon équipe

Coach/direction can open **Mon équipe → Présences**, select a team through the existing global selector, then choose the current or a historical club season. All-team scope asks for a single team and displays no previous team data.

The season summary displays the server percentage, present/recorded numerator and denominator, absences and unrecorded player-session counts. **Par mois** selects a month and expands dated training rows to reveal every player's status. **Par joueur** searches the roster (including inactive players), selects a player and displays season and monthly summaries with dated training statuses. No attendance editing is introduced.

## API contract

`GET /teams/:teamId/attendance-report?seasonId=:seasonId`, authenticated coach/direction. 400 invalid/missing season, 403 role, 404 missing/inaccessible team or foreign season. Catalog uses the existing paginated `GET /clubs/me/seasons`, fully loaded through `allClubSeasons`; `isCurrent` selects the default season, otherwise the newest returned season.

Report includes `teamId`, season identity/dates, `generatedAt`, summary, months, trainings and players with monthly summaries and per-training statuses. Stats contain `presentCount`, `absentCount`, `unrecordedCount`, `recordedCount`, nullable `attendanceRate`. iOS renders server rates without recomputing business rules. Rate = present / (present + recorded absent), rounded by backend to one decimal. Zero recorded sessions displays **—**. Future, cancelled and unrecorded entries are excluded; intentions do not count. Backend considers sessions started at report generation, not a completed-session flag. Months and training date display use Europe/Paris. Statuses are PRESENT, ABSENT, UNRECORDED, UPCOMING, CANCELLED, NOT_APPLICABLE; every state has visible text and an icon.

A request generation identifier rejects obsolete responses, and task cancellation/report scope checks prevent previous team or season data from appearing after selection changes. Network errors show retry; empty seasons/trainings/rosters and no matching player have explicit messages. Pull to refresh reloads the report.

## Validation

Run standalone contract/state checks:

```sh
swiftc -module-cache-path /private/tmp/attendance-swift-cache izifoot/Features/Shell/AppTab.swift izifoot/Core/Models/APIModels.swift izifoot/Features/Attendance/AttendanceReport.swift izifoot/Features/Attendance/AttendanceReportStore.swift tests/AttendanceReportChecks.swift -o /private/tmp/attendance-report-checks
/private/tmp/attendance-report-checks
```

Validation completed: standalone checks passed for decoding, all six statuses, null percentages, default month selection, late previous-team response rejection and all-team clearing. Debug iOS Simulator build passed with Xcode (`CODE_SIGNING_ALLOWED=NO`). UX source review passed; live rendering was not exercised. Manual acceptance: current/history season, month expansion, accented player search, active/inactive players, every attendance state, null percentage, weighted season totals, empty season, failed request/retry, rapid team/season switching and all-team selection. Check VoiceOver and narrow iPhone/Dynamic Type for the four Mon équipe segments. Runtime visual acceptance with live data remains required.
