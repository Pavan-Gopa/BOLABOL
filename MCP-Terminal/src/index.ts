#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { exec, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as http from "node:http";

// --- Configuration & Constants ---
const DEFAULT_TIMEOUT_SEC = 120;
const MAX_TIMEOUT_SEC = 600;
const MAX_OUTPUT_BYTES = 100 * 1024; // 100 KB max output per stream

// --- Helper Functions ---

/**
 * Truncate string if it exceeds max limit, adding notice
 */
function truncateOutput(text: string, maxBytes: number = MAX_OUTPUT_BYTES): string {
  if (Buffer.byteLength(text, "utf-8") <= maxBytes) {
    return text;
  }
  const truncated = text.slice(0, maxBytes);
  return `${truncated}\n\n[... Output truncated because it exceeded ${Math.round(maxBytes / 1024)} KB limit ...]`;
}

/**
 * Execute command safely with timeout and output capture
 */
interface ExecutionResult {
  exitCode: number | null;
  stdout: string;
  stderr: string;
  durationMs: number;
  timedOut: boolean;
  error?: string;
}

async function runCommand(
  command: string,
  cwd: string = process.cwd(),
  timeoutSec: number = DEFAULT_TIMEOUT_SEC,
  extraEnv: Record<string, string> = {}
): Promise<ExecutionResult> {
  const startTime = Date.now();
  const effectiveTimeoutSec = Math.min(Math.max(1, timeoutSec), MAX_TIMEOUT_SEC);
  const { promise, resolve } = Promise.withResolvers<ExecutionResult>();

  const shell = process.env.SHELL || (os.platform() === "win32" ? "cmd.exe" : "/bin/bash");
  const shellArgs = os.platform() === "win32" ? ["/s", "/c", command] : ["-c", command];

  const child = spawn(shell, shellArgs, {
    cwd,
    env: { ...process.env, ...extraEnv },
    stdio: "pipe",
  });

  let stdoutData = "";
  let stderrData = "";
  let timedOut = false;

  const timeoutTimer = setTimeout(() => {
    timedOut = true;
    try {
      child.kill("SIGTERM");
      setTimeout(() => {
        if (!child.killed) {
          child.kill("SIGKILL");
        }
      }, 3000);
    } catch {
      // Ignore kill errors
    }
  }, effectiveTimeoutSec * 1000);

  child.stdout.on("data", (data) => {
    stdoutData += data.toString();
  });

  child.stderr.on("data", (data) => {
    stderrData += data.toString();
  });

  child.on("error", (err) => {
    clearTimeout(timeoutTimer);
    resolve({
      exitCode: -1,
      stdout: truncateOutput(stdoutData),
      stderr: truncateOutput(stderrData),
      durationMs: Date.now() - startTime,
      timedOut: false,
      error: err.message,
    });
  });

  child.on("close", (code) => {
    clearTimeout(timeoutTimer);
    resolve({
      exitCode: code,
      stdout: truncateOutput(stdoutData),
      stderr: truncateOutput(stderrData),
      durationMs: Date.now() - startTime,
      timedOut,
    });
  });

  return promise;
}

/**
 * Auto-detect project test runner framework
 */
function detectTestRunner(projectPath: string): { command: string; framework: string } | null {
  const checkFile = (file: string) => fs.existsSync(path.join(projectPath, file));

  if (checkFile("package.json")) {
    try {
      const pkgJson = JSON.parse(fs.readFileSync(path.join(projectPath, "package.json"), "utf-8"));
      if (pkgJson.scripts && pkgJson.scripts.test) {
        return { command: "npm test", framework: "npm" };
      }
    } catch {
      return { command: "npm test", framework: "npm" };
    }
  }

  if (checkFile("Package.swift")) {
    return { command: "swift test", framework: "swift" };
  }

  if (checkFile("Cargo.toml")) {
    return { command: "cargo test", framework: "cargo" };
  }

  if (checkFile("go.mod")) {
    return { command: "go test ./...", framework: "go" };
  }

  if (checkFile("pytest.ini") || checkFile("pyproject.toml") || checkFile("setup.py") || checkFile("conftest.py")) {
    return { command: "pytest", framework: "pytest" };
  }

  if (checkFile("Makefile")) {
    return { command: "make test", framework: "make" };
  }

  return null;
}

