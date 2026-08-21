import assert from "node:assert/strict";
import {
	ARM_PERCENT,
	RESET_PERCENT,
	classifySessionScope,
	decideCompaction,
	nextArmedState,
} from "../extensions/workflow-context-economy.ts";

assert.equal(
	classifySessionScope({
		hasUI: true,
		mode: "tui",
		sessionFile: "/tmp/sessions/main.jsonl",
		parentSessionFileExists: false,
	}),
	"main",
);
assert.equal(
	classifySessionScope({
		hasUI: true,
		mode: "tui",
		sessionFile: "/tmp/sessions/main/coder.jsonl",
		parentSessionFileExists: true,
	}),
	"subagent",
);
assert.equal(
	classifySessionScope({
		hasUI: false,
		mode: "print",
		sessionFile: "/tmp/sessions/main/coder.jsonl",
		parentSessionFileExists: false,
	}),
	"headless",
);

assert.equal(nextArmedState(ARM_PERCENT - 0.1, false), false);
assert.equal(nextArmedState(ARM_PERCENT, false), true);
assert.equal(nextArmedState(20, true), true);
assert.equal(nextArmedState(RESET_PERCENT, true), false);

const base = {
	armed: true,
	compacting: false,
	invoking: false,
	willContinue: false,
	idle: true,
	workerCount: 0,
	asyncJobCount: 0,
	pendingMessages: false,
	lastCompactionAt: 0,
	now: 100_000,
	percent: 26.5,
};

assert.deepEqual(decideCompaction({ ...base, workerCount: 1 }), {
	shouldCompact: false,
	phase: "waiting-worker",
	reason: "1 worker/asynchronous job(s) remain active; Main will wait without touching worker context",
});
assert.equal(decideCompaction({ ...base, idle: false }).phase, "waiting-main");
assert.equal(decideCompaction({ ...base, pendingMessages: true }).phase, "waiting-queue");
assert.equal(decideCompaction({ ...base, compacting: true }).phase, "waiting-compaction");
assert.equal(decideCompaction({ ...base, armed: false }).shouldCompact, false);
assert.equal(decideCompaction(base).shouldCompact, true);

console.log("workflow-context-economy Main-only selftest: PASS");

async function extensionScopeIntegration(): Promise<void> {
	function harness() {
		const handlers = new Map<string, Array<(event: any, ctx: any) => any>>();
		const bus = new Map<string, Array<(payload: any) => any>>();
		let activeTools = ["read", "workflow_context"];
		const notices: string[] = [];
		let intervalCount = 0;
		let compactCount = 0;
		let percent = 26.5;
		let tokens = 265_000;
		let idle = false;
		const pi: any = {
			zod: { object: () => ({}) },
			logger: { debug: () => undefined },
			events: {
				on(name: string, handler: (payload: any) => any) {
					bus.set(name, [...(bus.get(name) ?? []), handler]);
				},
			},
			on(name: string, handler: (event: any, ctx: any) => any) {
				handlers.set(name, [...(handlers.get(name) ?? []), handler]);
			},
			registerTool: () => undefined,
			registerCommand: () => undefined,
			getActiveTools: () => [...activeTools],
			setActiveTools: async (tools: string[]) => {
				activeTools = [...tools];
			},
		};
		const context: any = {
			hasUI: true,
			mode: "tui",
			cwd: "/tmp/context-economy-selftest",
			sessionManager: { getSessionFile: () => "/tmp/context-economy-selftest/main.jsonl" },
			ui: {
				setStatus: () => undefined,
				notify: (message: string) => notices.push(message),
			},
			getContextUsage: () => ({ tokens, contextWindow: 1_000_000, percent }),
			getAsyncJobSnapshot: () => ({ running: [] }),
			isIdle: () => idle,
			hasPendingMessages: () => false,
			setInterval: () => {
				intervalCount += 1;
				return {};
			},
			setTimeout: (callback: () => void) => {
				callback();
				return {};
			},
			compact: async (options: any) => {
				compactCount += 1;
				tokens = 100_000;
				percent = 10;
				options?.onComplete?.({});
			},
		};
		return {
			pi,
			context,
			handlers,
			bus,
			notices,
			get activeTools() {
				return activeTools;
			},
			get intervalCount() {
				return intervalCount;
			},
			get compactCount() {
				return compactCount;
			},
			setIdle(value: boolean) {
				idle = value;
			},
		};
	}

	const extension = (await import("../extensions/workflow-context-economy.ts")).default;

	const worker = harness();
	worker.context.hasUI = false;
	worker.context.mode = "print";
	worker.context.sessionManager.getSessionFile = () => "/tmp/context-economy-selftest/main/coder.jsonl";
	extension(worker.pi);
	await worker.handlers.get("session_start")?.[0]?.({ type: "session_start" }, worker.context);
	assert.equal(worker.intervalCount, 0, "worker must not schedule the compaction monitor");
	assert.equal(worker.compactCount, 0, "worker must never invoke compaction");
	assert.equal(worker.activeTools.includes("workflow_context"), false, "worker tool must be deactivated");
	assert.equal(worker.notices.length, 0, "worker must show no context-economy warning");

	const main = harness();
	extension(main.pi);
	await main.handlers.get("session_start")?.[0]?.({ type: "session_start" }, main.context);
	await new Promise(resolve => setTimeout(resolve, 0));
	assert.equal(main.intervalCount, 1, "Main must schedule one monitor");
	assert.equal(main.compactCount, 0, "busy Main must not compact immediately");
	main.bus.get("task:subagent:lifecycle")?.[0]?.({ id: "coder-1", agent: "workflow-coder", status: "started" });
	main.setIdle(true);
	await main.handlers.get("turn_end")?.[0]?.({ type: "turn_end" }, main.context);
	await new Promise(resolve => setTimeout(resolve, 0));
	assert.equal(main.compactCount, 0, "Main must wait while the worker is active");
	assert.ok(main.notices.some(message => message.includes("Worker context remains untouched")));
	main.bus.get("task:subagent:lifecycle")?.[0]?.({ id: "coder-1", agent: "workflow-coder", status: "completed" });
	await main.handlers.get("turn_end")?.[0]?.({ type: "turn_end" }, main.context);
	await new Promise(resolve => setTimeout(resolve, 0));
	assert.equal(main.compactCount, 1, "Main must compact after the worker settles");
	assert.ok(main.notices.some(message => message.includes("starting Main-only shake -> soft compaction")));
}

await extensionScopeIntegration();
console.log("workflow-context-economy session-scope integration: PASS");
