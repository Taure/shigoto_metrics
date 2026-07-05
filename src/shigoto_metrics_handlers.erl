-module(shigoto_metrics_handlers).
-moduledoc """
`m:telemetry` handlers that translate shigoto events into Prometheus updates.

Attached by `shigoto_metrics:setup/0`. Idempotent: attaching the same
`HandlerId` twice is a no-op. `handle/4` is total — a bad event is logged and
swallowed rather than raising, because `telemetry` detaches any handler that
throws, which would silently blank out every metric.
""".

-include_lib("kernel/include/logger.hrl").

-export([attach/1, detach/1, handle/4]).

-define(EVENTS, [
    [shigoto, job, inserted],
    [shigoto, job, claimed],
    [shigoto, job, completed],
    [shigoto, job, failed],
    [shigoto, job, snoozed],
    [shigoto, job, discarded],
    [shigoto, job, cancelled],
    [shigoto, queue, poll],
    [shigoto, queue, paused],
    [shigoto, queue, resumed],
    [shigoto, resilience, rate_limited],
    [shigoto, resilience, circuit_open],
    [shigoto, resilience, bulkhead_full],
    [shigoto, resilience, load_shed],
    [shigoto, batch, completed],
    [shigoto, cron, scheduled],
    [shigoto, testing, mode_armed]
]).

-define(LABEL_MAX, 128).

-spec attach(term()) -> ok.
attach(HandlerId) ->
    case telemetry:attach_many(HandlerId, ?EVENTS, fun ?MODULE:handle/4, []) of
        ok -> ok;
        {error, already_exists} -> ok
    end.

-spec detach(term()) -> ok.
detach(HandlerId) ->
    _ = telemetry:detach(HandlerId),
    ok.

-spec handle(telemetry:event_name(), map(), map(), term()) -> ok.
handle(Event, Measurements, Meta, Config) ->
    try
        do_handle(Event, Measurements, Meta, Config)
    catch
        Class:Reason:Stack ->
            ?LOG_WARNING(#{
                msg => ~"shigoto_metrics_handler_error",
                event => Event,
                class => Class,
                reason => Reason,
                stacktrace => Stack
            }),
            ok
    end.

do_handle([shigoto, job, inserted], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_inserted_total, [worker(Meta), queue(Meta)]),
    ok;
do_handle([shigoto, job, claimed], Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_claimed_total, [worker(Meta), queue(Meta)]),
    prometheus_histogram:observe(
        shigoto_job_queue_wait_seconds,
        [worker(Meta), queue(Meta)],
        ms_to_seconds(maps:get(queue_wait_ms, Measurements, 0))
    ),
    ok;
do_handle([shigoto, job, completed], Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_completed_total, [worker(Meta), queue(Meta)]),
    observe_duration(Meta, Measurements),
    ok;
do_handle([shigoto, job, failed], Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_failed_total, [worker(Meta), queue(Meta)]),
    observe_duration(Meta, Measurements),
    ok;
do_handle([shigoto, job, snoozed], _Measurements, Meta, _Config) ->
    Reason = label(maps:get(snooze_reason, Meta, undefined)),
    prometheus_counter:inc(shigoto_jobs_snoozed_total, [worker(Meta), queue(Meta), Reason]),
    ok;
do_handle([shigoto, job, discarded], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_discarded_total, [worker(Meta), queue(Meta)]),
    ok;
do_handle([shigoto, job, cancelled], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_jobs_cancelled_total, [worker(Meta), queue(Meta)]),
    ok;
do_handle([shigoto, queue, poll], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_queue_polls_total, [queue(Meta)]),
    ok;
do_handle([shigoto, queue, paused], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_queue_paused_total, [queue(Meta)]),
    ok;
do_handle([shigoto, queue, resumed], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_queue_resumed_total, [queue(Meta)]),
    ok;
do_handle([shigoto, resilience, rate_limited], Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_resilience_rate_limited_total, [worker(Meta)]),
    prometheus_histogram:observe(
        shigoto_resilience_retry_after_seconds,
        [worker(Meta)],
        ms_to_seconds(maps:get(retry_after_ms, Measurements, 0))
    ),
    ok;
do_handle([shigoto, resilience, circuit_open], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_resilience_circuit_open_total, [worker(Meta)]),
    ok;
do_handle([shigoto, resilience, bulkhead_full], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_resilience_bulkhead_full_total, [worker(Meta)]),
    ok;
do_handle([shigoto, resilience, load_shed], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_resilience_load_shed_total, [label(maps:get(priority, Meta, 0))]),
    ok;
do_handle([shigoto, batch, completed], _Measurements, _Meta, _Config) ->
    prometheus_counter:inc(shigoto_batches_completed_total, []),
    ok;
do_handle([shigoto, cron, scheduled], _Measurements, Meta, _Config) ->
    Name = label(maps:get(name, Meta, undefined)),
    prometheus_counter:inc(shigoto_cron_scheduled_total, [Name, worker(Meta)]),
    ok;
do_handle([shigoto, testing, mode_armed], _Measurements, Meta, _Config) ->
    prometheus_counter:inc(shigoto_testing_mode_armed_total, [
        label(maps:get(mode, Meta, undefined))
    ]),
    ok;
do_handle(_Event, _Measurements, _Meta, _Config) ->
    ok.

observe_duration(Meta, Measurements) ->
    prometheus_histogram:observe(
        shigoto_job_duration_seconds,
        [worker(Meta), queue(Meta)],
        native_to_seconds(maps:get(duration, Measurements, 0))
    ).

worker(Meta) ->
    label(maps:get(worker, Meta, undefined)).

queue(Meta) ->
    label(maps:get(queue, Meta, undefined)).

native_to_seconds(N) when is_integer(N), N >= 0 ->
    N / erlang:convert_time_unit(1, second, native);
native_to_seconds(_) ->
    0.0.

ms_to_seconds(N) when is_number(N), N >= 0 ->
    N / 1000;
ms_to_seconds(_) ->
    0.0.

%% Labels come from bounded developer-controlled metadata; the fallback only
%% guards against an unexpected term and is truncated so it can never mint a
%% giant, high-cardinality label value.
label(undefined) -> ~"unknown";
label(A) when is_atom(A) -> atom_to_binary(A);
label(B) when is_binary(B) -> truncate(B);
label(I) when is_integer(I) -> integer_to_binary(I);
label(Term) -> truncate(iolist_to_binary(io_lib:format("~p", [Term]))).

truncate(Bin) when byte_size(Bin) =< ?LABEL_MAX ->
    Bin;
truncate(Bin) ->
    <<Head:?LABEL_MAX/binary, _/binary>> = Bin,
    <<Head/binary, "...">>.