// --- Tool Definitions ---

const TOOLS: Tool[] = [
  {
    name: "execute_command",
    description:
      "Execute an arbitrary shell/terminal command in the specified directory. Use this tool to run commands, inspect files, check git status, or execute scripts.",
    inputSchema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "The shell command to execute (e.g., 'npm test', 'git status', 'ls -la', 'python script.py')",
        },
        cwd: {
          type: "string",
          description: "Directory to execute the command in (optional, defaults to current working directory)",
        },
        timeout: {
          type: "number",
          description: "Timeout in seconds (optional, default: 120, max: 600)",
        },
        env: {
          type: "object",
          description: "Key-value pair of additional environment variables to pass to the process",
          additionalProperties: { type: "string" },
        },
      },
      required: ["command"],
    },
  },
  {
    name: "run_tests",
    description:
      "Run unit/integration tests for a software project. Auto-detects framework (npm, swift, pytest, cargo, go) or executes custom test commands with detailed test execution summary.",
    inputSchema: {
      type: "object",
      properties: {
        project_path: {
          type: "string",
          description: "Absolute or relative path to project root (defaults to current working directory)",
        },
        command: {
          type: "string",
          description: "Explicit command to run tests (e.g. 'npm test', 'pytest tests/test_auth.py', 'swift test')",
        },
        framework: {
          type: "string",
          enum: ["auto", "npm", "pytest", "swift", "cargo", "go", "make", "jest", "vitest", "custom"],
          description: "Test framework preset to auto-configure (default: 'auto')",
        },
        test_filter: {
          type: "string",
          description: "Filter/pattern for specific tests (e.g., 'auth', 'TestLogin', 'tests/test_api.py')",
        },
        timeout: {
          type: "number",
          description: "Timeout in seconds for the test execution (default: 300)",
        },
      },
    },
  },
  {
    name: "get_terminal_info",
    description: "Get information about the system environment, current shell, operating system, and installed command line tools.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "list_directory",
    description: "List directory contents including file sizes and modification dates to help navigate project files before running commands.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Directory path to list (defaults to current working directory)",
        },
        show_hidden: {
          type: "boolean",
          description: "Include hidden files (starting with dot)",
        },
      },
    },
  },
];

// --- MCP Server Setup ---

