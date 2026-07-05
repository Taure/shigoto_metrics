-module(shigoto_metrics_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    setup_is_idempotent/1,
    job_lifecycle_increments_counters/1,
    job_completed_records_duration/1,
    job_claimed_records_queue_wait/1,
    snooze_records_reason/1,
    queue_events_increment_counters/1,
    resilience_events_increment_counters/1,
    cron_and_batch_increment_counters/1,
    testing_mode_armed_increments_counter/1,
    scrape_returns_prometheus_text/1
]).

all() ->
    [
        setup_is_idempotent,
        job_lifecycle_increments_counters,
        job_completed_records_duration,
        job_claimed_records_queue_wait,
        snooze_records_reason,
        queue_events_increment_counters,
        resilience_events_increment_counters,
        cron_and_batch_increment_counters,
        testing_mode_armed_increments_counter,
        scrape_returns_prometheus_text
    ].

init_per_suite(Config) ->
    application:set_env(shigoto_metrics, auto_setup, false),
    {ok, _} = application:ensure_all_started(shigoto_metrics),
    ok = shigoto_metrics:setup(),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(shigoto_metrics),
    ok.

setup_is_idempotent(_Config) ->
    ok = shigoto_metrics:setup(),
    ok = shigoto_metrics:setup(),
    ok.

job_lifecycle_increments_counters(_Config) ->
    Meta = #{worker => my_worker, queue => ~"default"},
    Before = counter_value(shigoto_jobs_inserted_total, [~"my_worker", ~"default"]),
    telemetry:execute([shigoto, job, inserted], #{count => 1}, Meta),
    telemetry:execute([shigoto, job, discarded], #{count => 1}, Meta),
    telemetry:execute([shigoto, job, cancelled], #{count => 1}, Meta),
    ?assertEqual(
        Before + 1, counter_value(shigoto_jobs_inserted_total, [~"my_worker", ~"default"])
    ),
    ?assertEqual(1, counter_value(shigoto_jobs_discarded_total, [~"my_worker", ~"default"])),
    ?assertEqual(1, counter_value(shigoto_jobs_cancelled_total, [~"my_worker", ~"default"])).

job_completed_records_duration(_Config) ->
    Meta = #{worker => my_worker, queue => ~"default"},
    Before = counter_value(shigoto_jobs_completed_total, [~"my_worker", ~"default"]),
    telemetry:execute(
        [shigoto, job, completed],
        #{count => 1, duration => erlang:convert_time_unit(120, millisecond, native)},
        Meta
    ),
    ?assertEqual(
        Before + 1, counter_value(shigoto_jobs_completed_total, [~"my_worker", ~"default"])
    ),
    ?assertEqual(1, histogram_count(shigoto_job_duration_seconds, [~"my_worker", ~"default"])).

job_claimed_records_queue_wait(_Config) ->
    Meta = #{worker => my_worker, queue => ~"default"},
    telemetry:execute([shigoto, job, claimed], #{count => 1, queue_wait_ms => 250}, Meta),
    ?assertEqual(1, counter_value(shigoto_jobs_claimed_total, [~"my_worker", ~"default"])),
    ?assertEqual(1, histogram_count(shigoto_job_queue_wait_seconds, [~"my_worker", ~"default"])).

snooze_records_reason(_Config) ->
    Meta = #{worker => my_worker, queue => ~"default", snooze_reason => ~"snooze"},
    telemetry:execute([shigoto, job, snoozed], #{count => 1}, Meta),
    ?assertEqual(
        1, counter_value(shigoto_jobs_snoozed_total, [~"my_worker", ~"default", ~"snooze"])
    ).

queue_events_increment_counters(_Config) ->
    telemetry:execute([shigoto, queue, poll], #{count => 1, claimed => 3}, #{queue => ~"default"}),
    telemetry:execute([shigoto, queue, paused], #{count => 1}, #{queue => ~"default"}),
    telemetry:execute([shigoto, queue, resumed], #{count => 1}, #{queue => ~"default"}),
    ?assertEqual(1, counter_value(shigoto_queue_polls_total, [~"default"])),
    ?assertEqual(1, counter_value(shigoto_queue_paused_total, [~"default"])),
    ?assertEqual(1, counter_value(shigoto_queue_resumed_total, [~"default"])).

resilience_events_increment_counters(_Config) ->
    telemetry:execute(
        [shigoto, resilience, rate_limited], #{count => 1, retry_after_ms => 500}, #{
            worker => rl_worker
        }
    ),
    telemetry:execute([shigoto, resilience, circuit_open], #{count => 1}, #{worker => rl_worker}),
    telemetry:execute([shigoto, resilience, bulkhead_full], #{count => 1}, #{worker => rl_worker}),
    telemetry:execute([shigoto, resilience, load_shed], #{count => 1}, #{priority => 5}),
    ?assertEqual(1, counter_value(shigoto_resilience_rate_limited_total, [~"rl_worker"])),
    ?assertEqual(1, histogram_count(shigoto_resilience_retry_after_seconds, [~"rl_worker"])),
    ?assertEqual(1, counter_value(shigoto_resilience_circuit_open_total, [~"rl_worker"])),
    ?assertEqual(1, counter_value(shigoto_resilience_bulkhead_full_total, [~"rl_worker"])),
    ?assertEqual(1, counter_value(shigoto_resilience_load_shed_total, [~"5"])).

cron_and_batch_increment_counters(_Config) ->
    telemetry:execute([shigoto, batch, completed], #{count => 1}, #{batch_id => 1}),
    telemetry:execute(
        [shigoto, cron, scheduled], #{count => 1}, #{name => ~"nightly", worker => cron_worker}
    ),
    ?assertEqual(1, counter_value(shigoto_batches_completed_total, [])),
    ?assertEqual(1, counter_value(shigoto_cron_scheduled_total, [~"nightly", ~"cron_worker"])).

testing_mode_armed_increments_counter(_Config) ->
    telemetry:execute([shigoto, testing, mode_armed], #{count => 1}, #{mode => manual}),
    ?assertEqual(1, counter_value(shigoto_testing_mode_armed_total, [~"manual"])).

scrape_returns_prometheus_text(_Config) ->
    Body = shigoto_metrics:scrape(),
    ?assert(is_binary(Body)),
    ?assert(binary:match(Body, ~"shigoto_jobs_inserted_total") =/= nomatch),
    ?assert(binary:match(Body, ~"shigoto_job_duration_seconds") =/= nomatch),
    ?assert(binary:match(Body, ~"shigoto_resilience_rate_limited_total") =/= nomatch),
    ?assert(binary:match(Body, ~"# HELP shigoto_") =/= nomatch),
    ?assert(binary:match(Body, ~"# TYPE shigoto_") =/= nomatch).

counter_value(Metric, Labels) ->
    case prometheus_counter:value(Metric, Labels) of
        undefined -> 0;
        V when is_number(V) -> V
    end.

histogram_count(Metric, Labels) ->
    case prometheus_histogram:value(Metric, Labels) of
        undefined -> 0;
        {Buckets, _Sum} -> lists:sum(Buckets)
    end.
