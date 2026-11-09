# Task Manager

A multi-user task manager built with Flutter and Dart, Laravel 12, and MySQL 8.
SQLite stores each signed-in user's tasks on-device for offline access; Laravel
and MySQL provide the authenticated server copy.

## Setup

1. Install the Flutter SDK (Dart 3.13.7 or newer) and Android Studio with an
   Android emulator or device.
2. From the project root, run `flutter pub get`.
3. Configure `backend/.env` with `DB_CONNECTION=mysql` and the MySQL connection
   values. Configure SMTP using `MAIL_MAILER`, `MAIL_HOST`, `MAIL_PORT`,
   `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_SCHEME`, and `MAIL_FROM_ADDRESS` so
   registration credentials and password-reset links can be delivered. Set
   `APP_URL` to the public HTTPS backend URL for reset links. Keep real
   credentials out of source control.
4. From `backend/`, run `composer install`, `php artisan key:generate` if
   `APP_KEY` is empty, and `php artisan migrate`.
5. Start the Laravel API so other devices on your trusted local network can
   reach it:
   `php artisan serve --host=0.0.0.0 --port=8000`.
6. Return to the project root and run
   `flutter run --dart-define=TASK_API_BASE_URL=http://<host>:8000/api/v1/`.
   Use your PC's Wi-Fi IPv4 address for a physical device on the same Wi-Fi, or
   `http://10.0.2.2:8000/api/v1/` for an Android emulator. The configured
   address must be reachable from the device. HTTP cleartext is enabled only in
   Android debug builds; production deployments must use HTTPS.
7. Run `flutter analyze`, `flutter test`, and `php artisan test` to validate the
   Flutter and Laravel projects.

## Technology

- Flutter / Dart with Material Design 3
- SQLite (`sqflite`) for on-device task storage and offline mutations
- SQLite WebAssembly persisted in browser IndexedDB for Flutter Web
- Provider for application state
- Laravel Sanctum bearer tokens for API authentication
- `flutter_secure_storage` for encrypted mobile session storage
- Laravel REST API for synchronization
- MySQL 8 as the central server database
- `http` for REST requests, `connectivity_plus` for connectivity changes,
  `uuid` for stable task and mutation identifiers, `path` for SQLite paths,
  and `intl` for date/time formatting

The Flutter application never connects directly to MySQL. Keep database
credentials only in the backend environment configuration. Task APIs require
authentication with a Sanctum token; tokens expire after 30 days by default
(`SANCTUM_EXPIRATION` minutes). Configure SMTP before inviting users to register.
In Flutter Web, local SQLite data is stored in IndexedDB and is scoped to the
browser origin, including its port. Use the same `flutter run -d chrome` port to
reopen the same local database. The web SQLite implementation is experimental.

## Authentication

- Register at `POST /api/register` with a full name and email address. The
  backend generates a unique username and strong permanent password and emails
  the credentials; the registration endpoint does not accept a client password.
- Sign in at `POST /api/login` with `username` and `password`. Email verification
  and OTP are not required.
- OTP routes and screens are removed. The legacy OTP table is left untouched
  for existing databases rather than dropping its stored data.
- The app stores the bearer token and cached profile in Android/iOS secure
  storage. Protected endpoints include `GET /api/user`, `POST /api/logout`,
  `POST /api/change-password`, and both `/api/v1` task synchronization routes.
- Password recovery uses `POST /api/forgot-password`; Laravel emails an
  expiring, single-use reset link. The web form at
  `GET /reset-password/{token}` accepts the new password and confirmation.
  `POST /api/reset-password` is also available for clients that handle the
  token themselves. The forgot-password response does not disclose whether an
  email address is registered. Reset emails also include the username assigned
  to existing accounts during upgrade.
- `POST /api/change-password` verifies the current password and updates it.

Existing SQLite tasks and pending changes are retained and associated with the
first account that signs in after upgrading. On the server, a migration assigns
old tasks to the sole pre-existing user when exactly one exists; otherwise the
first registered account claims previously unowned legacy tasks. Server tasks
are shared: every authenticated account can view, update, and delete them.
Local task rows, outbox mutations, and sync cursors remain partitioned by
account. A synchronized shared task is cached separately for each signed-in
account, while pending mutations remain bound to the account that created them.
The SQLite upgrade resets only sync cursors so every account can download the
shared task history; it retains local task rows and outbox operations.
Signing out does not delete local task data, and the previous account's sync
worker is stopped before switching accounts.

## Synchronization protocol

- `POST /api/v1/sync` accepts an ordered `mutations` list. Each mutation has a
  unique `mutation_id`, stable `task_uuid`, `operation` (`upsert` or `delete`),
  `base_version`, and task fields for upserts.
- Repeating a mutation ID with the same content returns the original result.
  Reusing it with different content is rejected.
- `GET /api/v1/tasks?cursor=<cursor>` returns changed task snapshots, including
  soft-delete tombstones, and a `meta.next_cursor`.
- Both synchronization endpoints require `Authorization: Bearer <token>` and
  expose the shared task collection to every authenticated user. Server records
  retain the creating user and last updater.
- A version mismatch preserves local data and the server snapshot until the
  user chooses which task version to keep.

## Architecture

- `lib/models/`: task model, SQLite serialization, task status, and sync status
- `lib/models/auth_user.dart`: authenticated user profile model
- `lib/database/`: SQLite schema, local tasks, sync outbox, and sync cursor
- `lib/repositories/`: local-first persistence, authentication, and sync coordination
- `lib/providers/`: authentication and task state, sync state, counts, search, and filtering
- `lib/services/`: authenticated Laravel API clients, secure session storage, and offline synchronization
- `lib/screens/`: username login, registration, password recovery, profile/settings, and task screens
- `lib/widgets/`: reusable task cards, form controls, status labels, summaries,
  and empty state
- `lib/utils/`: app theme, colours, and date/time formatting

SQLite retains the local integer row ID and stores a stable task UUID, optional
server UUID, account ID, sync status/version, UTC timestamps, and deletion
tombstones. The outbox records account-scoped mutations with their own
idempotency UUID. Existing SQLite rows are preserved during upgrade and queued
for the first signed-in account.

Laravel owns server-side persistence through Eloquent. MySQL stores UUID task
IDs, creator/updater user IDs, task versions, soft-deletion tombstones, an
ordered change cursor, and idempotency results. Task updates use optimistic
version checks; conflicts preserve both versions until the user chooses the
local or server copy.
Task statuses remain Pending and Done. Date-times are sent and stored as UTC
ISO-8601 values and converted to local time only for display.

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
- Register and email generated credentials; sign in using username and password
- Recover passwords with secure email links and change passwords while signed in
- Share server tasks among authenticated users while keeping local pending
  mutations isolated by account

## Screenshot

- [`screenshots/home.png`](screenshots/home.png) — emulator capture of the
  application home screen and empty state.

## Limitations

- Local changes remain on-device until synchronized; uninstalling or clearing
  app data removes the local copy.
- The assessment PDF was not present in the workspace.
