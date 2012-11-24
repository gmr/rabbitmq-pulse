%%
%% RabbitMQ Pulse Worker Records
%%
-record(rabbitmq_pulse_connection, {virtual_host, username, connection, channel, exchanges}).
-record(rabbitmq_pulse_exchange, {virtual_host, username, exchange, interval, bindings, format, cluster}).
-record(rabbitmq_pulse_state, {connections, exchanges}).
-record(rabbitmq_queue_full, {memory, idle_since, policy, exclusive_consumer_pid, exclusive_consumer_tag, messages_ready,
                              messages_unacknowledged, messages, consumers, active_consumers, slave_pids,
                              synchronised_slave_pids, backing_queue_status, messages_details, messages_ready_details,
                              messages_unacknowledged_details, incoming, consumer_details, name, vhost, durable,
                              auto_delete, owner_pid, arguments, pid}).
