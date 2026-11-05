# Task Manager

A single-user task manager built with Flutter and Dart, Laravel 12, and MySQL 8.
SQLite stores tasks on-device for offline access; Laravel and MySQL provide the
central server copy.

## Setup

1. Install the Flutter SDK and Android Studio with an Android emulator or device.
2. From the project root, run `flutter pub get`.
3. Run `flutter run` to launch on the selected device.
4. Run `flutter analyze` and `flutter test` to validate the project.
5. Configure `backend/.env` with `DB_CONNECTION=mysql` and the MySQL connection
   values, then run
   `php artisan migrate` from `backend/` when setting up the server database.
6. Start the Laravel API with `php artisan serve`. For Android emulators, the
   default API URL uses `10.0.2.2`; override it with
   `--dart-define=TASK_API_BASE_URL=http://<host>:8000/api/v1/` for another
   device or environment.

## Technology

- Flutter / Dart with Material Design 3
- SQLite (`sqflite`) for on-device task storage and offline mutations
- Provider for application state
- Laravel REST API for synchronization
- MySQL 8 as the central server database
- `http` for REST requests, `connectivity_plus` for connectivity changes,
  `uuid` for stable task and mutation identifiers, `path` for SQLite paths,
  and `intl` for date/time formatting

The Flutter application never connects directly to MySQL. Keep database
credentials only in the backend environment configuration. This initial
single-user API intentionally has no authentication; expose it only on a
trusted network and use HTTPS outside local development.

## Synchronization protocol

- `POST /api/v1/sync` accepts an ordered `mutations` list. Each mutation has a
  unique `mutation_id`, stable `task_uuid`, `operation` (`upsert` or `delete`),
  `base_version`, and task fields for upserts.
- Repeating a mutation ID with the same content returns the original result.
  Reusing it with different content is rejected.
- `GET /api/v1/tasks?cursor=<cursor>` returns changed task snapshots, including
  soft-delete tombstones, and a `meta.next_cursor`.
- A version mismatch preserves local data and the server snapshot until the
  user chooses which task version to keep.

## Architecture

- `lib/models/`: task model, SQLite serialization, task status, and sync status
- `lib/database/`: SQLite schema, local tasks, sync outbox, and sync cursor
- `lib/repositories/`: local-first persistence and coordination with sync
- `lib/providers/`: task loading, CRUD state, sync state, counts, search, and filtering
- `lib/services/`: Laravel API client and offline synchronization
- `lib/screens/`: task list, create/edit form, and task details
- `lib/widgets/`: reusable task cards, form controls, status labels, summaries,
  and empty state
- `lib/utils/`: app theme, colours, and date/time formatting

SQLite retains the local integer row ID and stores a stable task UUID, optional
server UUID, sync status/version, UTC timestamps, and deletion tombstones. An
outbox records each mutation with its own idempotency UUID. Existing SQLite rows
are preserved during upgrade and queued for upload.

Laravel owns server-side persistence through Eloquent. MySQL stores UUID task
IDs, task versions, soft-deletion tombstones, an ordered change cursor, and
idempotency results. Task updates use optimistic version checks; conflicts
preserve both versions until the user chooses the local or server copy.
Date-times are sent and stored as UTC ISO-8601 values and converted to local
time only for display.

## Features

- Create, view, edit, and delete tasks with confirmation and feedback
- Search task titles and combine search with a status filter
- Toggle between Pending and Done from the task-list check icon or details
- View task counts, start/end date and time, and task details
- Validate required titles and ensure the end date/time is not before the start
- Show loading, empty, and database error states
- Create, edit, and delete tasks offline, then retry synchronization when
  connectivity returns
- Detect stale updates by server version and let the user resolve conflicts

## Screenshot

- [`screenshots/home.png`](screenshots/home.png) — emulator capture of the
  application home screen and empty state.

## Limitations

- Local changes remain on-device until synchronized; uninstalling or clearing
  app data removes the local copy.
- The assessment PDF was not present in the workspace.
