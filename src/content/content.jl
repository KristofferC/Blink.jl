using HttpServer, WebSockets, Lazy

include("config.jl")

# Content

type Frame
  id::Int
  sock::WebSocket
  init
  msg

  function Frame(init = nothing, msg = nothing)
    f = new(gen_id())
    f.init, f.msg = init, msg
    pool[f.id] = WeakRef(f)
    finalizer(f, f -> delete!(pool, f.id))
    return f
  end
end

const pool = Dict{Int, WeakRef}()

function gen_id()
  i = 1
  while haskey(pool, i) i += 1 end
  return i
end

# Server Setup

parse_id(s::String) = parse(s[2:end])

function http_handler(req, res)
  try
    pool[parse_id(req.resource)] # Only valid if frame with the ID exists
  catch e
    res = Response("Not found")
    res.status = 404
    return res
  end
  return readall(joinpath(dirname(@__FILE__), "main.html"))
end

function sock_handler(req, client)
  local f
  try
    f = pool[id(req.resource)].value
    # TODO: check if f already has a client, call init
  catch e
    close(client)
    return
  end
  f.sock = client
  while !client.is_closed
    data = read(client)
    @errs f.msg != nothing && f.msg(data)
  end
end

function __init__()
  http = HttpHandler(http_handler)
  http.events["error"]  = (client, err) -> println(err)
  http.events["listen"] = (port)        -> println("Listening on $port...")

  const server = Server(http, WebSocketHandler(sock_handler))
  @schedule @errs run(server, port())
end