# Todo ChatGPT App

A minimal ChatGPT Apps SDK todo app with:

- an MCP server at `http://localhost:8787/mcp`
- a vanilla HTML widget at `public/todo-widget.html`
- data tools: `list_todos`, `add_todo`, and `complete_todo`
- render tool: `render_todo_widget`

The app uses the decoupled Apps SDK pattern: data tools return
`structuredContent` only, while `render_todo_widget` owns the UI template.

## Run locally

```bash
npm install
npm start
```

Health check:

```bash
curl http://localhost:8787/
```

## Test with MCP Inspector

```bash
npx @modelcontextprotocol/inspector@latest \
  --server-url http://localhost:8787/mcp \
  --transport http
```

## Connect to ChatGPT

Expose the local server:

```bash
ngrok http 8787
```

Then use the public HTTPS MCP URL in ChatGPT:

```text
https://<subdomain>.ngrok.app/mcp
```

Enable Developer Mode in ChatGPT under Settings, create a new app/connector,
and paste the tunneled `/mcp` URL.
