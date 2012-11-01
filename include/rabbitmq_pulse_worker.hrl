%%
%% RabbitMQ Pulse Worker Records
%%
-record(rabbitmq_pulse_connection, {virtual_host, username, connection, channel, exchanges}).
-record(rabbitmq_pulse_exchange, {virtual_host, username, exchange, interval, bindings, format, cluster}).
-record(rabbitmq_pulse_state, {connections, exchanges}).
