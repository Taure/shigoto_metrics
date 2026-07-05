-module(shigoto_metrics_definitions).
-moduledoc """
Declares the Prometheus metrics that `shigoto_metrics_handlers` updates from
shigoto telemetry events.

High-cardinality keys (`job_id`, `batch_id`) deliberately stay out of metric
labels; they remain on the raw telemetry events for tracing or audit sinks that
need them. Labels are limited to bounded dimensions: `worker`, `queue`,
`priority`, snooze `reason`, cron `name`, and testing `mode`.

Label values MUST be bounded, developer-controlled dimensions. Never route
untrusted input into a `queue` name, a `priority`, or a snooze `reason` (e.g. a
worker snoozing with a per-job id embedded in the reason): each distinct value
mints a new Prometheus series and unbounded values are a cardinality DoS on both
the exporter and the scraping Prometheus.

The `[shigoto, job, progress]` event is intentionally NOT exported. It is a
per-job `0..100` percentage that only aggregates meaningfully keyed by `job_id`,
which is excluded on purpose; it has no bounded counter or histogram shape.
""".

-export([declare/0]).

%% Job execution time spans seconds to minutes; wait time is usually short but
%% can spike under backlog.
-define(DURATION_BUCKETS, [0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10, 30, 60, 300]).
-define(WAIT_BUCKETS, [0.01, 0.05, 0.1, 0.5, 1, 5, 10, 30, 60, 300]).

-spec declare() -> ok.
declare() ->
    counters(),
    histograms(),
    ok.

counters() ->
    prometheus_counter:declare([
        {name, shigoto_jobs_inserted_total},
        {help, "Total jobs enqueued."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_claimed_total},
        {help, "Total jobs claimed for execution."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_completed_total},
        {help, "Total jobs completed successfully."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_failed_total},
        {help,
            "Total job execution failures (a job may fail several times before it is discarded)."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_snoozed_total},
        {help,
            "Total jobs snoozed (rescheduled without counting as a failure). The `reason` label "
            "must be a bounded enum; never embed per-job ids/timestamps in a snooze reason."},
        {labels, [worker, queue, reason]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_discarded_total},
        {help, "Total jobs discarded after exhausting their attempts."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_jobs_cancelled_total},
        {help, "Total jobs cancelled."},
        {labels, [worker, queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_queue_polls_total},
        {help, "Total queue polls."},
        {labels, [queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_queue_paused_total},
        {help, "Total queue pause operations."},
        {labels, [queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_queue_resumed_total},
        {help, "Total queue resume operations."},
        {labels, [queue]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_resilience_rate_limited_total},
        {help, "Total jobs snoozed by a per-worker rate limit."},
        {labels, [worker]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_resilience_circuit_open_total},
        {help, "Total jobs snoozed by an open circuit breaker."},
        {labels, [worker]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_resilience_bulkhead_full_total},
        {help, "Total jobs snoozed by a full bulkhead (local concurrency cap)."},
        {labels, [worker]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_resilience_load_shed_total},
        {help, "Total jobs shed by load shedding, by priority."},
        {labels, [priority]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_batches_completed_total},
        {help, "Total batches finished."},
        {labels, []}
    ]),
    prometheus_counter:declare([
        {name, shigoto_cron_scheduled_total},
        {help, "Total cron jobs scheduled."},
        {labels, [name, worker]}
    ]),
    prometheus_counter:declare([
        {name, shigoto_testing_mode_armed_total},
        {help,
            "A non-production testing insert mode was armed at boot. Non-zero in production means "
            "inserts are not persisting; alert on it."},
        {labels, [mode]}
    ]),
    ok.

histograms() ->
    prometheus_histogram:declare([
        {name, shigoto_job_duration_seconds},
        {help, "Wall-clock execution time of a job (completed or failed)."},
        {labels, [worker, queue]},
        {buckets, ?DURATION_BUCKETS}
    ]),
    prometheus_histogram:declare([
        {name, shigoto_job_queue_wait_seconds},
        {help, "Time a job waited between becoming due and being claimed."},
        {labels, [worker, queue]},
        {buckets, ?WAIT_BUCKETS}
    ]),
    prometheus_histogram:declare([
        {name, shigoto_resilience_retry_after_seconds},
        {help, "Backoff a rate-limited job was told to wait before retrying."},
        {labels, [worker]},
        {buckets, ?WAIT_BUCKETS}
    ]),
    ok.
