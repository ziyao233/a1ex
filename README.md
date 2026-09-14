# A1ex

A simple (and likely poor) LLM coding agent in Lua.

## Security Warning

This project implements no sandboxing or approval mechanisms for tool calls.
Since LLM agents are effectively RCEs, please isolate them in separate
containers or VMs.

Technically, any agents, hacked by prompts from untrusted sources, could steal
your API keys and consume your other valuable resources. The best solution is
forwarding your requests through a local API gateway to prevent unwelcomed guys
from accessing with your LLM API key at first, and do not provide valuable keys
or tokens to your agent :)

## Usage

You should be able to install it with luarocks, or invoke it directly through
`a1ex.lua`. It depends on,

- `lua5.4` or later,
- `luaposix`
- `lua-CURLv3`
- `lua-cjson`

It executes `$HOME/.config/a1ex.lua` on start, and retrieves configuration from
its return value. a1ex expects a table, and recognizes following fields,

- `endpoint`: string, OpenAI-completion-style API endpoint
- `apiKey`: string, literally authentication key
- `arguments`, table, should contain JSON-respresentable simple values
	       (number, string, boolean, etc.) only. They would be copied to
	       requests sent to servers as-is.

## License and Code Origin

MPL-2.0. This small program is written by hand.

## About public contribution

This is a side-project guided by interests, thus no public contribution will
be accepted. Humans are still welcomed to post interesting ideas as issues.
