-module(rabbitmq_pulse_worker).
-behaviour(gen_server).

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
terminate/2, code_change/3]).

-export([fire/0, get_rabbit_nodes/0, gregorian_timestamp/0, gregorian_to_julian/1,
         process_node/3, publish_stats/4, routing_key/1, start_timer/1, timestamp/0]).

-include_lib("amqp_client/include/amqp_client.hrl").

-record(state, {channel, exchange, interval}).




start_link() ->
    gen_server:start_link({global, ?MODULE}, ?MODULE, [], []).

%---------------------------
% Gen Server Implementation
% --------------------------

init([]) ->
    {ok, Interval} = application:get_env(rabbitmq_pulse, interval),
    rabbit_log:info("Pulse interval: ~p~n", [Interval]),
    case open() of
        {ok, Connection, Channel} ->
            {ok, Exchange} = application:get_env(rabbitmq_pulse, exchange),
            amqp_channel:call(Channel, #'exchange.declare'{exchange = Exchange, type = <<"topic">>}),
            start_timer(Interval),
            {ok, #state{channel = Channel, exchange= Exchange, interval = Interval}};
        E ->
            {stop, E}
    end.


handle_call(_Msg, _From, State) ->
    {reply, unknown_command, State}.


handle_cast(fire, State = #state{channel = Channel, exchange = Exchange, interval = Interval}) ->
    process_node(Channel, Exchange, get_rabbit_nodes()),
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

fire() ->
    gen_server:cast({global, ?MODULE}, fire).


get_rabbit_nodes() ->
    [{nodes, Nodes}, {running_nodes, RunningNodes}] = rabbit_mnesia:status(),
    RunningNodes.


gregorian_to_julian(GregorianSeconds) ->
    GregorianSeconds - 719528 * 24 * 3600.


gregorian_timestamp() ->
    calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time(now())).


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


process_node(Channel, Exchange, [Node]) ->
    Name = node_name(Node),
    {_, Message} = json:encode([list_to_binary(Name), <<"stats">>]),
    RoutingKey = routing_key(Name),
    publish_stats(Channel, Exchange, RoutingKey, Message).


publish_stats(Channel, Exchange, RoutingKey, Message) ->
    BasicPublish = #'basic.publish'{exchange = Exchange, routing_key = list_to_binary(RoutingKey)},
    Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                            content_type = <<"application/json">>,
                            delivery_mode = 1,
                            timestamp = timestamp(),
                            type = <<"rabbitmq node stats">>},
    Content = #amqp_msg{props = Properties, payload = Message},
    amqp_channel:call(Channel, BasicPublish, Content).

node_name(Node) ->
    atom_to_list(Node).

routing_key(Node) ->
    [NodeName, RoutingKey] =  string:tokens(Node, "@"),
    string:join(["stats", NodeName, RoutingKey], ".").


start_timer(Duration) ->
    timer:apply_after(Duration, ?MODULE, fire, []).


timestamp() ->
      gregorian_to_julian(gregorian_timestamp()).
