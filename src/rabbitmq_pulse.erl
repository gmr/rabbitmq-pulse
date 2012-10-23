-module(rabbitmq_pulse).

-behaviour(application).

-export([start/2, stop/1]).

start(normal, []) ->
  rabbitmq_pulse_sup:start_link().

stop(_State) ->
  ok.
