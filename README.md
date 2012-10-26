rabbitmq-pulse
==============
rabbitmq-pulse is an *experimental* plugin that publishes information made available by the rabbitmq-management plugin
making cluster monitoring a push event instead of something you poll for.

Overview
--------
The rabbitmq-pulse plugin will publish node statistics to a topic exchange with a routing key of node.[hostname]. The
message is a JSON serialized payload of data provided by the rabbitmq-management plugin.

Installation
------------
Currently, the best way to install the plugin is to follow the instructions at http://www.rabbitmq.com/plugin-development.html and
setup the rabbitmq-public-umbrella checkout, clone the rabbitmq-pulse directory into it and custom compile the plugin.

Configuration
-------------
Default configuration values:

- username: guest
- virtual_host: /
- exchange: rabbitmq-pulse
- interval: 5000

Interval is the number of miliseconds between publishing stats. To change the default configuration values, add a
rabbitmq_pulse stanza in the rabbitmq.config file for the value you would like to override:

    [{rabbitmq_config, [{username, <<"guest">>},
                        {virtual_host, <<"/">>},
                        {exchange, <<"rabbitmq-pulse">>},
                        {interval, 5000}]}]

Example Node Message
--------------------
The following is an example stats message for a node:

    Exchange:          rabbitmq-pulse
    Routing Key:       node.localhost

    Properties

        app_id:        rabbitmq-pulse
        content_type:  application/json
        delivery_mode: 1
        timestamp:     1351221662
        type:          rabbitmq node stats

    Message:

        {
            "name": "rabbit@localhost",
            "os_pid": "7499",
            "type": "disc",
            "running": true,
            "disk_free": 169206083584,
            "disk_free_alarm": false,
            "disk_free_limit": 1000000000,
            "fd_total": 1024,
            "fd_used": 28,
            "mem_alarm": false,
            "mem_atom": 703377,
            "mem_atom_used": 677667,
            "mem_binary": 150264,
            "mem_code": 18406789,
            "mem_ets": 1499064,
            "mem_limit": 5647935078,
            "mem_proc": 12891074,
            "mem_proc_used": 13038914,
            "mem_used": 38600528,
            "proc_total": 1048576,
            "proc_used": 228,
            "run_queue": 0,
            "sockets_total": 829,
            "sockets_used": 1,
            "uptime": 6092
        }
