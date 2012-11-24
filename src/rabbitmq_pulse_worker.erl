-module(rabbitmq_pulse_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([handle_interval/1]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbitmq_pulse_worker.hrl").


-define(IDLE_INTERVAL, 5000).

start_timer(Duration, Exchange) ->
  timer:apply_after(Duration, ?MODULE, handle_interval, [Exchange]).

start_exchange_timer(Exchange) ->
  start_timer(Exchange#rabbitmq_pulse_exchange.interval,
              Exchange#rabbitmq_pulse_exchange.exchange).

start_exchange_timers(Exchanges) ->
  [start_exchange_timer(Exchange) || Exchange <- Exchanges].

%---------------------------
% Gen Server Implementation
% --------------------------
start_link() ->
  gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).

init([]) ->
  register(rabbitmq_pulse, self()),
  Exchanges = rabbitmq_pulse_lib:pulse_exchanges(),
  Connections = rabbitmq_pulse_lib:establish_connections(Exchanges),
  start_exchange_timers(Exchanges),
  rabbit_log:info("rabbitmq-pulse initialized~n"),
  {ok, #rabbitmq_pulse_state{connections=Connections, exchanges=Exchanges}}.

handle_call(_Msg, _From, _State) ->
  {noreply, unknown_command, _State}.

handle_cast({handle_interval, ExchangeName}, State) ->
  Exchange = rabbitmq_pulse_lib:process_interval(ExchangeName,
                                                 State#rabbitmq_pulse_state.exchanges,
                                                 State#rabbitmq_pulse_state.connections),
  start_exchange_timer(Exchange),
  {noreply, State};

handle_cast({add_binding, none, _, Binding}, State) ->
  Exchanges = rabbitmq_pulse_lib:add_binding(State#rabbitmq_pulse_state.exchanges, Binding),
  NewState = #rabbitmq_pulse_state{connections=State#rabbitmq_pulse_state.connections,
                                   exchanges=Exchanges},
  {noreply, NewState};

handle_cast({create, #exchange{name = #resource{virtual_host=VirtualHost, name=Name}, arguments = Args}}, State) ->
  {Connections, Exchanges} = rabbitmq_pulse_lib:create_exchange(State#rabbitmq_pulse_state.connections,
                                                                State#rabbitmq_pulse_state.exchanges,
                                                                VirtualHost, Name, Args),
  {noreply, #rabbitmq_pulse_state{connections=Connections, exchanges=Exchanges}};

handle_cast({delete, Exchange, _Bs}, State) ->
  {Connections, Exchanges} = rabbitmq_pulse_lib:delete_exchange(State#rabbitmq_pulse_state.connections,
                                                                State#rabbitmq_pulse_state.exchanges,
                                                                Exchange),
  rabbit_log:info("Post delete:~n~p~n~p~n", [Connections, Exchanges]),
  {noreply, #rabbitmq_pulse_state{connections=Connections, exchanges=Exchanges}};

handle_cast({policy_changed, _Tx, _X1, _X2}, State) ->
  rabbit_log:info("policy_changed: ~p, ~p, ~p ~p ~n", [_Tx, _X1, _X2, State]),
  {noreply, State};

handle_cast({recover, Exchange, Bs}, State) ->
  rabbit_log:info("recover: ~p ~p ~n", [Exchange, Bs, State]),
  {noreply, State};

handle_cast({remove_bindings, none, _, Bindings}, State) ->
  Exchanges = rabbitmq_pulse_lib:remove_bindings(State#rabbitmq_pulse_state.exchanges, Bindings),
  NewState = #rabbitmq_pulse_state{connections=State#rabbitmq_pulse_state.connections,
                                   exchanges=Exchanges},
  {noreply, NewState};

handle_cast(_, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_, #rabbitmq_pulse_state{connections=_Connections}) ->
  % Close connections
  % amqp_channel:call(Channel, #'channel.close'{}),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%---------------------------

handle_interval(Exchange) ->
  gen_server:cast({global, ?MODULE}, {handle_interval, Exchange}).

