-module(rabbitmq_pulse_worker).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([declare_exchange/1, handle_interval/0, process_interval/2, start_timer/1]).

-include_lib("amqp_client/include/amqp_client.hrl").

-record(state, {channel, exchange, interval}).

-define(IGNORE_KEYS, [applications, auth_mechanisms, erlang_version, exchange_types, processors, statistics_level]).

start_link() ->
    gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).

%---------------------------
% Gen Server Implementation
% --------------------------

init([]) ->
    {ok, Interval} = application:get_env(rabbitmq_pulse, interval),
    rabbit_log:info("Pulse interval: ~p~n", [Interval]),
    case open() of
        {ok, _, Channel} ->
            Exchange = declare_exchange(Channel),
            start_timer(Interval),
            {ok, #state{channel = Channel, exchange= Exchange, interval = Interval}};
        E ->
            {stop, E}
    end.

handle_call(_Msg, _From, State) ->
    {reply, unknown_command, State}.

handle_cast(handle_interval, State = #state{channel = Channel, exchange = Exchange, interval = Interval}) ->
    process_interval(Channel, Exchange),
    start_timer(Interval),
    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_, #state{channel = Channel}) ->
    amqp_channel:call(Channel, #'channel.close'{}),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%---------------------------

build_stats_message(Node) ->
    Values = [{Key, Value} || {Key, Value} <- Node, not lists:member(Key, ?IGNORE_KEYS)],
    iolist_to_binary(mochijson2:encode(Values)).

convert_gregorian_to_julian(GregorianSeconds) ->
    GregorianSeconds - 719528 * 24 * 3600.

current_gregorian_timestamp() ->
    calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time(now())).

current_timestamp() ->
    convert_gregorian_to_julian(current_gregorian_timestamp()).

declare_exchange(Channel) ->
    {ok, Exchange} = application:get_env(rabbitmq_pulse, exchange),
    amqp_channel:call(Channel, #'exchange.declare'{exchange = Exchange,
                                                   durable = true,
                                                   type = <<"topic">>}),
    Exchange.

get_routing_key(Type, Node) ->
    {name, Name} = lists:nth(1, Node),
    [_, Host] = string:tokens(atom_to_list(Name), "@"),
    iolist_to_binary(string:join([Type, Host], ".")).

handle_interval() ->
    gen_server:cast({global, ?MODULE}, handle_interval).

node_stats(Node) ->
    {get_routing_key("node", Node), build_stats_message(Node)}.

open() ->
    AdapterInfo = #adapter_info{name = <<"rabbitmq_pulse">>},
    {ok, Username} = application:get_env(rabbitmq_pulse, username),
    {ok, VirtualHost} = application:get_env(rabbitmq_pulse, virtual_host),
    case amqp_connection:start(#amqp_params_direct{username = Username,
                                                   virtual_host = VirtualHost,
                                                   adapter_info = AdapterInfo}) of
        {ok, Connection} ->
            case amqp_connection:open_channel(Connection) of
                {ok, Channel} ->
                    rabbit_log:info("rabbitmq_pulse plugin started~n"),
                    {ok, Connection, Channel};
                E             ->
                    catch amqp_connection:close(Connection),
                    rabbit_log:warning("error starting rabbitmq_pulse plugin: ~s~n", E),
                    E
            end;
        E -> E
    end.

publish_message(Channel, Exchange, RoutingKey, Message, Type) ->
    BasicPublish = #'basic.publish'{exchange = Exchange, routing_key = RoutingKey},
    Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                            content_type = <<"application/json">>,
                            delivery_mode = 1,
                            timestamp = current_timestamp(),
                            type = Type},
    Content = #amqp_msg{props = Properties, payload = Message},
    amqp_channel:call(Channel, BasicPublish, Content).

process_node(Channel, Exchange, [Node]) ->
    {RoutingKey, Message} = node_stats(Node),
    publish_message(Channel, Exchange, RoutingKey, Message, <<"rabbitmq node stats">>).

process_interval(Channel, Exchange) ->
    Nodes = rabbit_mgmt_wm_nodes:all_nodes(),
    process_node(Channel, Exchange, Nodes).

start_timer(Duration) ->
    timer:apply_after(Duration, ?MODULE, handle_interval, []).
