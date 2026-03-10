#!/usr/bin/env bash
set -euo pipefail

binary="${1:-./zig-out/bin/sioyek}"
document="${2:-tutorial.pdf}"
search_term="${3:-Sioyek}"
iterations="${4:-5}"
out_dir="${5:-benchmarks/results}"

mkdir -p "$out_dir"

timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
git_sha="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
raw_json="$(mktemp)"
time_log="$(mktemp)"
out_file="${out_dir}/zig-bench-${timestamp}.json"

cleanup() {
  rm -f "$raw_json" "$time_log"
}
trap cleanup EXIT

{
  /usr/bin/time -l "$binary" --bench "$document" "$search_term" "$iterations" >"$raw_json"
} 2>"$time_log"

real_seconds="$(awk '/ real / {print $1; exit}' "$time_log")"
max_rss="$(awk '/maximum resident set size/ {print $1; exit}' "$time_log")"
peak_footprint="$(awk '/peak memory footprint/ {print $1; exit}' "$time_log")"

jq -n \
  --arg timestamp "$timestamp" \
  --arg git_sha "$git_sha" \
  --arg binary "$binary" \
  --arg document "$document" \
  --arg search_term "$search_term" \
  --argjson iterations "$iterations" \
  --arg real_seconds "${real_seconds:-0}" \
  --argjson max_rss "${max_rss:-0}" \
  --argjson peak_footprint "${peak_footprint:-0}" \
  --slurpfile internal "$raw_json" \
  '{
    timestamp: $timestamp,
    git_sha: $git_sha,
    binary: $binary,
    document: $document,
    search_term: $search_term,
    iterations: $iterations,
    external: {
      real_seconds: ($real_seconds | tonumber),
      maximum_resident_set_size: $max_rss,
      peak_memory_footprint_bytes: $peak_footprint
    },
    internal: $internal[0]
  }' >"$out_file"

printf 'wrote %s\n' "$out_file"
