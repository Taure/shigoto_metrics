-module(shigoto_metrics).
-moduledoc """
Prometheus metrics collectors for [`shigoto`](https://github.com/Taure/shigoto).

Declares Prometheus metrics for the shigoto telemetry surface (see the
[Telemetry](https://hexdocs.pm/shigoto/telemetry.html) contract) and attaches
`m:telemetry` handlers that translate events into counter / histogram updates.

This package has no web dependency and stands up no listener of its own. Serve
the scrape output from your application's existing web layer. For a Nova app
(the shigoto ecosystem's web framework), a one-line controller does it:

```erlang
-module(metrics_controller).
-export([index/1]).

index(_Req) ->
    {status, 200, #{~"content-type" => ~"text/plain; version=0.0.4"},
        shigoto_metrics:scrape()}.
```

then route `{"/metrics", fun metrics_controller:index/1, #{methods => [get]}}`.

If you are not on Nova, mount `prometheus_cowboy2_handler` on your own Cowboy
listener, or return `scrape/0` from whatever handler you already run. Enabling
metrics is just:

```erlang
{ok, _} = application:ensure_all_started(shigoto_metrics).
```

`auto_setup` (default `true`) declares the metrics and attaches the handlers at
boot; set it to `false` to call `setup/0` yourself.
""".

-export([setup/0, scrape/0]).

-define(HANDLER_ID, shigoto_metrics_handler).

-doc "Declare metrics and attach telemetry handlers. Idempotent.".
-spec setup() -> ok.
setup() ->
    ok = shigoto_metrics_definitions:declare(),
    ok = shigoto_metrics_handlers:attach(?HANDLER_ID),
    ok.

-doc """
Render the current metrics in Prometheus text exposition format. Return this
from your `/metrics` handler with content type
`text/plain; version=0.0.4`.
""".
-spec scrape() -> binary().
scrape() ->
    iolist_to_binary(prometheus_text_format:format()).
