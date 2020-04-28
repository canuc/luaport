# LuaPort
*An [erlang port](http://erlang.org/doc/tutorial/c_port.html) for scripting application logic in lua*
```erlang
{ok, Pid} = luaport:spawn(someid, "path/to/scripts"),
{ok, [6]} = luaport:call(Pid, multiply, [2, 3]).
```
```lua
function multiply(a, b)
  return a * b
end
```

## Test
```
git clone https://github.com/asciibeats/luaport.git
cd luaport
rebar3 ct
```

## Use
If you use erlang and [rebar3](https://www.rebar3.org), add LuaPort as dependency to your `rebar.config`.
```erlang
{deps, [
  {luaport, {git, "https://github.com/asciibeats/luaport.git", {tag, "v1.1.0"}}}
]}.
```
Or for elixir and mix, add it to your `mix.exs`.
```elixir
defp deps do
  [
    {:luaport, "~> 1.1"}
  ]
end
```
Create a lua script at path/to/scripts called `main.lua`.
```lua
function subtract(a, b)
  return a - b
end
```
When using erlang, don't forget to start the application.
```erlang
application:start(luaport),
{ok, Pid} = luaport:spawn(myid, "path/to/scripts"),
{ok, Results} = luaport:call(Pid, subtract, [43, 1]),
luaport:despawn(myid),
application:stop(luaport).
```
Elixir will start it automatically.
```elixir
{:ok, pid} = :luaport.spawn(:myid, 'path/to/scripts')
{:ok, results} = :luaport.call(pid, :subtract, [43, 1])
:luaport.despawn(:myid)
```
Ports can be spawned with a callback module to be able to call or cast erlang functions from lua context. The fourth argument, the pipe, is not interpreted by the port. Its elements will become arguments when calling or casting back.
```erlang
{ok, Pid} = luaport:spawn(myid, "path/to/scripts", callback, [one, "another"]),
luaport:cast(Pid, execute).
```
The main script gets interpreted on every spawn or respawn. You could load some state into persistent memory for use throughout the port's lifecycle. The print function in this example is a custom function mimicking Lua's own print function. It shows its output in the erlang shell, is able to print tables in depth and can take a variable number of arguments.
```lua
local state, number = port.call.init('sunshine', 49)

function execute()
  print(state, number)
end
```
The port's reference is the first argument of every callback, followed by the pipe and the original arguments.
```erlang
-module(callback).

-export([init/5]).

init(myid, one, "another", String, Number) ->
  [#{string => String}, Number].
```
If you want to insert or just execute some code during runtime, use the load function.
```erlang
{ok, []} = luaport:load(Pid, <<"function something() return 666 end">>),
{ok, [666]} = luaport:call(Pid, something).
```
```erlang
{ok, []} = luaport:load(Pid, <<"print('nice')">>).
```
To be able to continuously call or cast functions after accidental or intended respawns, you could use `{global, Name}` or `{local, Name}` as reference to register the port.
```erlang
{ok, _Pid1} = luaport:spawn({local, myid}, "path/to/scripts"),
{ok, _Pid2} = luaport:respawn({local, myid}),
luaport:cast({local, myid}, execute).
```
Requiring modules works normally. You can put a module.lua or module.so into path/to/scripts or any other path in lua's package.path or package.cpath, respectively.
```lua
local module = require('module')
```
Lua has no delayed call mechanism, therefore LuaPort provides an interface to erlangs timer functions. The number is the time to wait in milliseconds.
```lua
port.after(3000, function (str) print(str) end, 'call once, if not canceled')
```
```lua
local ref = port.interval(1000, function (str) print(str) end, 'call repeatedly until canceled')
port.cancel(ref)
```

## Quirks
Since erlang and lua datatypes do not align too nicely, there are some things to consider.

- Lua has only one collection type, the table. It is like a map in erlang. So when maps get translated to lua they become tables. 
- When lists or tuples get translated they become tables with a metatype 'list' or 'tuple', respectively.
- Strings in erlang are lists and translated as such. Lua has no dedicated binary type. If you want to translate to strings, use binary strings.
- Erlang has no boolean type and atoms serve no purpose in lua context. So atom true translates to true and atom false to false.
- Atom undefined translates to nil.
- For convenience, all other atoms become strings. They will be handled like any other string on the way back.

#### Translations
| Erlang | Lua | Notes |
| --- | --- | --- |
| 23 | 23 | |
| "abc" | {97, 98, 99} | erlang strings are lists |
| <<"abc">> | 'abc' | |
| \[1, 2] | {1, 2} | has metatype 'list' |
| {3, 4} | {3, 4} | has metatype 'tuple' |
| #{5 => 6} | {\[5] = 6} | has no metatype |
| true | true | |
| false | false | |
| undefined | nil | |

#### Helpers
| Function | Description |
| --- | --- |
| port.aslist(t) | set metatype 'list' |
| port.astuple(t) | set metatype 'tuple' |
| port.asmap(t) | unset metatype |
| port.islist(v) | if metatype 'list' |
| port.istuple(v) | if metatype 'tuple' |
| port.ismap(v) | if no metatype |

## Help
It is very much appreciated. What i could use help with:

- Just trying out LuaPort and seeing if i made sensible choices
- Finding and fixing bugs
- Writing a more versatile makefile
- Things i don't know i need help with

Thank you!
