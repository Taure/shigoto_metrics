# Security

## Reporting a vulnerability

Open a private security advisory on GitHub, or email the maintainer.

## Surface

`shigoto_metrics` has **no network surface of its own**: it declares Prometheus
metrics and attaches `telemetry` handlers, and stands up no listener. Its only
runtime dependencies are `telemetry` and `prometheus`.

The `/metrics` scrape output (`shigoto_metrics:scrape/0`) is served by *your*
application's web layer, so exposure and authentication are governed there. The
output is operational metadata — worker and queue names, throughput, failure
rates, and the `shigoto_testing_mode_armed_total` flag — so serve it on a private
interface or behind auth, never on the public internet.

## Label cardinality

Metric label values must be bounded, developer-controlled dimensions. Never route
untrusted input into a `queue` name, a `priority`, or a snooze `reason`; each
distinct value creates a new time series, and unbounded values are a cardinality
denial-of-service on the exporter and the scraping Prometheus. See the
`shigoto_metrics_definitions` moduledoc.
