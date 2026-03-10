# Sioyek Web

Rails sidecar for the Zig-first Sioyek fork.

This app is not the reader runtime. The desktop reader stays in Zig and owns rendering, commands, offline state, and local UX. `apps/web` provides the service layer around that product:

- account auth
- device registration
- cloud library records
- synced reader session state
- synced bookmarks, highlights, and notes
- lightweight admin and inspection pages

This repo is not being shaped around an upstream Qt pull request. `origin` is the independent Zig-first fork, `upstream` is reference-only, and Rails exists here as the product-service layer around that fork.

## Local boot

1. Ensure PostgreSQL is available locally.
2. Install gems:

```bash
cd apps/web
bundle install
```

3. Prepare the database:

```bash
bundle exec rails db:prepare
bundle exec rails db:seed
```

4. Start the app:

```bash
bundle exec rails server
```

## Environment

- Ruby: modern Ruby with Bundler available
- Database: PostgreSQL
- Optional env vars:
  - `SIOYEK_WEB_DB_USERNAME`
  - `SIOYEK_WEB_DB_PASSWORD`
  - `SIOYEK_WEB_DB_HOST`
  - `SIOYEK_WEB_DB_PORT`

The generated `config/master.key` is intentionally ignored in this fork. The sidecar does not need encrypted credentials for local development.

## Zig client contract

The Zig reader should use the JSON API under `/api/v1` for:

- `POST /api/v1/session`
- `DELETE /api/v1/session`
- `GET /api/v1/library_entries`
- `POST /api/v1/library_entries/register`
- `GET /api/v1/reader_session`
- `POST /api/v1/reader_session/upsert`
- `GET /api/v1/bookmarks`
- `POST /api/v1/bookmarks/upsert`
- `GET /api/v1/highlights`
- `POST /api/v1/highlights/upsert`
- `GET /api/v1/notes`
- `POST /api/v1/notes/upsert`

The intended model is offline-first: Zig remains usable without the network, and Rails acts as the optional sync and product-services layer.

## Test suite

```bash
bundle exec rails test
bundle exec rails zeitwerk:check
```

## Product trace

- Zig desktop app: rendering, commands, local-first reading, persistence, HUD, future classroom-friendly UX
- Rails sidecar: accounts, devices, sync, library services, admin, future classroom and teacher workflows
- Upstream repo: reference for feature inventory and occasional selective sync, not the governing product direction for this fork
