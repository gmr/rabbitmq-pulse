-module(rabbitmq_pulse_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([handle_interval/0, process_interval/2, start_timer/1]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbitmq_pulse_worker.hrl").


-define(IDLE_INTERVAL, 5000).
-define(IGNORE_KEYS, [applications, auth_mechanisms, erlang_version, exchange_types, processors, statistics_level]).

start_link() ->
  gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).

%---------------------------
% Gen Server Implementation
% --------------------------

init([]) ->
  register(rabbitmq_pulse, self()),
  Exchanges = rabbitmq_pulse_lib:pulse_exchanges(),
  Connections = rabbitmq_pulse_lib:establish_connections(Exchanges),
  rabbit_log:info("rabbitmq-pulse initialized~n"),
  {ok, #rabbitmq_pulse_state{connections=Connections, exchanges=Exchanges}}.

handle_call(_Msg, _From, _State) ->
  {noreply, unknown_command, _State}.

handle_cast({on_exchange_timer, _Exchange}, State=#rabbitmq_pulse_state{connections=_Connections, exchanges=_Exchanges}) ->
  {noreply, State};

handle_cast({add_binding, Tx, X, B}, State) ->
  rabbit_log:info("add_binding: ~p ~p ~p ~p ~n", [Tx, X, B, State]),
  {noreply, State};

handle_cast({create, X = #exchange{name = #resource{virtual_host=VirtualHost, name=Name}, arguments = Args}}, State) ->
  rabbit_log:info("create: ~p ~p ~p ~p ~n", [VirtualHost, Name, Args, State]),
  {noreply, State};

handle_cast({delete, X, _Bs}, State) ->
  rabbit_log:info("delete: ~p ~p ~p ~n", [X, _Bs, State]),
  {ok, State};

handle_cast({policy_changed, _Tx, _X1, _X2}, State) ->
  rabbit_log:info("policy_changed: ~p, ~p, ~p ~p ~n", [_Tx, _X1, _X2, State]),
  {noreply, State};

handle_cast({recover, Exchange, Bs}, State) ->
  rabbit_log:info("recover: ~p ~p ~n", [Exchange, Bs, State]),
  {noreply, State};

handle_cast({remove_bindings, Tx, X, Bs}, State) ->
  rabbit_log:info("remove_binding: ~p ~p ~p ~p ~n", [Tx, X, Bs, State]),
  {noreply, State};

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

handle_interval() ->
  gen_server:cast({global, ?MODULE}, handle_interval).



build_stats_message(Node) ->
  Values = [{Key, Value} || {Key, Value} <- Node, not lists:member(Key, ?IGNORE_KEYS)],
  iolist_to_binary(mochijson2:encode(Values)).



get_routing_key(Type, Node) ->
  {name, Name} = lists:nth(1, Node),
  [_, Host] = string:tokens(atom_to_list(Name), "@"),
  iolist_to_binary(string:join([Type, Host], ".")).



node_stats(Node) ->
  {get_routing_key("node", Node), build_stats_message(Node)}.





process_cluster(Channel, Exchange) ->
  Overview = rabbit_mgmt_db:get_overview(),
  rabbitmq_pulse_lib:publish_message(Channel, Exchange, <<"overview">>,
                                      iolist_to_binary(mochijson2:encode(Overview)),
                                      <<"rabbitmq cluster overview">>).

process_node(Channel, Exchange, [Node]) ->
  {RoutingKey, Message} = node_stats(Node),
  rabbitmq_pulse_lib:publish_message(Channel, Exchange, RoutingKey, Message, <<"rabbitmq node stats">>).

%process_queues(Channel, Exchange, [Queue]) ->

process_interval(Channel, Exchange) ->
  process_cluster(Channel, Exchange),
  Nodes = rabbit_mgmt_wm_nodes:all_nodes(),
  process_node(Channel, Exchange, Nodes),
  Queues = rabbit_amqqueue:list().
  %process_queue(Channel, Exchange, Equeues).

start_timer(Duration) ->
  timer:apply_after(Duration, ?MODULE, idle_interval, []).
