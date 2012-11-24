-module(rabbitmq_pulse_lib).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbitmq_pulse_worker.hrl").

-export([add_binding/2,
         create_exchange/4,
         delete_exchange/4,
         establish_connections/1,
         process_interval/3,
         pulse_exchanges/0,
         remove_bindings/2]).

-define(PREFIX, "rabbitmq_pulse").
-define(DEFAULT_INTERVAL, 5000).
-define(IGNORE_KEYS, [applications, auth_mechanisms, erlang_version, exchange_types, processors, statistics_level, pid,
                      owner_pid, exclusive_consumer_pid, slave_pids, synchronised_slave_pids]).
-define(OVERVIEW_BINDINGS, [<<"#">>, <<"overview">>]).

-define(OVERVIEW_TYPE, <<"rabbitmq cluster overview">>).
-define(NODE_TYPE,  <<"rabbitmq node stats">>).
-define(QUEUE_TYPE, <<"rabbitmq queue stats">>).

-define(GRAPHITE_OVERVIEW_TYPE,  <<"rabbitmq-pulse cluster overview graphite datapoint">>).
-define(GRAPHITE_NODE_TYPE,  <<"rabbitmq-pulse node graphite datapoint">>).
-define(GRAPHITE_QUEUE_TYPE,  <<"rabbitmq-pulse queue graphite datapoint">>).

%% General functions

convert_gregorian_to_julian(GregorianSeconds) ->
  GregorianSeconds - 719528 * 24 * 3600.

current_gregorian_timestamp() ->
  calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time(now())).

current_timestamp() ->
  convert_gregorian_to_julian(current_gregorian_timestamp()).

get_env(EnvVar, DefaultValue) ->
  case application:get_env(rabbitmq_pulse, EnvVar) of
    undefined ->
      DefaultValue;
    {ok, V} ->
      V
  end.

%% Functions for getting and filtering info from RabbitMQ configuration

