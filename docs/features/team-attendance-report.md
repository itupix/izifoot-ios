# Présences — Mon équipe

Coach/direction can open **Mon équipe → Présences**, select a team through the existing global selector, and consult the current season shown as contextual text. There is no season dropdown or history fallback. All-team scope asks for a single team and displays no previous team data.

The season summary displays the server percentage, present/recorded numerator and denominator, absences and unrecorded player-session counts. **Par mois** selects a month and expands dated training rows to reveal every player's status. **Par joueur** searches the current active roster only, selects a player and displays season and monthly summaries with dated training statuses. An empty current roster displays “Aucun joueur dans l’effectif actuel.” and no previous player detail. No attendance editing is introduced.

## API contract

`GET /teams/:teamId/attendance-report`, authenticated coach/direction, without a `seasonId` query. The server resolves or creates the current club season using its existing Europe/Paris calendar rules. Only active players of the selected team are returned and all summaries use that roster. No season catalog is loaded by this view. Errors: 400 if an obsolete noncurrent season is requested, 403 role, 404 missing/inaccessible team, club or current season.

Report includes `teamId`, season identity/dates, `generatedAt`, summary, months, trainings and players with monthly summaries and per-training statuses. Stats contain `presentCount`, `absentCount`, `unrecordedCount`, `recordedCount`, nullable `attendanceRate`. iOS renders server rates without recomputing business rules. Rate = present / (present + recorded absent), rounded by backend to one decimal. Zero recorded sessions displays **—**. Future, cancelled and unrecorded entries are excluded; intentions do not count. Backend considers sessions started at report generation, not a completed-session flag. Months and training date display use Europe/Paris. Statuses are PRESENT, ABSENT, UNRECORDED, UPCOMING, CANCELLED, NOT_APPLICABLE; every state has visible text and an icon.

A request generation identifier rejects obsolete responses, and task cancellation/report scope checks prevent previous team or scope data from appearing after selection changes. Network errors show retry; empty trainings/current rosters and no matching player have explicit messages. Pull to refresh reloads the report.

## Validation

Run standalone contract/state checks:

```sh
swiftc -module-cache-path /private/tmp/attendance-swift-cache izifoot/Features/Attendance/AttendanceReport.swift izifoot/Features/Attendance/AttendanceReportStore.swift tests/AttendanceReportChecks.swift -o /private/tmp/attendance-report-checks
/private/tmp/attendance-report-checks
```

Validation completed: standalone checks passed for decoding, all six statuses, null percentages, default month selection, current-season-only requests, late previous-team response rejection, current-season failures clearing old data without fallback, and all-team clearing. Debug iOS Simulator build passed with Xcode (`CODE_SIGNING_ALLOWED=NO`). UX source review passed; live rendering was not exercised. Manual acceptance: current season label with no selector, month expansion, accented player search, exclusion of inactive players, every attendance state, null percentage, weighted season totals, empty season, failed request/retry, rapid team switching and all-team selection. Check VoiceOver and narrow iPhone/Dynamic Type for the four Mon équipe segments. Runtime visual acceptance with live data remains required.
