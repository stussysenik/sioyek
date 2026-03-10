# Sync API

JSON API contract between the Zig desktop reader and the Rails sidecar at `apps/web`.

## Auth model

- The Zig app signs in with email and password once.
- Rails returns a device-scoped bearer token.
- All later sync requests send `Authorization: Bearer <access_token>`.
- The Zig app should stay offline-first and treat sync as asynchronous.

## Shared rules

- Content type: `application/json`
- Document identity: `fingerprint` plus filename/title metadata
- Timestamps: ISO 8601 strings
- Per-record sync identity: `external_id`
- Soft delete: send `deleted_at` instead of hard-deleting remote records

## `POST /api/v1/session`

Creates or refreshes a device session for a user.

Request:

```json
{
  "email": "reader@example.com",
  "password": "verysecure123!",
  "device": {
    "name": "Classroom Mac",
    "platform": "macOS",
    "app_version": "0.2.0"
  }
}
```

Response:

```json
{
  "user": {
    "id": 1,
    "name": "Reader",
    "email": "reader@example.com",
    "role": "member"
  },
  "device": {
    "id": 1,
    "name": "Classroom Mac",
    "platform": "macOS",
    "app_version": "0.2.0",
    "access_token": "token",
    "last_seen_at": "2026-03-10T12:00:00Z"
  },
  "library_entries_count": 4
}
```

## `DELETE /api/v1/session`

Revokes the current device token by rotating it. Returns `204 No Content`.

## `GET /api/v1/library_entries`

Returns the current user’s registered library items.

Response:

```json
{
  "library_entries": [
    {
      "id": 2,
      "title": "Chemistry 101",
      "custom_title": null,
      "last_opened_at": "2026-03-10T12:00:00Z",
      "document": {
        "id": 3,
        "fingerprint": "sha256:reader-doc-1",
        "title": "Chemistry 101",
        "filename": "chemistry.pdf",
        "page_count": 512,
        "metadata": {
          "source": "desktop-import"
        }
      }
    }
  ]
}
```

## `POST /api/v1/library_entries/register`

Registers or refreshes a document in the user’s library.

Request:

```json
{
  "fingerprint": "sha256:reader-doc-1",
  "filename": "chemistry.pdf",
  "title": "Chemistry 101",
  "page_count": 512,
  "custom_title": "AP Chemistry",
  "metadata": {
    "source": "desktop-import"
  }
}
```

Response:

```json
{
  "library_entry": {
    "id": 2,
    "title": "AP Chemistry",
    "custom_title": "AP Chemistry",
    "last_opened_at": "2026-03-10T12:00:00Z",
    "document": {
      "id": 3,
      "fingerprint": "sha256:reader-doc-1",
      "title": "Chemistry 101",
      "filename": "chemistry.pdf",
      "page_count": 512,
      "metadata": {
        "source": "desktop-import"
      }
    }
  },
  "reader_session": null,
  "bookmark_count": 0,
  "highlight_count": 0,
  "note_count": 0
}
```

## `GET /api/v1/reader_session?library_entry_id=<id>`

Returns the latest synced reader session for that library entry.

## `POST /api/v1/reader_session/upsert`

Upserts per-device reader state.

Request:

```json
{
  "library_entry_id": 2,
  "current_page": 42,
  "zoom": 1.35,
  "fit_to_window": false,
  "last_opened_at": "2026-03-10T11:00:00Z",
  "client_updated_at": "2026-03-10T11:00:00Z"
}
```

## `GET /api/v1/bookmarks?library_entry_id=<id>`

Returns synced bookmarks for one library entry.

## `POST /api/v1/bookmarks/upsert`

Request:

```json
{
  "library_entry_id": 2,
  "bookmarks": [
    {
      "external_id": "bookmark-1",
      "page_index": 42,
      "label": "Key chapter",
      "note": "Review this before class",
      "client_updated_at": "2026-03-10T11:01:00Z",
      "deleted_at": null
    }
  ]
}
```

## `GET /api/v1/highlights?library_entry_id=<id>`

Returns synced highlights for one library entry.

## `POST /api/v1/highlights/upsert`

Request:

```json
{
  "library_entry_id": 2,
  "highlights": [
    {
      "external_id": "highlight-1",
      "page_index": 43,
      "quote": "Atoms bond by sharing electrons.",
      "color": "yellow",
      "anchor": "page=43&x=10&y=22",
      "annotation_text": "Core definition",
      "client_updated_at": "2026-03-10T11:02:00Z",
      "deleted_at": null
    }
  ]
}
```

## `GET /api/v1/notes?library_entry_id=<id>`

Returns synced notes for one library entry.

## `POST /api/v1/notes/upsert`

Request:

```json
{
  "library_entry_id": 2,
  "notes": [
    {
      "external_id": "note-1",
      "page_index": 43,
      "body": "Ask about ionic bonds next lesson.",
      "highlight_external_id": "highlight-1",
      "client_updated_at": "2026-03-10T11:03:00Z",
      "deleted_at": null
    }
  ]
}
```

## Recommended Zig sync flow

1. Sign in once with `POST /api/v1/session`.
2. Persist the returned device token locally.
3. On document open, call `POST /api/v1/library_entries/register`.
4. Pull `GET /api/v1/reader_session`, `GET /api/v1/bookmarks`, `GET /api/v1/highlights`, and `GET /api/v1/notes`.
5. Push local changes through the matching `upsert` endpoints.
6. Rotate the token with `DELETE /api/v1/session` on sign-out.
