llayer - agents the Unix way
============================

A simple, Unix-minded agent runtime with composable command-line tools.

`llayer` is a minimal implementation of an interactive agent that applies the Unix philosophy to LLM orchestration: small, single-purpose tools stitched together through pipes and textual interfaces to implement a REPL-style agent loop.

The repository is intentionally tiny and treats the event stream as the canonical source of truth. Each component is a simple program that performs one role and can be composed in scripts or pipelines.

### Event sourcing

The implementation uses an append-only history file as the canonical state store. Each line is an event JSON object describing either a user input, a token emitted by the LLM, a completed message, or a tool call.

Why event sourcing?

- Immutable audit trail: every token and event is preserved for replay and debugging.
- Simple persistence: appending lines to a text file is robust and aligns with the Unix philosophy.
- Composability: downstream tools can consume, filter, and transform the event stream without changing the original history.

Standard history format

We follow a small, explicit JSONL shape where each line contains a `type` and `payload`. Example events you will see in `history.jsonl`:

```json
{"type": "message", "source": "user", "payload": {"text": "Hello"}}
{"type": "token", "source": "assistant", "payload": {"text": "Hi"}}
{"type": "message_complete", "source": "system", "payload": {}}
```

##### Compaction

`compact` implements lightweight compression on top of the canonical event history. Namely:

- Non-destructive: `compact` does not rewrite or delete the original history; it produces a smaller, model-friendly sequence derived from recent events.
- Role: it selects relevant events, groups token streams into higher-level messages, and applies configurable heuristics (e.g. keep last N turns, strip tool-call payloads, collapse tokens into a single assistant message) so the model receives concise context.
- Purpose: reduce prompt size and convert token-granular stream logs into coherent message blocks suitable for the LLM.

Barebones
---------

A barebones, context-free/stateless interaction is simply a chain of command-line calls:

```
% echo "Hello, world!" | ./prompt | ./compact | ./invoke | ./extract 
Hello! It's nice to meet you. Is there something I can help you with or would you like to chat?
```


Agent REPL
----------

```mermaid
graph LR
    subgraph Read
        User["👤 User input<br/>(stdin)"]
        Prompt["<b>prompt</b><br/>format input"]
        History["📜 .llayer_history<br/>(append-only)"]
        Compact["<b>compact</b><br/>select & compress"]
    end

    subgraph Eval
        Invoke["<b>invoke</b><br/>stream from LLM"]
    end

    subgraph Print
        Extract["<b>extract</b><br/>format output"]
        Screen["🖥️ Terminal output<br/>(stdout)"]
    end

    Model["LLM"]

    User -->|text| Prompt
    Prompt -->|append| History
    History -->|read all| Compact
    Compact -->|pipe| Invoke
    Invoke -->|append| History
    Invoke -->|pipe| Extract
    Invoke -->|http| Model
    Extract -->|print| Screen
    Screen --> User

    style History fill:#676767,stroke:#333,stroke-width:2px
```

The `agent` script represents a read-eval-print-loop (REPL):

1. `prompt`s for user input and appends a formatted event to the history file.
2. `compact`s history to produce the model context and `invoke` to stream the model output.
3. Append streamed events to history and `extract` the model output.

```
% ./agent           
> Hello, world
Hello! It's nice to meet you. Is there something I can help you with or would you like to chat?
> Let's chat
We can have a conversation on any topic that interests you. What would you like to talk about?
```

License
-------

MIT


