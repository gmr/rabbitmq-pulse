RabbitMQ Pulse
==============
RabbitMQ Pulse is an *experimental* exchange plugin for **RabbitMQ 3.0+** that publishes information made available by the
rabbitmq-management plugin making cluster monitoring a push event instead of something you poll for.

Messages can be published in JSON format as they would be received from the management API or they can be published
in a format that is compatible with Graphite's carbon AMQP client, providing conversionless integration into Graphite
and systems like rocksteady.

This is a work in progress and is not meant for production systems (yet).

Overview
--------
The *x-pulse* exchange type added by RabbitMQ Pulse creates a publishing exchange that will send status messages at pre-specified
intervals to bound objects matching the routing key patterns it uses.

The rabbitmq-pulse plugin will publish cluster, node and queue statistics to a topic *like* exchange with varying routing keys to
 allow for stats at multiple layers of granularity. For example, to get all stats for a server with a hostname of megabunny,
 you could bind to *.rabbit.megabunny. Or to get node stats for all hosts, you could do node.rabbit.*.  RabbitMQ Pulse uses
 a similar style of routing-key behavior as the topic exchange, but without the partial word matching (ie no node.rab*.*).

The messages are JSON serialized data with stats provided by the rabbitmq-management plugin.

Todo
----
- Add the ability to bind to get stats for:
  - Queues
  - Connections
  - Channels
- Handle shutdown cleanly
- Handle add_binding/remove_binding, create, delete properly

Message Types
-------------
- cluster overview: High-level cluster overview data
- node stats: Per-node messages
- queue stats: Per-queue messages

Installation
------------
Currently, the best way to install the plugin is to follow the instructions at http://www.rabbitmq.com/plugin-development.html and
setup the rabbitmq-public-umbrella checkout, clone the rabbitmq-pulse directory into it and custom compile the plugin.

Plugin Configuration
--------------------
Default configuration values:

- default_username: guest
- default_interval: 5000

