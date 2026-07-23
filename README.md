# Lilbud

A native, local-first macOS chat app foundation. Conversations are persisted only
on the device; the only networked capability is the explicit `search_web` tool.

## Web search

Lilbud uses [Exa Search](https://exa.ai) for raw web retrieval. Before enabling
the Pi tool loop, provide the API key to the app process:

```bash
export EXA_API_KEY="your-key"
swift run Lilbud
```

The provider sends `type: "auto"`, requests highlights only, limits results to
10, and uses a 24-hour freshness limit only when the model requests a recent
search. It returns source-labelled excerpts for the local model to reason over;
it does not ask Exa to write Lilbud's final response.
