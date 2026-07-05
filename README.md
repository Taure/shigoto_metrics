# shigoto_metrics

Prometheus metrics collectors and Grafana dashboard for
[`shigoto`](https://github.com/Taure/shigoto).

Subscribes to the shigoto telemetry surface and exposes it as canonical
Prometheus metrics. A ready-to-import Grafana dashboard lives in
[`priv/grafana/shigoto.json`](priv/grafana/shigoto.json). `shigoto` itself takes
no dependency on this package, and this package has no web dependency — it only
needs `telemetry` and `prometheus`.

## Quickstart

Start the application (it declares the metrics and attaches the telemetry
handlers at boot):

```erlang
{ok, _} = application:ensure_all_started(shigoto_metrics).
```

Then serve `shigoto_metrics:scrape/0` from your app's web layer and point
Prometheus at it. On [Nova](https://github.com/novaframework/nova) — shigoto's
web framework — that is a one-line controller:

```erlang
-module(metrics_controller).
-export([index/1]).

index(_Req) ->
    {status, 200, #{~"content-type" => ~"text/plain; version=0.0.4"},
        shigoto_metrics:scrape()}.
```

wired into your routes:

```erlang
{"/metrics", {metrics_controller, index}, #{methods => [get]}}
```

Reusing your existing Nova listener means the endpoint sits behind whatever auth
and network policy your app already has. Import `priv/grafana/shigoto.json` into
Grafana.

Not on Nova? Return `scrape/0` from any handler you already run, or mount
`prometheus_cowboy2_handler` on your own Cowboy listener (add `prometheus_cowboy`
to your app — it is not a dependency here).

## What gets exported

| Metric | Type | Labels |
| --- | --- | --- |
| `shigoto_jobs_inserted_total` | counter | `worker`, `queue` |
| `shigoto_jobs_claimed_total` | counter | `worker`, `queue` |
| `shigoto_jobs_completed_total` | counter | `worker`, `queue` |
| `shigoto_jobs_failed_total` | counter | `worker`, `queue` |
| `shigoto_jobs_snoozed_total` | counter | `worker`, `queue`, `reason` |
| `shigoto_jobs_discarded_total` | counter | `worker`, `queue` |
| `shigoto_jobs_cancelled_total` | counter | `worker`, `queue` |
| `shigoto_queue_polls_total` | counter | `queue` |
| `shigoto_queue_paused_total` | counter | `queue` |
| `shigoto_queue_resumed_total` | counter | `queue` |
| `shigoto_resilience_rate_limited_total` | counter | `worker` |
| `shigoto_resilience_circuit_open_total` | counter | `worker` |
| `shigoto_resilience_bulkhead_full_total` | counter | `worker` |
| `shigoto_resilience_load_shed_total` | counter | `priority` |
| `shigoto_batches_completed_total` | counter | — |
| `shigoto_cron_scheduled_total` | counter | `name`, `worker` |
| `shigoto_testing_mode_armed_total` | counter | `mode` |
| `shigoto_job_duration_seconds` | histogram | `worker`, `queue` |
| `shigoto_job_queue_wait_seconds` | histogram | `worker`, `queue` |
| `shigoto_resilience_retry_after_seconds` | histogram | `worker` |

High-cardinality identifiers (`job_id`, `batch_id`) are kept out of labels; they
stay on the raw telemetry events for tracing sinks that need them. The per-job
`[shigoto, job, progress]` event is intentionally not exported.

`shigoto_testing_mode_armed_total` being non-zero in production is a red flag: a
testing insert mode (`inline`/`manual`) is armed and inserts are not persisting.
Alert on it.

**Cardinality:** label values must be bounded, developer-controlled dimensions.
Never route untrusted input into a `queue` name, a `priority`, or a snooze
`reason` — each distinct value mints a new time series.

## Configuration

| Key | Default | Meaning |
| --- | --- | --- |
| `auto_setup` | `true` | Declare metrics and attach handlers at application start. Set `false` to call `shigoto_metrics:setup/0` yourself. |

## License

MIT.
