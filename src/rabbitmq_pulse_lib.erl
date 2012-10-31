-module(rabbitmq_pulse_lib).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbitmq_pulse_worker.hrl").

-export([establish_connections/1,
         get_bindings/1,
         pulse_exchanges/0,
         publish_message/5]).

-define(DEFAULT_INTERVAL, 5000).

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
      get_env(interval, ?DEFAULT_INTERVAL)
  end.

get_username(Args) ->
  case lists:keysearch(<<"username">>, 1, Args) of
    {value, Tuple} ->
      {_, _, Username} = Tuple;
    false ->
      Username = get_env(username, <<"guest">>)
  end,
  Username.

remapped_exchange(Exchange) ->
  {exchange,{resource, VirtualHost, exchange, Name}, 'x-pulse', _, _, _, Args, _} = Exchange,
  Remapped = #rabbitmq_pulse_exchange{virtual_host=VirtualHost, username=get_username(Args),
                                      exchange=Name, interval=get_interval(Args), bindings=[]},
  Remapped.


binding_exchange_and_routing_key([{source_name, Exchange},{source_kind,exchange},{destination_name,_},{destination_kind,queue},{routing_key,RoutingKey},{arguments,_}]) ->
  {Exchange, RoutingKey}.

remapped_bindings(Bindings) ->
  [binding_exchange_and_routing_key(B) || B <- Bindings].

filter_bindings(Exchange, Bindings) ->
  lists:flatten([RoutingKey ||  {BindingExchange, RoutingKey}  <- remapped_bindings(Bindings), BindingExchange =:= Exchange]).

filter_pulse_exchange(Exchange={exchange,{resource, _, exchange, _}, 'x-pulse', _, _, _, _, _}) ->
  Exchange;

filter_pulse_exchange({exchange,{resource, _, exchange, _}, _, _, _, _, _, _}) ->
  null.

get_bindings(Exchange) ->
  filter_bindings(Exchange#rabbitmq_pulse_exchange.exchange,
                  rabbit_binding:info_all(Exchange#rabbitmq_pulse_exchange.virtual_host)).

add_binding(Exchange) ->
  #rabbitmq_pulse_exchange{virtual_host=Exchange#rabbitmq_pulse_exchange.virtual_host,
                           username=Exchange#rabbitmq_pulse_exchange.username,
                           exchange=Exchange#rabbitmq_pulse_exchange.exchange,
                           interval=Exchange#rabbitmq_pulse_exchange.interval,
                           bindings=get_bindings(Exchange)}.

add_bindings(Exchanges) ->
  [add_binding(Exchange) || Exchange <- Exchanges].

get_virtual_hosts() ->
  rabbit_vhost:list().

get_exchanges([VirtualHost]) ->
  rabbit_exchange:list(VirtualHost).

get_all_exchanges() ->
  VirtualHosts = get_virtual_hosts(),
  get_exchanges(VirtualHosts).

pulse_exchanges() ->
  Exchanges = [remapped_exchange(X) || X  <- get_all_exchanges(), filter_pulse_exchange(X) =/= null],
  add_bindings(Exchanges).

distinct_vhost_pairs(Exchanges) ->
  lists:usort([{X#rabbitmq_pulse_exchange.virtual_host, X#rabbitmq_pulse_exchange.username} || X <- Exchanges]).

%% AMQP specific functions

open(VirtualHost, Username) ->
  rabbit_log:info("Connecting to ~s as ~s~n", [VirtualHost, Username]),
  AdapterInfo = #adapter_info{name = <<"rabbitmq_pulse">>},
  case amqp_connection:start(#amqp_params_direct{username = Username,
                                                 virtual_host = VirtualHost,
                                                 adapter_info = AdapterInfo}) of
    {ok, Connection} ->
      case amqp_connection:open_channel(Connection) of
        {ok, Channel}  ->
          rabbit_log:info("Connection to virtual host ~s opened as ~s~n", [VirtualHost, Username]),
          {ok, Connection, Channel};
        E              ->
          catch amqp_connection:close(Connection),
          rabbit_log:warning("Error connecting to virtual host ~s as ~n: ~p~n", [VirtualHost, Username, E]),
          E
      end;
    E                ->
      E
  end.

publish_message(Channel, Exchange, RoutingKey, Message, Type) ->
  BasicPublish = #'basic.publish'{exchange=Exchange, routing_key=RoutingKey},
  Properties = #'P_basic'{app_id = <<"rabbitmq-pulse">>,
                          content_type = <<"application/json">>,
                          delivery_mode = 1,
                          timestamp = current_timestamp(),
                          type = Type},
  Content = #amqp_msg{props = Properties, payload = Message},
  amqp_channel:call(Channel, BasicPublish, Content).

establish_connections(Exchanges) ->
  [open(VirtualHost, Username) || {VirtualHost, Username} <- distinct_vhost_pairs(Exchanges)].
