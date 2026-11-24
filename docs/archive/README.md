# Archived Documentation

These files are historical records. They are **not** updated against the
current codebase and should not be used as implementation references.

| Document | What it records | Why archived |
|---|---|---|
| [APP_SIZE_OPTIMIZATION_PLAN.md](APP_SIZE_OPTIMIZATION_PLAN.md) | 2026-09 size and memory plan for 0.17.2-beta.3 | Superseded; several recommendations conflict with the current PocketBase sidecar packaging. Outcomes are summarized in the Phase 0/1 reports. |
| [PHASE0_BASELINE.md](PHASE0_BASELINE.md) | Size/R8/memory baseline for 0.17.2-beta.3 | One-off measurement; artifacts are in `baseline_artifacts/`. |
| [PHASE1_REPORT.md](PHASE1_REPORT.md) | Quick-win results for 0.17.2-beta.3 | One-off measurement; later packaging changes supersede its extraction notes. Artifacts are in `phase1_artifacts/`. |
| [IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) | Product improvement phases 0–5 | All phases are complete; kept as a delivery record. |
| [refactor_roadmap.md](refactor_roadmap.md) | Service/gallery split and Riverpod modernization plan | Phases 0–3 are complete. Phase 4 (Riverpod modernization) was never started; see the note below. |

## Still-open item from the refactor roadmap

Phase 4 (remove service singletons and migrate off `flutter_riverpod/legacy.dart`)
is the only unfinished item. If that work resumes, write a fresh, short
`docs/riverpod_modernization.md` against the current service graph instead of
reviving the old line-numbered plan. The stale plan's target list includes
`VaultService`, `EncryptionService`, `FileImportService`, `CompressionService`,
`NoteService`, `PasswordService`, and the other `static final … instance`
services still present under `lib/services/`.
