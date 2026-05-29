# Bella

Bella contains two Apple/OpenAI development surfaces:

- `Bella.xcodeproj`: the iOS app.
- `ChatGPTTodoApp/`: a ChatGPT Apps SDK MCP server and widget demo.

## iOS app

Open the Xcode project:

```bash
open Bella.xcodeproj
```

Build from the command line:

```bash
xcodebuild -project Bella.xcodeproj \
  -scheme Bella \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build
```

## ChatGPT app

Run the MCP server:

```bash
cd ChatGPTTodoApp
npm install
npm start
```

The MCP endpoint is:

```text
http://localhost:8787/mcp
```
