# Fork Architecture

This fork is building an independent product stack around a Zig-native reader.

## Ownership

- `origin` is the canonical repo for the Zig-first fork.
- `upstream` is kept only as a reference to the original Sioyek project.
- The goal is not to stage a Qt pull request back upstream.

## Product split

- Zig desktop app:
  - PDF rendering and windowing
  - shortcuts, commands, and on-screen guidance
  - local-first persistence and session state
  - beginner-friendly UX for strong K-12 readers
- Rails sidecar at `apps/web`:
  - accounts and device registration
  - cloud library records keyed by document fingerprint
  - sync for sessions, bookmarks, highlights, and notes
  - admin and future classroom workflows

## Why this split

- The reader stays fast, offline-first, and native.
- Product services stay out of the desktop runtime.
- Sync and classroom features can evolve without turning the reader into a web shell.
