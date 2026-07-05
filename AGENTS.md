# AGENTS.md

Working agreement for agents and contributors on **shigoto_metrics** - a
Prometheus exporter and starter Grafana dashboard for shigoto.

## Ecosystem

A shigoto companion library (all under https://github.com/Taure):

- **[shigoto](https://github.com/Taure/shigoto)** - PostgreSQL-backed background
  job queue for the Nova ecosystem (this library observes it).
- **[shigoto_board](https://github.com/Taure/shigoto_board)** - real-time web
  dashboard.
- **[opentelemetry_shigoto](https://github.com/Taure/opentelemetry_shigoto)** -
  OpenTelemetry spans for the job lifecycle.

**This repo** exports shigoto's telemetry events (the `[shigoto, ...]` surface
documented in shigoto's Telemetry guide) as Prometheus metrics and ships a
starter Grafana dashboard. Keep it in lockstep with any shigoto release that
changes the telemetry surface. shigoto core takes no dependency on this package.

## Conventions

- OTP 29+. The `~"..."` sigil, never `<<"...">>`. No `lists:foldl/foldr`.
- JSON via the OTP `json` module. `?LOG_*` macros with `#{...}` map reports.
- Docs: OTP `-moduledoc` / `-doc`. `{vsn, "git"}` - version derives from git tags.
- Default to zero comments; comment only non-obvious *why*.

## Commands

```bash
rebar3 compile
rebar3 eunit
rebar3 fmt          # CI runs fmt --check
rebar3 xref
rebar3 dialyzer
rebar3 ex_doc
```

## Git and PRs

Conventional commits. Always open a PR - never push to `main`. Every merge to
`main` tags a release.