function createMcpServer(): Server {
  const server = new Server(
    {
      name: "terminal-mcp-server",
      version: "1.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // List tools handler
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return { tools: TOOLS };
  });

  // Call tool handler
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;

    try {
      if (name === "execute_command") {
        const command = String(args.command || "");
        if (!command.trim()) {
          return {
            content: [{ type: "text", text: "Error: 'command' argument must not be empty." }],
            isError: true,
          };
        }

        const cwd = args.cwd ? path.resolve(String(args.cwd)) : process.cwd();
        const timeout = typeof args.timeout === "number" ? args.timeout : DEFAULT_TIMEOUT_SEC;
        const extraEnv = (args.env && typeof args.env === "object") ? (args.env as Record<string, string>) : {};

        if (!fs.existsSync(cwd)) {
          return {
            content: [{ type: "text", text: `Error: Working directory '${cwd}' does not exist.` }],
            isError: true,
          };
        }

        console.error(`[Terminal MCP] Executing: "${command}" in "${cwd}"`);

        const res = await runCommand(command, cwd, timeout, extraEnv);

        let outputText = `=== Command Execution Result ===\n`;
        outputText += `Command: ${command}\n`;
        outputText += `Directory: ${cwd}\n`;
        outputText += `Status: ${res.timedOut ? "TIMED OUT" : res.exitCode === 0 ? "SUCCESS (Exit Code 0)" : `FAILED (Exit Code ${res.exitCode})`}\n`;
        outputText += `Duration: ${(res.durationMs / 1000).toFixed(2)}s\n\n`;

        if (res.error) {
          outputText += `--- System Error ---\n${res.error}\n\n`;
        }

        outputText += `--- STDOUT ---\n${res.stdout || "(no output)"}\n\n`;
        outputText += `--- STDERR ---\n${res.stderr || "(no errors)"}\n`;

        return {
          content: [{ type: "text", text: outputText }],
          isError: res.exitCode !== 0 || res.timedOut,
        };
      }

      if (name === "run_tests") {
        const projectPath = args.project_path ? path.resolve(String(args.project_path)) : process.cwd();
        const framework = String(args.framework || "auto");
        const filter = args.test_filter ? String(args.test_filter) : "";
        const timeout = typeof args.timeout === "number" ? args.timeout : 300;
        let testCmd = args.command ? String(args.command) : "";

        if (!fs.existsSync(projectPath)) {
          return {
            content: [{ type: "text", text: `Error: Project directory '${projectPath}' does not exist.` }],
            isError: true,
          };
        }

        // Auto-detect test runner if no explicit command
        if (!testCmd) {
          const detected = detectTestRunner(projectPath);
          if (detected) {
            testCmd = detected.command;
            console.error(`[Terminal MCP] Auto-detected test runner (${detected.framework}): "${testCmd}"`);
          } else {
            testCmd = "npm test"; // fallback default
          }
        }

        // Append filter if specified
        if (filter) {
          if (testCmd.startsWith("npm") || testCmd.startsWith("npx") || testCmd.startsWith("yarn") || testCmd.startsWith("pnpm")) {
            testCmd += ` -- ${filter}`;
          } else if (testCmd.startsWith("pytest")) {
            testCmd += ` -k "${filter}"`;
          } else if (testCmd.startsWith("swift")) {
            testCmd += ` --filter "${filter}"`;
          } else if (testCmd.startsWith("cargo")) {
            testCmd += ` ${filter}`;
          } else if (testCmd.startsWith("go test")) {
            testCmd += ` -run "${filter}"`;
          } else {
            testCmd += ` ${filter}`;
          }
        }

        console.error(`[Terminal MCP] Running Tests: "${testCmd}" in "${projectPath}"`);

        const res = await runCommand(testCmd, projectPath, timeout);

        let outputText = `=== Test Execution Summary ===\n`;
        outputText += `Project Path: ${projectPath}\n`;
        outputText += `Test Command: ${testCmd}\n`;
        outputText += `Result: ${res.timedOut ? "TIMEOUT EXCEEDED" : res.exitCode === 0 ? "PASSED" : "FAILED"}\n`;
        outputText += `Exit Code: ${res.exitCode}\n`;
        outputText += `Duration: ${(res.durationMs / 1000).toFixed(2)}s\n\n`;

        outputText += `--- TEST OUTPUT (STDOUT) ---\n${res.stdout || "(empty)"}\n\n`;
        if (res.stderr) {
          outputText += `--- TEST ERRORS / WARNINGS (STDERR) ---\n${res.stderr}\n`;
        }

        return {
          content: [{ type: "text", text: outputText }],
          isError: res.exitCode !== 0 || res.timedOut,
        };
      }

      if (name === "get_terminal_info") {
        const info = {
          os: `${os.type()} ${os.release()} (${os.arch()})`,
          hostname: os.hostname(),
          platform: os.platform(),
          homedir: os.homedir(),
          cwd: process.cwd(),
          shell: process.env.SHELL || (os.platform() === "win32" ? "cmd.exe" : "/bin/sh"),
          user: os.userInfo().username,
          cpus: os.cpus().length,
          totalMemoryMb: Math.round(os.totalmem() / (1024 * 1024)),
          freeMemoryMb: Math.round(os.freemem() / (1024 * 1024)),
        };

        // Quick check for common tools
        const toolChecks = await Promise.all(
          ["node", "npm", "git", "python3", "swift", "cargo", "go", "docker"].map(async (tool) => {
            const check = await runCommand(`which ${tool}`, process.cwd(), 3);
            return [tool, check.exitCode === 0 ? check.stdout.trim() : "not found"];
          })
        );

        const availableTools = Object.fromEntries(toolChecks);

        let text = "=== Terminal Environment Info ===\n";
        text += JSON.stringify({ ...info, availableTools }, null, 2);

        return {
          content: [{ type: "text", text }],
        };
      }

      if (name === "list_directory") {
        const dirPath = args.path ? path.resolve(String(args.path)) : process.cwd();
        const showHidden = Boolean(args.show_hidden);

        if (!fs.existsSync(dirPath)) {
          return {
            content: [{ type: "text", text: `Error: Directory '${dirPath}' does not exist.` }],
            isError: true,
          };
        }

        const entries = fs.readdirSync(dirPath, { withFileTypes: true });
        const list = entries
          .filter((e) => showHidden || !e.name.startsWith("."))
          .map((e) => {
            const full = path.join(dirPath, e.name);
            let size = 0;
            let mtime = "";
            try {
              const stat = fs.statSync(full);
              size = stat.size;
              mtime = stat.mtime.toISOString();
            } catch {
              // ignore permission errors
            }
            return {
              name: e.name + (e.isDirectory() ? "/" : ""),
              type: e.isDirectory() ? "directory" : e.isFile() ? "file" : "other",
              sizeBytes: size,
              modified: mtime,
            };
          });

        let text = `=== Listing directory: ${dirPath} ===\n`;
        text += JSON.stringify(list, null, 2);

        return {
          content: [{ type: "text", text }],
        };
      }

      return {
        content: [{ type: "text", text: `Unknown tool: ${name}` }],
        isError: true,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        content: [{ type: "text", text: `Tool error: ${message}` }],
        isError: true,
      };
    }
  });

  return server;
}