Interval is the number of miliseconds between publishing stats. To change the default configuration values, add a
rabbitmq_pulse stanza in the rabbitmq.config file for the value you would like to override:

    [{rabbitmq_pulse, [{default_username, <<"guest">>},
                       {default_interval, 5000},
                       {default_format, <<"json">>]}]

To override the default values, specify a username and/or interval as arguments when delcaring a x-pulse exchange.

Per-exchange optional configuration values
------------------------------------------

- username: Username to connect to the vhost as
- interval: Number of milliseconds between publishing of stats
- format: The publishing format. Acceptable values are json or graphite.


Examples
--------

### Cluster Overview Message (JSON)

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

## Cluster Overview Single Stat Message (Graphite)

    Exchange:      graphite
    Routing Key:   rabbitmq_pulse.overview.rabbit.localhost.message_stats.deliver_details.rate

    Properties:

        app_id:        rabbitmq-pulse
        content_type:  application/json
        delivery_mode: 1
        timestamp:     1351748994
        type:          rabbitmq-pulse cluster overview graphite datapoint

    Message:

        rabbitmq_pulse.overview.rabbit.localhost.message_stats.deliver_details.rate 945.8392531255008 1351748994

### Node Message (JSON)

    Exchange:          rabbitmq-pulse
    Routing Key:       node.rabbit.localhost

    Properties:

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

## Queue Message (JSON)

    Exchange:          rabbitmq-pulse
    Routing Key:       queue./.test_two

    Properties:

        app_id:        rabbitmq-pulse
        content_type:  application/json
        delivery_mode: 1
        timestamp:     1353718351
        type:          rabbitmq queue stats

    Message:

      {
          "policy": "",
          "exclusive_consumer_tag": "",
          "messages_ready": 0,
          "messages_unacknowledged": 0,
          "messages": 0,
          "consumers": 1,
          "active_consumers": 1,
          "memory": 89096,
          "backing_queue_status": {
              "q1": 0,
              "q2": 0,
              "delta": [
                  "delta",
                  "undefined",
                  0,
                  "undefined"
              ],
              "q3": 0,
              "q4": 0,
              "len": 0,
              "pending_acks": 0,
              "target_ram_count": "infinity",
              "ram_msg_count": 0,
              "ram_ack_count": 0,
              "next_seq_id": 25,
              "persistent_count": 0,
              "avg_ingress_rate": 0.19991921264616969,
              "avg_egress_rate": 0.19991921264616969,
              "avg_ack_ingress_rate": 0.19991921264616969,
              "avg_ack_egress_rate": 0.19991921264616969
          },
          "messages_details": {
              "rate": 0,
              "interval": 5002982,
              "last_event": 1353718221808
          },
          "messages_ready_details": {
              "rate": 0,
              "interval": 5002982,
              "last_event": 1353718221808
          },
          "messages_unacknowledged_details": {
              "rate": 0,
              "interval": 5002982,
              "last_event": 1353718221808
          },
          "incoming": [
              {
                  "stats": {
                      "publish": 25,
                      "publish_details": {
                          "rate": 0.1999166347633037,
                          "interval": 5002085,
                          "last_event": 1353718221806
                      }
                  },
                  "exchange": {
                      "name": "test",
                      "vhost": "/"
                  }
              }
          ],
          "deliveries": [
              {
                  "stats": {
                      "ack": 15,
                      "ack_details": {
                          "rate": 0.19941320669797052,
                          "interval": 5014713,
                          "last_event": 1353718218329
                      },
                      "deliver": 15,
                      "deliver_details": {
                          "rate": 0.19941320669797052,
                          "interval": 5014713,
                          "last_event": 1353718218329
                      },
                      "deliver_get": 15,
                      "deliver_get_details": {
                          "rate": 0.19941320669797052,
                          "interval": 5014713,
                          "last_event": 1353718218329
                      },
                      "redeliver": 11,
                      "redeliver_details": {
                          "rate": 0,
                          "interval": 5014713,
                          "last_event": 1353718218329
                      }
                  },
                  "channel_details": {
                      "name": "127.0.0.1:61941 -> 127.0.0.1:5672 (1)",
                      "number": 1,
                      "connection_name": "127.0.0.1:61941 -> 127.0.0.1:5672",
                      "peer_port": 61941,
                      "peer_host": "127.0.0.1"
                  }
              }
          ],
          "message_stats": {
              "ack": 15,
              "ack_details": {
                  "rate": 0.19941320669797052,
                  "interval": 5014713,
                  "last_event": 1353718218329
              },
              "deliver": 15,
              "deliver_details": {
                  "rate": 0.19941320669797052,
                  "interval": 5014713,
                  "last_event": 1353718218329
              },
              "deliver_get": 15,
              "deliver_get_details": {
                  "rate": 0.19941320669797052,
                  "interval": 5014713,
                  "last_event": 1353718218329
              },
              "redeliver": 11,
              "redeliver_details": {
                  "rate": 0,
                  "interval": 5014713,
                  "last_event": 1353718218329
              },
              "publish": 25,
              "publish_details": {
                  "rate": 0.1999166347633037,
                  "interval": 5002085,
                  "last_event": 1353718221806
              }
          },
          "consumer_details": [
              {
                  "channel_details": {
                      "name": "127.0.0.1:61941 -> 127.0.0.1:5672 (1)",
                      "number": 1,
                      "connection_name": "127.0.0.1:61941 -> 127.0.0.1:5672",
                      "peer_port": 61941,
                      "peer_host": "127.0.0.1"
                  },
                  "queue_details": {
                      "name": "test_two",
                      "vhost": "/"
                  },
                  "consumer_tag": "ctag1.0",
                  "exclusive": false,
                  "ack_required": true
              }
          ],
          "name": "test_two",
          "vhost": "/",
          "durable": true,
          "auto_delete": false,
          "arguments": {
              "x-message-ttl": 60000
          }
      }
