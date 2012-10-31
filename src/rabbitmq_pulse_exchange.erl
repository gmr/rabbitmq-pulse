-module(rabbitmq_pulse_exchange).
-author("gmr@meetme.com").

-include_lib("rabbit_common/include/rabbit.hrl").

-define(EXCHANGE_TYPE_BIN, <<"x-pulse">>).
-define(TYPE,              <<"type-module">>).

-behaviour(rabbit_exchange_type).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type x-pulse"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, ?EXCHANGE_TYPE_BIN, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

-export([
    add_binding/3,
    assert_args_equivalence/2,
    create/2,
    delete/3,
    policy_changed/3,
    description/0,
    remove_bindings/3,
    route/2,
    serialise_events/0,
    validate/1
]).

add_binding(Tx, X, B) ->
  gen_server:cast(rabbitmq_pulse, {add_binding, Tx, X, B}),
  rabbit_exchange_type_topic:add_binding(Tx, X, B).

assert_args_equivalence(X, Args) ->
  rabbit_exchange:assert_args_equivalence(X, Args).

create(transaction, X) ->
  gen_server:cast(rabbitmq_pulse, {create, X}),
  ok;
create(none, _X) ->
  ok.

delete(transaction, X, _Bs) ->
  gen_server:cast(rabbitmq_pulse, {delete, X, _Bs}),
  ok;
delete(none, _X, _Bs) ->
  ok.

exchange_type(#exchange{arguments=Args}) ->
  case lists:keyfind(?TYPE, 1, Args) of
    {?TYPE, _, Type} ->
      case list_to_atom(binary_to_list(Type)) of
        rabbitmq_pulse_exchange ->
          error_logger:error_report("Cannot bind a Pulse exchange to a Pulse exchange"),
          rabbit_exchange_type_topic;
        Else -> Else
      end;
    _ -> rabbit_exchange_type_topic
  end.


description() ->
  [{name, ?EXCHANGE_TYPE_BIN},
   {description, <<"Experimental RabbitMQ-Pulse stats exchange">>}].

policy_changed(_Tx, _X1, _X2) ->
  gen_server:cast(rabbitmq_pulse, {policy_changed, _X1, _X2}),
  ok.

remove_bindings(Tx, X, Bs) ->
  gen_server:cast(rabbitmq_pulse, {remove_bindings, Tx, X, Bs}),
  rabbit_exchange_type_topic:remove_bindings(Tx, X, Bs).

route(_Exchange, _Delivery) ->
  [].

serialise_events() ->
  false.

validate(X) ->
  Exchange = exchange_type(X),
  Exchange:validate(X).



