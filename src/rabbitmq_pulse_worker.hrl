%%
%% RabbitMQ Pulse Worker Records
%%
-record(rabbitmq_pulse_connection, {virtual_host}).
-record(rabbitmq_pulse_exchange, {virtual_host, username, exchange, interval, bindings}).
-record(rabbitmq_pulse_state, {connections, exchanges}).