add_binding_to_exchange(Exchange, Source, RoutingKey) when Exchange#rabbitmq_pulse_exchange.exchange =:= Source ->
  Bindings = sets:to_list(sets:from_list(lists:append(Exchange#rabbitmq_pulse_exchange.bindings, [RoutingKey]))),
  #rabbitmq_pulse_exchange{virtual_host=Exchange#rabbitmq_pulse_exchange.virtual_host,
                           username=Exchange#rabbitmq_pulse_exchange.username,
                           exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                           interval=Exchange#rabbitmq_pulse_exchange.interval,
                           format=Exchange#rabbitmq_pulse_exchange.format,
                           cluster=Exchange#rabbitmq_pulse_exchange.cluster,
                           bindings=Bindings};

add_binding_to_exchange(Exchange, _, _) ->
  Exchange.

add_binding(Exchanges, {binding, {resource, _, exchange, Source}, RoutingKey, {resource,_,queue, _},_}) ->
  [add_binding_to_exchange(X, Source, RoutingKey) || X <- Exchanges].

add_startup_bindings(Exchanges) ->
  [get_exchange_bindings(Exchange) || Exchange <- Exchanges].

binding_exchange_and_routing_key([{source_name, Exchange}, {source_kind,exchange}, {destination_name,_}, {destination_kind,queue}, {routing_key,RoutingKey}, {arguments,_}]) ->
  {Exchange, RoutingKey}.

create_exchange(Connections, Exchanges, VirtualHost, Exchange) ->
  rabbit_log:info('Create exchange: ~p~n~p~n', [VirtualHost, Exchange]),
  {Connections, Exchanges}.

delete_exchange(Connections, Exchanges, VirtualHost, Exchange) ->
  rabbit_log:info('Delete exchange: ~p~n~p~n', [VirtualHost, Exchange]),
  {Connections, Exchanges}.

distinct_vhost_pairs(Exchanges) ->
  lists:usort([{X#rabbitmq_pulse_exchange.virtual_host, X#rabbitmq_pulse_exchange.username} || X <- Exchanges]).

filter_bindings(Exchange, Bindings) ->
  sets:to_list(sets:from_list(lists:flatten([RoutingKey ||  {BindingExchange, RoutingKey}  <- remapped_bindings(Bindings),
                              BindingExchange =:= Exchange]))).

filter_pulse_exchange(Exchange={exchange,{resource, _, exchange, _}, 'x-pulse', _, _, _, _, _, _}) ->
  Exchange;

filter_pulse_exchange({exchange,{resource, _, exchange, _}, _, _, _, _, _, _, _}) ->
  null.

find_connection(Exchange, Connections)->
  [Connection] = [C || C <- Connections, has_exchange(C, Exchange)],
  Connection.

flatten(A, B, Subitem) when is_list(Subitem) ->
  lists:flatten([[A, B, C, D] || {C, D} <- Subitem]);

flatten(A, B, Subitem) when is_number(Subitem) ->
  lists:flatten([A, B, Subitem]).

get_all_exchanges() ->
  VirtualHosts = get_virtual_hosts(),
  get_exchanges(VirtualHosts).

get_exchange_bindings(Exchange) ->
  #rabbitmq_pulse_exchange{virtual_host=Exchange#rabbitmq_pulse_exchange.virtual_host,
                           username=Exchange#rabbitmq_pulse_exchange.username,
                           exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                           interval=Exchange#rabbitmq_pulse_exchange.interval,
                           format=Exchange#rabbitmq_pulse_exchange.format,
                           cluster=Exchange#rabbitmq_pulse_exchange.cluster,
                           bindings=get_bindings_from_rabbitmq(Exchange)}.

get_bindings_from_rabbitmq(Exchange) ->
  filter_bindings(Exchange#rabbitmq_pulse_exchange.exchange,
                  rabbit_binding:info_all(Exchange#rabbitmq_pulse_exchange.virtual_host)).

get_binding_tuple(Value) ->
  list_to_tuple(get_binding_tuple(Value, [], [])).

get_binding_tuple(<<>>, [], []) ->
  [];

get_binding_tuple(<<>>, ReversedWord, ReversedRest) ->
  lists:reverse([lists:reverse(ReversedWord) | ReversedRest]);

get_binding_tuple(<<$., Rest/binary>>, ReversedWord, ReversedRest) ->
  get_binding_tuple(Rest, [], [lists:reverse(ReversedWord) | ReversedRest]);

get_binding_tuple(<<C:8, Rest/binary>>, ReversedWord, ReversedRest) ->
  get_binding_tuple(Rest, [C | ReversedWord], ReversedRest).

get_channel(Exchange, Connections) ->
  Connection = find_connection(Exchange, Connections),
  Connection#rabbitmq_pulse_connection.channel.

get_cluster_name(Args) ->
  case lists:keysearch(<<"cluster">>, 1, Args) of
    {value, Tuple} ->
      case Tuple of
        {_, longstr, Value} ->
          Value;
        {_, _, _} ->
          get_node_name()
      end;
    false ->
      get_node_name()
  end.

get_exchanges([VirtualHost]) ->
  rabbit_exchange:list(VirtualHost).

get_format(Args) ->
  case lists:keysearch(<<"format">>, 1, Args) of
    {value, Tuple} ->
      case Tuple of
        {_, longstr, <<"graphite">>} ->
          graphite;
        {_, longstr, <<"json">>} ->
          json;
        {_, longstr, _} ->
          json
      end;
    false ->
      json
  end.

get_interval(Args) ->
  case lists:keysearch(<<"interval">>, 1, Args) of
    {value, Tuple} ->
      case Tuple of
        {_, longstr, Value} ->
          ListValue = bitstring_to_list(Value),
          {Integer, _} = string:to_integer(ListValue),
          case Integer of
            error ->
              {Float, _} = string:to_float(ListValue),
              case Float of
                error ->
                  get_env(interval, ?DEFAULT_INTERVAL);
                _ ->
                  Float
              end;
            _ ->
              Integer
          end;
        {_, integer, Value} ->
          Value;
        {_, float, Value} ->
          Value;
        {_, long, Value} ->
          Value
      end;
    false ->
      get_env(default_interval, ?DEFAULT_INTERVAL)
  end.

get_kvp(Value) ->
  pair_up(lists:flatten([[[[flatten(A,D,E)] || {D,E} <- B]] || {A,B} <- Value])).

get_node_name() ->
  string:join(string:tokens(atom_to_list(node(self())), "@"), ".").

get_node_name(Node) ->
  case lists:keysearch(name, 1, Node) of
    {value, {name, Name}} ->
      atom_to_list(Name);
    false -> "unknown"
  end.

get_queues() ->
  rabbit_mgmt_db:augment_queues([rabbit_mgmt_format:queue(Q) || Q <- rabbit_amqqueue:list()], full).

get_node_routing_key(Node) ->
  Value = tuple_to_list(get_node_routing_key_tuple(get_node_name(Node))),
  iolist_to_binary(string:join(Value, ".")).

get_node_routing_key_tuple(Value) ->
  list_to_tuple(lists:merge(["node"], string:tokens(Value, "@"))).

get_queue_routing_key(Vhost, Name) ->
  iolist_to_binary(string:join(["queue", binary_to_list(Vhost), binary_to_list(Name)], ".")).

get_username(Args) ->
  case lists:keysearch(<<"username">>, 1, Args) of
    {value, Tuple} ->
      {_, _, Username} = Tuple;
    false ->
      Username = get_env(default_username, <<"guest">>)
  end,
  Username.

get_virtual_hosts() ->
  rabbit_vhost:list().

graphite__overview_key(Exchange, Key) ->
  string:join([?PREFIX, "overview", Exchange#rabbitmq_pulse_exchange.cluster, Key], ".").

has_exchange(Connection, Exchange) ->
  lists:member(Exchange, Connection#rabbitmq_pulse_connection.exchanges).

pair_up([A, B, C, D, E | Tail]) when is_atom(A), is_atom(B), is_atom(C), is_atom(D), is_number(E) ->
  [{string:join([atom_to_list(A), atom_to_list(B), atom_to_list(C), atom_to_list(D)], "."), E} | pair_up(Tail)];

pair_up([A, B, C, D | Tail]) when is_atom(A), is_atom(B), is_atom(C), is_number(D) ->
  [{string:join([atom_to_list(A), atom_to_list(B), atom_to_list(C)], "."), D} | pair_up(Tail)];

pair_up([A, B, C | Tail]) when is_atom(A), is_atom(B), is_number(C) ->
  [{string:join([atom_to_list(A), atom_to_list(B)], "."), C} | pair_up(Tail)];

pair_up([A, B | Tail]) when is_atom(A), is_number(B) ->
  [{atom_to_list(A), B} | pair_up(Tail)];

pair_up([]) ->
  [].

pulse_exchanges() ->
  Exchanges = [remapped_exchange(X) || X  <- get_all_exchanges(), filter_pulse_exchange(X) =/= null],
  add_startup_bindings(Exchanges).

remapped_bindings(Bindings) ->
  [binding_exchange_and_routing_key(B) || B <- Bindings].

remapped_exchange(Exchange) ->
  {exchange,{resource, VirtualHost, exchange, Name}, 'x-pulse', _, _, _, Args, _, _} = Exchange,
  Remapped = #rabbitmq_pulse_exchange{virtual_host=VirtualHost,
                                      username=get_username(Args),
                                      exchange=Name,
                                      interval=get_interval(Args),
                                      format=get_format(Args),
                                      cluster=get_cluster_name(Args),
                                      bindings=[]},
  Remapped.

remapped_queue(Q) ->
  list_to_tuple([rabbitmq_queue_full |[proplists:get_value(X, Q) || X <- record_info(fields, rabbitmq_queue_full)]]).

remove_binding_from_exchange(Exchange, Source, RoutingKey) when Exchange#rabbitmq_pulse_exchange.exchange =:= Source ->
  #rabbitmq_pulse_exchange{virtual_host=Exchange#rabbitmq_pulse_exchange.virtual_host,
                           username=Exchange#rabbitmq_pulse_exchange.username,
                           exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                           interval=Exchange#rabbitmq_pulse_exchange.interval,
                           format=Exchange#rabbitmq_pulse_exchange.format,
                           cluster=Exchange#rabbitmq_pulse_exchange.cluster,
                           bindings=[Binding || Binding <- Exchange#rabbitmq_pulse_exchange.bindings, Binding =/= RoutingKey]};

remove_binding_from_exchange(Exchange, _, _) ->
  Exchange.

remove_binding(Exchanges, {binding, {resource, _, exchange, Source}, RoutingKey, {resource,_,queue, _},_}) ->
  [remove_binding_from_exchange(X, Source, RoutingKey) || X <- Exchanges].

remove_bindings(Exchanges, Bindings) ->
  [Xs] = [remove_binding(Exchanges, Binding) || Binding <- Bindings],
  Xs.

routing_key_match({BT, BN, BH}, {NT, NN, NH}) when BT =:= NT, BN =:= NN, BH =:= NH ->
  true;
routing_key_match({BT, BN, BH}, {_NT, NN, NH}) when BT =:= "*", BN =:= NN, BH =:= NH ->
  true;
routing_key_match({BT, BN, BH}, {NT, _NN, NH}) when BT =:= NT, BN =:= "*", BH =:= NH ->
  true;
routing_key_match({BT, BN, BH}, {NT, NN, _NH}) when BT =:= NT, BN =:= NN, BH =:= "*" ->
  true;
routing_key_match({BT, BN, BH}, {NT, NN, _NH}) when BT =:= NT, BN =:= NN, BH =:= "#" ->
  true;
routing_key_match({BT, BN, BH}, {_NT, _NN, NH}) when BT =:= "*", BN =:= "*", BH =:= NH ->
  true;
routing_key_match({BT, BN, BH}, {NT, _NN, _NH}) when BT =:= NT, BN =:= "*", BH =:= "*" ->
  true;
routing_key_match({BT, BN, BH}, {NT, NN, _NH}) when BT =:= NT, BN =:= NN, BH =:= "#" ->
  true;
routing_key_match({BT, BN}, {NT, _NN, _NH}) when BT =:= NT, BN =:= "#" ->
  true;
routing_key_match({BT}, {_NT, _NN, _NH}) when BT =:= "#" ->
  true;
routing_key_match(BT, {_NT, _NN, _NH}) when BT =:= "#" ->
  true;
routing_key_match(_, _) ->
  false.

%% Connection and AMQP specific functions

add_exchange(Connection, Exchanges) ->
  [add_exchange_to_connection(Connection, Exchange) || Exchange <- Exchanges].

add_exchange_to_connection(Connection, Exchange) when Connection#rabbitmq_pulse_connection.virtual_host =:= Exchange#rabbitmq_pulse_exchange.virtual_host,
  Connection#rabbitmq_pulse_connection.username =:= Exchange#rabbitmq_pulse_exchange.username ->
  #rabbitmq_pulse_connection{connection=Connection#rabbitmq_pulse_connection.connection,
                             channel=Connection#rabbitmq_pulse_connection.channel,
                             virtual_host=Connection#rabbitmq_pulse_connection.virtual_host,
                             username=Connection#rabbitmq_pulse_connection.username,
                             exchanges=lists:append(Connection#rabbitmq_pulse_connection.exchanges, [Exchange#rabbitmq_pulse_exchange.exchange])};

add_exchange_to_connection(_, _) ->
  null.

establish_connections(Exchanges) ->
  [Connections] = [add_exchange(open(VirtualHost, Username), Exchanges) || {VirtualHost, Username} <- distinct_vhost_pairs(Exchanges)],
  Connections.

open(VirtualHost, Username) ->
  AdapterInfo = #amqp_adapter_info{name = <<"rabbitmq_pulse">>},
  case amqp_connection:start(#amqp_params_direct{username = Username,
                                                 virtual_host = VirtualHost,
                                                 adapter_info = AdapterInfo}) of
    {ok, Connection} ->
      case amqp_connection:open_channel(Connection) of
        {ok, Channel}  ->
          #rabbitmq_pulse_connection{virtual_host=VirtualHost, username=Username, connection=Connection, channel=Channel, exchanges=[]};
        E              ->
          catch amqp_connection:close(Connection),
          rabbit_log:warning("Error connecting to virtual host ~s as ~n: ~p~n", [VirtualHost, Username, E]),
          E
      end;
    E                ->
      E
  end.

publish_graphite_message(Channel, Exchange, Key, ValueString, Type) ->
  Epoch = current_timestamp(),
  [Timestamp] = io_lib:format("~p", [Epoch]),
  [Value] = io_lib:format("~p", [ValueString]),
  BasicPublish = #'basic.publish'{exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                                  routing_key=list_to_bitstring(Key)},
  Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                          content_type = <<"application/json">>,
                          delivery_mode = 1,
                          timestamp = Epoch,
                          type = Type},
  Message = list_to_bitstring(string:join([Key, Value, Timestamp], " ")),
  Content = #amqp_msg{props = Properties, payload = Message},
  amqp_channel:call(Channel, BasicPublish, Content).

publish_json_message(Channel, Exchange, RoutingKey, Message, Type) ->
  BasicPublish = #'basic.publish'{exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                                  routing_key=RoutingKey},
  Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                          content_type = <<"application/json">>,
                          delivery_mode = 1,
                          timestamp = current_timestamp(),
                          type = Type},
  Content = #amqp_msg{props = Properties, payload = Message},
  amqp_channel:call(Channel, BasicPublish, Content).

%% Poll functions

build_stats_message(Node) ->
  Values = [{Key, Value} || {Key, Value} <- Node, not lists:member(Key, ?IGNORE_KEYS)],
  iolist_to_binary(mochijson2:encode(Values)).

node_stats(Node) ->
  {get_node_routing_key(Node), build_stats_message(Node)}.

queue_stats(Vhost, Name, Q) ->
  {get_queue_routing_key(Vhost, Name), build_stats_message(Q)}.

process_binding_overview(Exchange, Channel) ->
  case length([true || Binding <- Exchange#rabbitmq_pulse_exchange.bindings, lists:member(Binding, ?OVERVIEW_BINDINGS)]) of
    0 ->
      ok;
    _ ->
      process_overview(Exchange, Channel),
      ok
  end.

process_interval(ExchangeName, Exchanges, Connections) ->
  [Exchange] = [Exchange || Exchange <- Exchanges, Exchange#rabbitmq_pulse_exchange.exchange =:= ExchangeName],
  Channel = get_channel(Exchange#rabbitmq_pulse_exchange.exchange, Connections),
  process_binding_overview(Exchange, Channel),
  [process_node(Channel, Exchange, N) || N <- rabbit_mgmt_wm_nodes:all_nodes()],
  [process_queue(Channel, Exchange, Q) || Q <- get_queues()],
  Exchange.

process_node(Channel, Exchange, Node) when Exchange#rabbitmq_pulse_exchange.format =:= json ->
  case should_publish_node_stats(Exchange, Node) of
    true ->
      {RoutingKey, Message} = node_stats(Node),
      publish_json_message(Channel, Exchange, RoutingKey, Message, ?NODE_TYPE),
      ok;
    false ->
      ok
  end.

process_overview(Exchange, Channel) when Exchange#rabbitmq_pulse_exchange.format =:= graphite ->
  Overview = rabbit_mgmt_db:get_overview(),
  Pairs = get_kvp(Overview),
  [publish_graphite_message(Channel, Exchange, graphite__overview_key(Exchange, Key), Value, ?GRAPHITE_OVERVIEW_TYPE) || {Key, Value} <- Pairs],
  ok;

process_overview(Exchange, Channel) when Exchange#rabbitmq_pulse_exchange.format =:= json ->
  Overview = rabbit_mgmt_db:get_overview(),
  publish_json_message(Channel, Exchange, <<"overview">>, iolist_to_binary(mochijson2:encode(Overview)), ?OVERVIEW_TYPE),
  ok.

process_queue(Channel, Exchange, Q) when Exchange#rabbitmq_pulse_exchange.format =:= json ->
  Queue = remapped_queue(Q),
  case should_publish_queue_stats(Exchange, Queue) of
    true ->
      {RoutingKey, Message} = queue_stats(Queue#rabbitmq_queue_full.vhost, Queue#rabbitmq_queue_full.name, Q),
      publish_json_message(Channel, Exchange, RoutingKey, Message, ?QUEUE_TYPE),
      ok
  end.

should_publish_node_stats(Exchange, Node) ->
  NodeTuple = get_node_routing_key_tuple(get_node_name(Node)),
  lists:any(fun (V) -> V =:= true end,
            [routing_key_match(get_binding_tuple(Binding), NodeTuple) || Binding <- Exchange#rabbitmq_pulse_exchange.bindings]).

should_publish_queue_stats(Exchange, Queue) ->
  QueueTuple = {"queue", binary_to_list(Queue#rabbitmq_queue_full.vhost), binary_to_list(Queue#rabbitmq_queue_full.name)},
  lists:any(fun (V) -> V =:= true end,
            [routing_key_match(get_binding_tuple(Binding), QueueTuple) || Binding <- Exchange#rabbitmq_pulse_exchange.bindings]).
