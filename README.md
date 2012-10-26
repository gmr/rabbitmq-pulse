rabbitmq-pulse
==============
rabbitmq-pulse is an *experimental* plugin that publishes information made available by the rabbitmq-management plugin
making cluster monitoring a push event instead of something you poll for.

Overview
--------
The rabbitmq-pulse plugin will publish cluster, node and queue statistics to a topic exchange with varying routing keys to
 allow for stats at multiple layers of granularity.

The messages are JSON serialized data provided by the rabbitmq-management plugin.

Message Types
-------------
- cluster overview: High-level cluster overview data
- node stats: Per-node messages
- queue stats: Per-queue messages

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

Examples
--------

_Cluster Overview Message_

The following is an example cluster overview message:

    Exchange:          rabbitmq-pulse
    Routing Key:       overview

    Properties

        app_id:        rabbitmq-pulse
        content_type:  application/json
        delivery_mode: 1
        timestamp:     1351221662
        type:          rabbitmq cluster overview

    Message:

        {
            "message_stats": {
                "ack": 61828830,
                "ack_details": {
                    "interval": 13691029994,
                    "last_event": 1351225207219,
                    "rate": 1657.4946825255636
                },
                "confirm": 587185321,
                "confirm_details": {
                    "interval": 14440907038,
                    "last_event": 1351225202580,
                    "rate": 940.2572840257346
                },
                "deliver": 61829392,
                "deliver_details": {
                    "interval": 13691029994,
                    "last_event": 1351225207219,
                    "rate": 1655.3086640878523
                },
                "deliver_get": 61829392,
                "deliver_get_details": {
                    "interval": 13691029994,
                    "last_event": 1351225207219,
                    "rate": 1655.3086640878523
                },
                "publish": 1194850838,
                "publish_details": {
                    "interval": 514892992009,
                    "last_event": 1351225207219,
                    "rate": 1748.604888221129
                },
                "redeliver": 3566,
                "redeliver_details": {
                    "interval": 13691029994,
                    "last_event": 1351225207219,
                    "rate": 0.5793280232749254
                }
            },
            "queue_totals": {
                "messages": 37014,
                "messages_details": {
                    "interval": 118795693987,
                    "last_event": 1351225206950,
                    "rate": 138.75356292893883
                },
                "messages_ready": 36410,
                "messages_ready_details": {
                    "interval": 118795693987,
                    "last_event": 1351225206950,
                    "rate": 113.47632183168328
                },
                "messages_unacknowledged": 604,
                "messages_unacknowledged_details": {
                    "interval": 118795693987,
                    "last_event": 1351225206950,
                    "rate": 25.277241097255544
                }
            }
        }



_Node Message_

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
