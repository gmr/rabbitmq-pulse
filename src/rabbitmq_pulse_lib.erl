-module(rabbitmq_pulse_lib).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbitmq_pulse_worker.hrl").

-export([establish_connections/1,
         process_interval/3,
         pulse_exchanges/0,
         routing_key_match/2]).

-define(PREFIX, "rabbitmq_pulse").
-define(DEFAULT_INTERVAL, 5000).
-define(IGNORE_KEYS, [applications, auth_mechanisms, erlang_version, exchange_types, processors, statistics_level]).
-define(OVERVIEW_BINDINGS, [<<"#">>, <<"overview">>]).

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

add_binding(Exchange) ->
  #rabbitmq_pulse_exchange{virtual_host=Exchange#rabbitmq_pulse_exchange.virtual_host,
                           username=Exchange#rabbitmq_pulse_exchange.username,
                           exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                           interval=Exchange#rabbitmq_pulse_exchange.interval,
                           format=Exchange#rabbitmq_pulse_exchange.format,
                           cluster=Exchange#rabbitmq_pulse_exchange.cluster,
                           bindings=get_bindings(Exchange)}.

add_bindings(Exchanges) ->
  [add_binding(Exchange) || Exchange <- Exchanges].

binding_exchange_and_routing_key([{source_name, Exchange},{source_kind,exchange},{destination_name,_},{destination_kind,queue},{routing_key,RoutingKey},{arguments,_}]) ->
  {Exchange, RoutingKey}.

