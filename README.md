# Task Manager

A personal task manager built with Flutter and Dart. Tasks are stored locally in
SQLite and remain on the device between app launches.

## Setup

1. Install the Flutter SDK and Android Studio with an Android emulator or device.
2. From the project root, run `flutter pub get`.
3. Run `flutter run` to launch on the selected device.
4. Run `flutter analyze` and `flutter test` to validate the project.

## Technology

- Flutter / Dart with Material Design 3
- SQLite (`sqflite`) for on-device task storage
- Provider for application state
- `path` for the SQLite file path and `intl` for date/time formatting

No Firebase, REST API, or cloud storage is used.

## Architecture

- `lib/models/`: task model, SQLite serialization, and the two task statuses
- `lib/database/`: SQLite database initialization and SQL operations
- `lib/repositories/`: persistence boundary between SQLite and application state
- `lib/providers/`: task loading, CRUD state, status counts, search, and filtering
- `lib/screens/`: task list, create/edit form, and task details
- `lib/widgets/`: reusable task cards, form controls, status labels, summaries,
  and empty state
- `lib/utils/`: app theme, colours, and date/time formatting

The `tasks` table stores `title`, optional `note`, ISO 8601 start/end date-times,
status, and creation time. New tasks default to `pending`.

## Features

- Create, view, edit, and delete tasks with confirmation and feedback
- Search task titles and combine search with a status filter
- Toggle between Pending and Done from the task-list check icon or details
- View task counts, start/end date and time, and task details
- Validate required titles and ensure the end date/time is not before the start
- Show loading, empty, and database error states
- Persist tasks locally after the app closes

## Screenshot

- [`screenshots/home.png`](screenshots/home.png) — emulator capture of the
  application home screen and empty state.

## Limitations

- Data is local to the app installation; uninstalling the app or clearing its
  app data removes saved tasks. There is no sync or backup service.
- The assessment PDF was not present in the workspace.
- The emulator build and launch were verified. Automated tests cover provider
  CRUD, status transitions, counts, and combined search/filter behavior; an
  end-to-end SQLite CRUD walkthrough and CRUD screenshots have not been
  captured.
