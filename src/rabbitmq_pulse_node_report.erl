-module(rabbitmq_pulse_node_report).

poll(Hostname) ->
  Remote = lists:concat(["rabbit@", Hostname]),
  io:format("status report ~s~n", [Remote]),
  Node = erlang:list_to_atom(Remote),
  MemEts = rpc:call(Node, erlang, memory, [ets]),
  MemBinary = rpc:call(Node, erlang, memory, [binary]),
  MemProc = rpc:call(Node, erlang, memory, [processes]),
  MemProcUsed = rpc:call(Node, erlang, memory, [processes_used]),
  MemAtom = rpc:call(Node, erlang, memory, [atom]),
  MemAtomUsed = rpc:call(Node, erlang, memory, [atom_used]),
  MemCode = rpc:call(Node, erlang, memory, [code]),
  MemUsed = rpc:call(Node, erlang, memory, [total]),
  MemLimit = rpc:call(Node, vm_memory_monitor, get_memory_limit, []),
  ProcUsed = rpc:call(Node, erlang, system_info, [process_count]),
  ProcTotal = rpc:call(Node, erlang, system_info, [process_limit]),
  RunQueue = rpc:call(Node, erlang, statistics, [run_queue]),
  {{_,BytesIn},{_,BytesOut}} = rpc:call(Node, erlang, statistics, [io]),
  {ContextSwitches, _} = rpc:call(Node, erlang, statistics, [context_switches]).
