import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  RESOURCE_MIME_TYPE,
  registerAppResource,
  registerAppTool
} from "@modelcontextprotocol/ext-apps/server";
import { z } from "zod";

const port = Number(process.env.PORT ?? 8787);
const MCP_PATH = "/mcp";
const todoHtml = readFileSync("public/todo-widget.html", "utf8");

const addTodoInputSchema = {
  title: z.string().min(1)
};

const completeTodoInputSchema = {
  id: z.string().min(1)
};

const renderTodoInputSchema = {
  tasks: z
    .array(
      z.object({
        id: z.string(),
        title: z.string(),
        completed: z.boolean()
      })
    )
    .optional()
};

const todoOutputSchema = {
  tasks: z.array(
    z.object({
      id: z.string(),
      title: z.string(),
      completed: z.boolean()
    })
  )
};

let todos = [];
let nextId = 1;

const replyWithTodos = (message) => ({
  content: message ? [{ type: "text", text: message }] : [],
  structuredContent: { tasks: todos }
});

function createTodoServer() {
  const server = new McpServer({ name: "todo-app", version: "0.1.0" });

  registerAppResource(
    server,
    "todo-widget",
    "ui://widget/todo.html",
    {
      _meta: {
        "openai/widgetDescription": "A compact todo list UI for adding and completing tasks.",
        "openai/widgetPrefersBorder": true,
        "openai/widgetCSP": {
          connect_domains: [],
          resource_domains: []
        },
        ui: {
          csp: {
            connectDomains: [],
            resourceDomains: []
          },
          prefersBorder: true
        }
      }
    },
    async () => ({
      contents: [
        {
          uri: "ui://widget/todo.html",
          mimeType: RESOURCE_MIME_TYPE,
          text: todoHtml
        }
      ]
    })
  );

  registerAppTool(
    server,
    "list_todos",
    {
      title: "List todos",
      description: "Use this when the user wants to inspect the current todo list without rendering UI.",
      inputSchema: {},
      outputSchema: todoOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      },
      _meta: {
        "openai/toolInvocation/invoking": "Reading todos",
        "openai/toolInvocation/invoked": "Todos loaded"
      }
    },
    async () => replyWithTodos()
  );

  registerAppTool(
    server,
    "add_todo",
    {
      title: "Add todo",
      description: "Use this when the user wants to create a todo item with a title.",
      inputSchema: addTodoInputSchema,
      outputSchema: todoOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
      },
      _meta: {
        "openai/toolInvocation/invoking": "Adding todo",
        "openai/toolInvocation/invoked": "Todo added"
      }
    },
    async (args) => {
      const title = args?.title?.trim?.() ?? "";
      if (!title) return replyWithTodos("Missing title.");
      const todo = { id: `todo-${nextId++}`, title, completed: false };
      todos = [...todos, todo];
      return replyWithTodos(`Added "${todo.title}".`);
    }
  );

  registerAppTool(
    server,
    "complete_todo",
    {
      title: "Complete todo",
      description: "Use this when the user wants to mark an existing todo item as complete.",
      inputSchema: completeTodoInputSchema,
      outputSchema: todoOutputSchema,
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      },
      _meta: {
        "openai/toolInvocation/invoking": "Completing todo",
        "openai/toolInvocation/invoked": "Todo completed"
      }
    },
    async (args) => {
      const id = args?.id;
      if (!id) return replyWithTodos("Missing todo id.");
      const todo = todos.find((task) => task.id === id);
      if (!todo) return replyWithTodos(`Todo ${id} was not found.`);

      todos = todos.map((task) =>
        task.id === id ? { ...task, completed: true } : task
      );

      return replyWithTodos(`Completed "${todo.title}".`);
    }
  );

  registerAppTool(
    server,
    "render_todo_widget",
    {
      title: "Render todo widget",
      description:
        "Use this when the user should see or interact with the todo list UI. Call list_todos, add_todo, or complete_todo first when fresh data is needed.",
      inputSchema: renderTodoInputSchema,
      outputSchema: todoOutputSchema,
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      },
      _meta: {
        "openai/toolInvocation/invoking": "Rendering todo list",
        "openai/toolInvocation/invoked": "Todo list ready",
        "openai/outputTemplate": "ui://widget/todo.html",
        ui: { resourceUri: "ui://widget/todo.html" }
      }
    },
    async (args) => {
      const tasks = Array.isArray(args?.tasks) ? args.tasks : todos;
      return {
        content: [{ type: "text", text: "Showing the todo list." }],
        structuredContent: { tasks }
      };
    }
  );

  return server;
}

const httpServer = createServer(async (req, res) => {
  if (!req.url) {
    res.writeHead(400).end("Missing URL");
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);

  if (req.method === "OPTIONS" && url.pathname === MCP_PATH) {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "content-type, mcp-session-id",
      "Access-Control-Expose-Headers": "Mcp-Session-Id"
    });
    res.end();
    return;
  }

  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/plain" }).end("Todo MCP server");
    return;
  }

  const mcpMethods = new Set(["POST", "GET", "DELETE"]);
  if (url.pathname === MCP_PATH && req.method && mcpMethods.has(req.method)) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");

    const server = createTodoServer();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true
    });

    res.on("close", () => {
      transport.close();
      server.close();
    });

    try {
      await server.connect(transport);
      await transport.handleRequest(req, res);
    } catch (error) {
      console.error("Error handling MCP request:", error);
      if (!res.headersSent) {
        res.writeHead(500).end("Internal server error");
      }
    }
    return;
  }

  res.writeHead(404).end("Not Found");
});

httpServer.listen(port, () => {
  console.log(`Todo MCP server listening on http://localhost:${port}${MCP_PATH}`);
});
