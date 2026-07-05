# Changelog

All notable changes to shigoto_metrics are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and shigoto_metrics uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Prometheus metrics collectors for the shigoto telemetry surface (jobs, queues,
  resilience, batches, cron, testing-mode) and `shigoto_metrics:scrape/0`.
- Ready-to-import Grafana dashboard in `priv/grafana/shigoto.json`.