distinct_vhost_pairs(Exchanges) ->
  lists:usort([{X#rabbitmq_pulse_exchange.virtual_host, X#rabbitmq_pulse_exchange.username} || X <- Exchanges]).

filter_bindings(Exchange, Bindings) ->
  lists:flatten([RoutingKey ||  {BindingExchange, RoutingKey}  <- remapped_bindings(Bindings), BindingExchange =:= Exchange]).

filter_pulse_exchange(Exchange={exchange,{resource, _, exchange, _}, 'x-pulse', _, _, _, _, _}) ->
  Exchange;

filter_pulse_exchange({exchange,{resource, _, exchange, _}, _, _, _, _, _, _}) ->
  null.

find_connection(Exchange, Connections)->
  [Connection] = [C || C <- Connections, has_exchange(C, Exchange)],
  Connection.

flatten(A, B, Subitem) when is_list(Subitem) ->
  lists:flatten([[A,B,C,D] || {C, D} <- Subitem]);

flatten(A, B, Subitem) when is_number(Subitem) ->
  lists:flatten([A,B,Subitem]).

get_all_exchanges() ->
  VirtualHosts = get_virtual_hosts(),
  get_exchanges(VirtualHosts).

get_bindings(Exchange) ->
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
  {name, Name}= lists:nth(1, Node),
  atom_to_list(Name).

get_routing_key_tuple(Type, Value) ->
  list_to_tuple(lists:merge([Type], string:tokens(Value, "@"))).

get_routing_key(Type, Node) ->
  Value = tuple_to_list(get_routing_key_tuple(Type, get_node_name(Node))),
  iolist_to_binary(string:join(Value, ".")).

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
  add_bindings(Exchanges).

remapped_bindings(Bindings) ->
  [binding_exchange_and_routing_key(B) || B <- Bindings].

remapped_exchange(Exchange) ->
  {exchange,{resource, VirtualHost, exchange, Name}, 'x-pulse', _, _, _, Args, _} = Exchange,
  Remapped = #rabbitmq_pulse_exchange{virtual_host=VirtualHost,
                                      username=get_username(Args),
                                      exchange=Name,
                                      interval=get_interval(Args),
                                      format=get_format(Args),
                                      cluster=get_cluster_name(Args),
                                      bindings=[]},
  Remapped.

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
routing_key_match(BT, {_NT, _NN, _NH}) when BT =:= "#" ->
  true;
routing_key_match({BT, BN}, {NT, _NN, _NH}) when BT =:= NT, BN =:= "#" ->
  true;
routing_key_match({BT, BN, BH}, {NT, NN, _NH}) when BT =:= NT, BN =:= NN, BH =:= "#" ->
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
  [add_exchange(open(VirtualHost, Username), Exchanges) || {VirtualHost, Username} <- distinct_vhost_pairs(Exchanges)].


open(VirtualHost, Username) ->
  AdapterInfo = #adapter_info{name = <<"rabbitmq_pulse">>},
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

publish_graphite_message(Channel, Exchange, Key, ValueString) ->
  Epoch = current_timestamp(),
  [Timestamp] = io_lib:format("~p", [Epoch]),
  [Value] = io_lib:format("~p", [ValueString]),
  FullKey = string:join([?PREFIX, "overview", Exchange#rabbitmq_pulse_exchange.cluster, Key], "."),
  BasicPublish = #'basic.publish'{exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                                  routing_key=list_to_bitstring(FullKey)},
  Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                          content_type = <<"application/json">>,
                          delivery_mode = 1,
                          timestamp = Epoch,
                          type = <<"rabbitmq-pulse cluster overview graphite datapoint">>},
  Message = list_to_bitstring(string:join([FullKey, Value, Timestamp], " ")),
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
  {get_routing_key("node", Node), build_stats_message(Node)}.

process_binding_overview(Exchange, Channel) ->
  case length([true || Binding <- Exchange#rabbitmq_pulse_exchange.bindings, lists:member(Binding, ?OVERVIEW_BINDINGS)]) of
    0 ->
      ok;
    _ ->
      process_overview(Exchange, Channel),
      ok
  end.

process_exchange_bindings(Exchange, Channel) ->
  process_binding_overview(Exchange, Channel),
  %Nodes = rabbit_mgmt_wm_nodes:all_nodes(),
  %process_node(Channel, Exchange, Nodes),
  Queues = rabbit_amqqueue:list().

process_interval(ExchangeName, Exchanges, [Connections]) ->
  [Exchange] = [Exchange || Exchange <- Exchanges, Exchange#rabbitmq_pulse_exchange.exchange =:= ExchangeName],
  Channel = get_channel(Exchange#rabbitmq_pulse_exchange.exchange, Connections),
  process_exchange_bindings(Exchange, Channel),
  Exchange.

process_node(Channel, Exchange, [Node]) when Exchange#rabbitmq_pulse_exchange.format =:= json ->
  case should_publish_node_stats(Exchange, Node) of
    true ->
      {RoutingKey, Message} = node_stats(Node),
      publish_json_message(Channel, Exchange, RoutingKey, Message, <<"rabbitmq node stats">>),
      ok;
    false ->
      ok
  end.

process_overview(Exchange, Channel) when Exchange#rabbitmq_pulse_exchange.format =:= graphite ->
  Overview = rabbit_mgmt_db:get_overview(),
  Pairs = get_kvp(Overview),
  [publish_graphite_message(Channel, Exchange, Key, Value) || {Key, Value} <- Pairs];

process_overview(Exchange, Channel) when Exchange#rabbitmq_pulse_exchange.format =:= json ->
  rabbit_log:info("processing json~n"),
  Overview = rabbit_mgmt_db:get_overview(),
  publish_json_message(Channel, Exchange, <<"overview">>, iolist_to_binary(mochijson2:encode(Overview)), <<"rabbitmq cluster overview">>).

%process_queues(Channel, Exchange, [Queue]) ->

should_publish_node_stats(Exchange, Node) ->
  NodeTuple = get_routing_key_tuple("node", get_node_name(Node)),
  lists:any(fun (V) -> V =:= true end,
            [routing_key_match(get_binding_tuple(Binding), NodeTuple) || Binding <- Exchange#rabbitmq_pulse_exchange.bindings]).
