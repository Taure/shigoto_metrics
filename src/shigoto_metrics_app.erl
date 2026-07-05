-module(shigoto_metrics_app).
-moduledoc false.

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    case application:get_env(shigoto_metrics, auto_setup, true) of
        true -> ok = shigoto_metrics:setup();
        false -> ok
    end,
    shigoto_metrics_sup:start_link().

stop(_State) ->
    ok.
