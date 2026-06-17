llayer - AI agents the Unix way
===============================

This project applies the Unix philosophy to implementing an AI agent: model orchestration is done through a set of
small, single-purpose tools stitched together through pipes and textual interfaces to produce a REPL-style agent loop.

To get started, run a local model server (Ollama) with `docker compose up` then invoke the individual commands. For
example, a stateless, context-free call is simply a chain of command-line tools:

```shell
% echo "Hello, world!" | ./ll-read | ./ll-context | ./ll-eval | ./ll-print
Hello! It's nice to meet you. Is there something I can help you with or would you like to chat?
```

Alternatively, use the `agent` script for an interactive session:

```shell
% ./agent 
> Hello there, good evening.
How can I assist you tonight?
> 
```

Caling specific components of the agent is straightforward. Examples include inspecting and adding to the context passed into the model:

```shell
% (cat .llayer_history && echo "Print some digits of PI" | ./ll-read) | ./ll-context | jq -c '.[]'
{"role":"system","content":"You are a witty math tutor. You MUST only give one-line responses"}
{"role":"user","content":"What's 2+2?"}
{"role":"assistant","content":"Elementary, my friend - it's four and eight!"}
{"role":"user","content":"Print some digits of PI"}
```

Or replaying agent messages from history:

```shell
% cat .llayer_history | ./ll-print --debug
[system] You are Super Mario. You must give one-line responses.
[user] I'm hungry, want to get something to eat?
"It's-a me, I'll power-up and grab some spaghetti at Toad's favorite restaurant!"
[user] How are we going to get there?
"I'll just jump over a few Goombas on the way, we can be like mushrooms growing together!"
[user] Sounds fun
"Let's-a go, it's-a time for some Warp Pipes and a pipe-dream of delicious food!"
```

Or directly inspect streamed model outputs:

```shell
% echo "ping! return pong a few times" | ./ll-read | ./ll-context | ./ll-eval            
{"type":"token","source":"assistant","payload":{"text":"Ping"}}
{"type":"token","source":"assistant","payload":{"text":"!"}}
{"type":"token","source":"assistant","payload":{"text":" P"}}
{"type":"token","source":"assistant","payload":{"text":"ong"}}
{"type":"token","source":"assistant","payload":{"text":"!"}}
{"type":"message_complete","source":"system","payload":{}}
```

Or pipe to a downstream tool to measure how quickly the model is streaming responses back, and buffer all of the output before printing the responses:

```shell
% echo "How much wood could a woodchuck chuck?" | ./ll-read | ./ll-context | ./ll-eval | pv --line-mode | sponge | ./ll-print
 427  0:00:37 [11.3 /s] 
The classic tongue-twister! The answer, of course, is "a woodchuck would chuck as much wood as a woodchuck could chuck if a woodchuck could chuck wood." But let's have some fun with this...
```

Stateful Agent - REPL
---------------------

```mermaid
graph LR
    User

    subgraph READ
        ll-read
        History
        ll-context
    end

    subgraph EVAL
        ll-eval
        ll-dispatch
        Model
        Tools
    end

    subgraph PRINT
        ll-print
    end

    User -->|read| ll-read
    ll-read -->|append| History
    History -->|pipe| ll-context
    ll-context -->|pipe| ll-eval
    ll-eval -->|append| History
    ll-eval -->|pipe| ll-dispatch
    ll-dispatch <-->|call|Tools
    ll-dispatch -->|append| History
    ll-eval -->|pipe| ll-print
    ll-eval <-->|http| Model
    ll-print -->|print| User

    style ll-read fill:#4A90E2
    style ll-context fill:#4A90E2
    style ll-eval fill:#4A90E2
    style ll-dispatch fill:#4A90E2
    style ll-print fill:#4A90E2
```

The `agent` script combines the standalone components to form a read-eval-print loop (REPL) that largely resembles an AI agent:

1. `ll-read` user input and append a corresponding event to the history file.
2. Build `ll-context` from history to produce the model context and `ll-eval` the model.
3. If necessary, `ll-dispatch` to supported tools and append the result to the history; repeat step 2.
4. Append model output as events to history then `ll-print` to display messages to the user.

Implementation
--------------

### Append-Only State

An append-only history file stores all of the state. Each line is an event JSON object describing either a user input, a token emitted by the model, a completed message, or a tool call/result. Motivations and goals of this design:

* Immutability: all events, down to individual tokens, are preserved for auditing, debugging, and replayability.
* Simplicity: using append-only text to store state is robust and  aligns with the minimalist philosophy.
* Composability: downstream tools can consume, filter, and transform the event stream without modifying state.

### Context Building

`ll-context` compacts the canonical event history to build the context for each model call. Its main purposes are:

- Scoping: the command filters history down to relevant events, groups tokens into higher-level messages, and applies configurable heuristics (e.g. keep last N turns, strip tool-call payloads, collapse tokens into a single assistant message) so the model receives concise context.
- Reduction: the original history is never rewritten or deleted; the command reduces the history down to a filtered, model-friendly sequence derived from events that fall within a user-defined window.

### Schema

The individual components utilize a DSL that follows minimal, explicit JSONL shapes where each line contains a `type`, `source`, and `payload`. The basic event schema is as follows:

```json
{"type": "message",          "source": "user",      "payload": {"text": "..."}}
{"type": "message_complete", "source": "system",    "payload": {}}
{"type": "token",            "source": "assistant", "payload": {"text": "..."}}
{"type": "tool_call",        "source": "assistant", "payload": {}}
{"type": "tool_result",      "source": "tool",      "payload": {}}
```
