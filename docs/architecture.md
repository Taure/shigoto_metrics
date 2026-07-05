# Architecture

`shigoto_metrics` is a thin adapter between two stable contracts:

- **shigoto's telemetry event surface** (the `[shigoto, ...]` events)
- **the Prometheus scrape format** (via `prometheus.erl`)

It owns no novel logic and has no web dependency. `shigoto_metrics_definitions:declare/0`
declares the Prometheus metrics, and `shigoto_metrics_handlers` attaches one
`telemetry` handler group that increments counters and observes histograms as
events fire. `shigoto_metrics:scrape/0` renders the current registry in
Prometheus text format for whatever web layer serves it.

## Process tree

```
shigoto_metrics_sup   (empty; the collectors live in the prometheus registry)
```

When `auto_setup` is `true` (default), the application start callback calls
`shigoto_metrics:setup/0`, which declares the metrics and attaches the telemetry
handlers via `telemetry:attach_many/4`. The handlers run in the process that
emits each event and do no I/O beyond a Prometheus counter/histogram update.
`handle/4` is total: a bad event is logged and swallowed, because `telemetry`
detaches any handler that raises and that would blank out every metric.

## No endpoint of its own

This package stands up no listener. The `/metrics` endpoint is served by the
consuming application's web layer — for a Nova app, a one-line controller
returning `shigoto_metrics:scrape/0`. This mirrors how Oban is observed: the
library emits telemetry, and the endpoint is mounted in the host app (PromEx in a
Phoenix endpoint), not stood up by the library. Reusing the host's listener means
the endpoint inherits its auth and network policy for free.

## Why a separate library

1. **Optional dependency.** Users who export telemetry via OpenTelemetry
   (`opentelemetry_shigoto`) or a custom pipeline are not forced into a
   Prometheus stack. `shigoto` core stays metric-stack-agnostic.
2. **Stable API contract.** Metric names and labels are public API. Keeping
   them in their own library makes versioning explicit.
3. **Dashboard JSON.** A Grafana dashboard is an opinionated asset that belongs
   in a companion library, not a core OTP library.

## Cardinality

Labels are restricted to bounded dimensions: `worker`, `queue`, `priority`,
snooze `reason`, cron `name`, testing `mode`. High-cardinality identifiers
(`job_id`, `batch_id`) are refused as labels because Prometheus is not a tracing
system; they remain on the raw telemetry events for tracing sinks.
