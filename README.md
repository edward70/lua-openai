# lua-openai

OpenAI compatible API for Lua. Uses `luasocket` for normal lua installations or [`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests) for OpenResty, which requires adding a `proxy_pass` to the Nginx config:

```
location /proxy {
    internal;
    rewrite_by_lua "
      local req = ngx.req

      for k,v in pairs(req.get_headers()) do
        if k ~= 'content-length' then
          req.clear_header(k)
        end
      end

      if ngx.ctx.headers then
        for k,v in pairs(ngx.ctx.headers) do
          req.set_header(k, v)
        end
      end
    ";

    resolver 8.8.8.8;
    proxy_http_version 1.1;
    proxy_pass $_url;
}
```

## Install

Install using LuaRocks:

```bash
luarocks install lua-openai
```

## Quick Usage

Here we use openrouter but you can use any OpenAI compatible API endpoint.

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENROUTER_API_KEY"), "https://openrouter.ai/api/v1")

local status, response = client:chat({
  {role = "system", content = "You are a Lua programmer"},
  {role = "user", content = "Write a 'Hello world' program in Lua"}
}, {
  model = "openai/gpt-3.5-turbo",
  temperature = 0.5
})

if status == 200 then
  -- the JSON response is automatically parsed into a Lua object
  print(response.choices[1].message.content)
end
```

## Chat Session Example

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"), "https://openrouter.ai/api/v1")

local chat = client:new_chat_session({
  -- provide an initial set of messages
  messages = {
    {role = "system", content = "You are an artist who likes colors"}
  },
  model = "openai/gpt-3.5-turbo",
  temperature = 0.5
})

-- returns the string response
print(chat:send("List your top 5 favorite colors"))

-- the chat history is sent on subsequent requests to continue the conversation
print(chat:send("Excluding the colors you just listed, tell me your favorite color"))

-- the entire chat history is stored in the messages field
for idx, message in ipairs(chat.messages) do
  print(message.role, message.content)
end

-- You can stream the output by providing a callback as the second argument
-- the full response concatenated is also returned by the function
local response = chat:send("What's the most boring color?", function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)
```

## Chat Session Tool Calling

```lua
local chat = openai:new_chat_session({
  model = "openai/gpt-3.5-turbo",
  tools = {
    {
      type = "function"
      name = "add",
      description =  "Add two numbers together",
      parameters = {
        type = "object",
        properties = {
          a = { type = "number" },
          b = { type = "number" }
        }
      }
    }
  }
})
```

Any prompt you send will be aware of all available tools, and may request
any of them to be called. If the response contains a tool call request,
then an object will be returned instead of the standard string return value.

```lua
local res = chat:send("Using the provided function, calculate the sum of 2923 + 20839")

if type(res) == "table" and res.tool_call then
  -- The tool_call object has the following fields:
  --   tool_call.name --> name of function to be called
  --   tool_call.arguments --> A string in JSON format that should match the parameter specification
  -- Note that res may also include a content field if the LLM produced a textual output as well

  local cjson = require "cjson"
  local name = res.tool_call.name
  local arguments = cjson.decode(res.tool_call.arguments)
  -- ... compute the result and send it back ...
end
```

You can evaluate the requested tool & arguments and send the result back to
the client so it can resume operation with a `role=tool` message object:

> Since the LLM can hallucinate every part of the function call, you'll want to
> do robust type validation to ensure that function name and arguments match
> what you expect. Assume every stage can fail, including receiving malformed
> JSON for the arguments.

```lua
local name, arguments = ... -- the name and arguments extracted from above

if name == "add" then
  local value = arguments.a + arguments.b

  -- send the response back to the chat bot using a `role = function` message

  local cjson = require "cjson"

  local res = chat:send({
    role = "tool",
    name = name,
    content = cjson.encode(value)
  })

  print(res) -- Print the final output
else
  error("Unknown function: " .. name)
end
```

## Streaming Response Example

Under normal circumstances the API will wait until the entire response is
available before returning the response. Depending on the prompt this may take
some time. The streaming API can be used to read the output one chunk at a
time, allowing you to display content in real time as it is generated.

```lua
local openai = require("openai")
local client = openai.new(os.getenv("OPENAI_API_KEY"))

client:chat({
  {role = "system", content = "You work for Streak.Club, a website to track daily creative habits"},
  {role = "user", content = "Who do you work for?"}
}, {
  stream = true
}, function(chunk)
  io.stdout:write(chunk.content)
  io.stdout:flush()
end)

print() -- print a newline
```

## Documentation

The `openai` module returns a table with the following fields:

- `OpenAI`: A client for sending requests to the OpenAI API.
- `new`: An alias to `OpenAI` to create a new instance of the OpenAI client
- `ChatSession`: A class for managing chat sessions and history with the OpenAI API.
- `VERSION = "1.1.0"`: The current version of the library

### Classes

#### OpenAI

This class initializes a new OpenAI API client.

##### `new(api_key, config)`

Constructor for the OpenAI client.

- `api_key`: Your OpenAI API key.
- `config`: An optional table of configuration options, with the following shape:
  - `http_provider`: A string specifying the HTTP module name used for requests, or `nil`. If not provided, the library will automatically use "lapis.nginx.http" in an ngx environment, or "ssl.https" otherwise.

```lua
local openai = require("openai")
local api_key = "your-api-key"
local client = openai.new(api_key)
```

##### `client:new_chat_session(...)`

Creates a new [ChatSession](#chatsession) instance. A chat session is an
abstraction over the chat completions API that stores the chat history. You can
append new messages to the history and request completions to be generated from
it. By default, the completion is appended to the history.

##### `client:chat(messages, opts, chunk_callback)`

Sends a request to the `/chat/completions` endpoint.

- `messages`: An array of message objects.
- `opts`: Additional options for the chat, passed directly to the API (eg. model, temperature, etc.) https://platform.openai.com/docs/api-reference/chat
- `chunk_callback`: A function to be called for parsed streaming output when `stream = true` is passed to `opts`.

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:completion(prompt, opts)`

Sends a request to the `/completions` endpoint.

- `prompt`: The prompt for the completion.
- `opts`: Additional options for the completion, passed directly to the API (eg. model, temperature, etc.) https://platform.openai.com/docs/api-reference/completions

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

##### `client:embedding(input, opts)`

Sends a request to the `/embeddings` endpoint.

- `input`: A single string or an array of strings
- `opts`: Additional options for the completion, passed directly to the API (eg. model) https://platform.openai.com/docs/api-reference/embeddings

Returns HTTP status, response object, and output headers. The response object
will be decoded from JSON if possible, otherwise the raw string is returned.

#### ChatSession

This class manages chat sessions and history with the OpenAI API. Typically
created with `new_chat_session`

The field `messages` stores an array of chat messages representing the chat
history. Each message object must conform to the following structure:

- `role`: A string representing the role of the message sender. It must be one of the following values: "system", "user", or "assistant".
- `content`: A string containing the content of the message.
- `name`: An optional string representing the name of the message sender. If not provided, it should be `nil`.

For example, a valid message object might look like this:

```lua
{
  role = "user",
  content = "Tell me a joke",
  name = "John Doe"
}
```

##### `new(client, opts)`

Constructor for the ChatSession.

- `client`: An instance of the OpenAI client.
- `opts`: An optional table of options.
  - `messages`: An initial array of chat messages
  - `functions`: A list of function declarations
  - `temperature`: temperature setting
  - `model`: Which chat completion model to use, eg. `gpt-4`, `gpt-3.5-turbo`

##### `chat:append_message(m, ...)`

Appends a message to the chat history.

- `m`: A message object.

##### `chat:last_message()`

Returns the last message in the chat history.

##### `chat:send(message, stream_callback=nil)`

Appends a message to the chat history and triggers a completion with
`generate_response` and returns the response as a string. On failure, returns
`nil`, an error message, and the raw request response.

If the response includes a `function_call`, then the entire message object is
returned instead of a string of the content. You can return the result of the
function by passing `role = "function"` object to the `send` method

- `message`: A message object or a string.
- `stream_callback`: (optional) A function to enable streaming output.

By providing a `stream_callback`, the request will runin streaming mode. This
function receives chunks as they are parsed from the response.

These chunks have the following format:

- `content`: A string containing the text of the assistant's generated response.

For example, a chunk might look like this:

```lua
{
  content = "This is a part of the assistant's response.",
}
```

##### `chat:generate_response(append_response, stream_callback=nil)`

Calls the OpenAI API to generate the next response for the stored chat history.
Returns the response as a string. On failure, returns `nil`, an error message,
and the raw request response.

- `append_response`: Whether the response should be appended to the chat history (default: true).
- `stream_callback`: (optional) A function to enable streaming output.

See `chat:send` for details on the `stream_callback`