// --- Transport Initialization ---

async function main() {
  const args = process.argv.slice(2);
  const ssePortIndex = args.indexOf("--port");
  const isSSE = args.includes("--sse") || ssePortIndex !== -1;

  if (isSSE) {
    // SSE Mode for HTTP remote/web connections
    const port = ssePortIndex !== -1 && args[ssePortIndex + 1] ? parseInt(args[ssePortIndex + 1], 10) : 3000;
    const transports = new Map<string, SSEServerTransport>();

    const httpServer = http.createServer(async (req, res) => {
      // CORS headers
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");

      if (req.method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

      const url = new URL(req.url || "", `http://localhost:${port}`);

      if (url.pathname === "/sse") {
        console.error(`[Terminal MCP SSE] New SSE client connecting from ${req.socket.remoteAddress}`);
        const mcpServer = createMcpServer();
        const transport = new SSEServerTransport("/message", res);
        transports.set(transport.sessionId, transport);

        transport.onclose = () => {
          console.error(`[Terminal MCP SSE] Session ${transport.sessionId} closed`);
          transports.delete(transport.sessionId);
        };

        await mcpServer.connect(transport);
        return;
      }

      if (url.pathname === "/message") {
        const sessionId = url.searchParams.get("sessionId");
        if (!sessionId || !transports.has(sessionId)) {
          res.writeHead(400, { "Content-Type": "text/plain" });
          res.end("Invalid or missing sessionId");
          return;
        }
        const transport = transports.get(sessionId)!;
        await transport.handlePostMessage(req, res);
        return;
      }

      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Terminal MCP Server: Use /sse for MCP connection");
    });

    httpServer.listen(port, () => {
      console.error(`[Terminal MCP Server] Running in SSE mode on http://localhost:${port}/sse`);
    });
  } else {
    // Stdio Mode (Default for Claude Desktop, Cursor, Windsurf, Continue, Zed)
    console.error("[Terminal MCP Server] Starting in Stdio mode...");
    const server = createMcpServer();
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("[Terminal MCP Server] Connected to stdio successfully.");
  }
}

main().catch((err) => {
  console.error("[Terminal MCP Server] Fatal error:", err);
  process.exit(1);
});
