-module(luaport_server).

-export([start_link/5]).
-export([init/5]).
-export([call/4]).
-export([cast/4]).

-define(TIMEOUT, 5000).
-define(EXIT_REASONS, #{
  0 => {shutdown, success},
  139 => {respawn, segmentation_fault},
  141 => {respawn, broken_pipe},
  200 => {respawn, fail_read},
  201 => {respawn, fail_write},
  202 => {respawn, fail_size},
  210 => {respawn, bad_version},
  211 => {respawn, bad_tuple},
  212 => {respawn, bad_atom},
  213 => {respawn, bad_func},
  214 => {respawn, bad_args},
  215 => {respawn, bad_call},
  216 => {respawn, bad_command},
  220 => {respawn, call_read},
  221 => {respawn, call_version},
  222 => {respawn, call_result},
  230 => {respawn, after_read},
  231 => {respawn, after_version},
  232 => {respawn, after_ref}}).

start_link(PortRef, Path, M, Pipe, Timeout) ->
  Pid = spawn_link(?MODULE, init, [PortRef, Path, M, Pipe, Timeout]),
  register_name(PortRef, Pid),
  {ok, Pid}.

init(PortRef, Path, M, Pipe, Timeout) when is_list(Path), is_atom(M), is_list(Pipe) ->
  process_flag(trap_exit, true),
  Exec = filename:join([code:priv_dir(luaport), "luaport"]),
  Port = open_port({spawn_executable, Exec}, [{cd, Path}, {packet, 4}, binary, exit_status]),
  TRefs = #{},
  {ok, []} = portloop(PortRef, Port, M, Pipe, TRefs, Timeout),
  mainloop(PortRef, Port, M, Pipe, TRefs).

call(PortRef, F, A, Timeout) when is_atom(F), is_list(A) ->
  Ref = make_ref(),
  send(PortRef, {call, F, A, Timeout, self(), Ref}),
  receive
    {Ref, Result} -> Result
  end.

cast(PortRef, F, A, Timeout) when is_atom(F), is_list(A) ->
  send(PortRef, {cast, F, A, Timeout}),
  ok.

mainloop(PortRef, Port, M, Pipe, TRefs) ->
  receive
    {call, F, A, Timeout, From, Ref} ->
      Port ! {self(), {command, term_to_binary({F, A})}},
      From ! {Ref, portloop(PortRef, Port, M, Pipe, TRefs, Timeout)},
      mainloop(PortRef, Port, M, Pipe, TRefs);
    {cast, F, A, Timeout} ->
      Port ! {self(), {command, term_to_binary({F, A})}},
      portloop(PortRef, Port, M, Pipe, TRefs, Timeout),
      mainloop(PortRef, Port, M, Pipe, TRefs);
    {cast, LRef, Timeout} ->
      Port ! {self(), {command, term_to_binary(LRef)}},
      portloop(PortRef, Port, M, Pipe, TRefs, Timeout),
      mainloop(PortRef, Port, M, Pipe, TRefs);
    {'EXIT', _From, Reason} ->
      port_close(Port),
      exit(Reason)
  end.

portloop(PortRef, Port, M, Pipe, TRefs, Timeout) ->
  receive
    {Port, {data, Data}} ->
      try binary_to_term(Data, [safe]) of
        {call, F, A} ->
          Result = tryapply(M, F, [PortRef | Pipe ++ A]),
          Port ! {self(), {command, term_to_binary(Result)}},
          portloop(PortRef, Port, M, Pipe, TRefs, Timeout);
        {cast, F, A} ->
          tryapply(M, F, [PortRef | Pipe ++ A]),
          portloop(PortRef, Port, M, Pipe, TRefs, Timeout);
        {info, List} ->
          io:format("inf ~p ~p~n", [PortRef, List]),
          portloop(PortRef, Port, M, Pipe, TRefs, Timeout);
        {'after', Time, LRef} ->
          {ok, TRef} = timer:send_after(Time, {cast, LRef, Timeout}),
          portloop(PortRef, Port, M, Pipe, maps:put(LRef, TRef, TRefs), Timeout);
        {interval, Time, LRef} ->
          {ok, TRef} = timer:send_interval(Time, {cast, LRef, Timeout}),
          portloop(PortRef, Port, M, Pipe, maps:put(LRef, TRef, TRefs), Timeout);
        {cancel, LRef} ->
          {TRef, TRefs2} = maps:take(LRef, TRefs),
          timer:cancel(TRef),
          portloop(PortRef, Port, M, Pipe, TRefs2, Timeout);
        {error, Reason} ->
          io:format("err ~p ~p~n", [PortRef, Reason]),
          {error, Reason};
        {ok, Results} ->
          {ok, Results}
      catch
        error:badarg -> exit({respawn, unsafe_data})
      end;
    {Port, {exit_status, Status}} ->
      exit(maps:get(Status, ?EXIT_REASONS, {respawn, Status}))
  after Timeout ->
    io:format("err ~p ~p~n", [PortRef, timeout]),
    {error, timeout}
  end.

register_name({global, Name}, Pid) ->
  global:register_name(Name, Pid),
  wait_for_name(Name);
register_name({local, Name}, Pid) ->
  register(Name, Pid);
register_name(_PortRef, _Pid) ->
  ok.

send({global, Name}, Message) ->
  global:send(Name, Message);
send({local, Name}, Message) ->
  Name ! Message;
send(Pid, Message) ->
  Pid ! Message.

wait_for_name(Name) ->
  wait_for_name(Name, false).
wait_for_name(Name, false) ->
  timer:sleep(500),
  wait_for_name(Name, lists:member(Name, global:registered_names()));
wait_for_name(_Name, true) ->
  ok.

tryapply(M, F, A) when M =/= undefined ->
  try
    apply(M, F, A)
  catch
    error:undef -> []
  end;
tryapply(_M, _F, _A) ->
  [].
