import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

export const ARM_PERCENT = 23;
export const HARD_PERCENT = 28;
export const RESET_PERCENT = 18;
const COOLDOWN_MS = 60_000;
const CHECK_INTERVAL_MS = 5_000;

const STATE_PATH = "AI_Workflow_Kit/docs/AI/STATE.yaml";
const STEPS_PATH = "AI_Workflow_Kit/docs/STEPS.md";
const DECISIONS_PATH = "AI_Workflow_Kit/docs/DECISIONS.md";
const TOOL_NAME = "workflow_context";
const STATUS_KEY = "workflow-context-economy";

export type SessionScope = "unknown" | "main" | "subagent" | "headless";

type Worker = {
	id: string;
	agent: string;
	status: string;
	model?: string;
	task?: string;
	updatedAt: number;
};

type Phase =
	| "disabled"
	| "monitoring"
	| "armed"
	| "waiting-main"
	| "waiting-worker"
	| "waiting-queue"
	| "waiting-compaction"
	| "cooldown"
	| "starting"
	| "complete"
	| "error";

type Runtime = {
	scope: SessionScope;
	armed: boolean;
	compacting: boolean;
	invoking: boolean;
	phase: Phase;
	reason: string;
	lastBeforeTokens?: number;
	lastAfterTokens?: number;
	lastCompactionAt: number;
	lastError?: string;
	lastHumanInstruction: string;
	armNoticeShown: boolean;
	waitingWorkerNoticeShown: boolean;
	startingNoticeShown: boolean;
	completionNoticeShown: boolean;
};

export type CompactionDecisionInput = {
	armed: boolean;
	compacting: boolean;
	invoking: boolean;
	willContinue: boolean;
	idle: boolean;
	workerCount: number;
	asyncJobCount: number;
	pendingMessages: boolean;
	lastCompactionAt: number;
	now: number;
	percent: number;
};

export type CompactionDecision = {
	shouldCompact: boolean;
	phase: Phase;
	reason: string;
};

function freshRuntime(scope: SessionScope = "unknown"): Runtime {
	return {
		scope,
		armed: false,
		compacting: false,
		invoking: false,
		phase: scope === "main" || scope === "unknown" ? "monitoring" : "disabled",
		reason: scope === "main" || scope === "unknown" ? "waiting for Main context usage" : "disabled outside Main",
		lastCompactionAt: 0,
		lastHumanInstruction: "",
		armNoticeShown: false,
		waitingWorkerNoticeShown: false,
		startingNoticeShown: false,
		completionNoticeShown: false,
	};
}

/**
 * OMP task sessions are headless and persist below the parent session's artifact
 * directory. A child file `<parent>/<agent>.jsonl` therefore has a matching
 * parent session file at `<parent>.jsonl`. UI availability is the conservative
 * fallback: context economy runs only in the top-level interactive Main session.
 */
export function classifySessionScope(input: {
	hasUI: boolean;
	mode: string;
	sessionFile?: string;
	parentSessionFileExists: boolean;
}): SessionScope {
	if (input.sessionFile && input.parentSessionFileExists) return "subagent";
	if (input.hasUI && input.mode === "tui") return "main";
	return "headless";
}

function detectSessionScope(ctx: ExtensionContext): SessionScope {
	let sessionFile: string | undefined;
	try {
		sessionFile = ctx.sessionManager.getSessionFile();
	} catch {
		sessionFile = undefined;
	}
	let parentSessionFileExists = false;
	if (sessionFile) {
		try {
			parentSessionFileExists = existsSync(`${dirname(resolve(sessionFile))}.jsonl`);
		} catch {
			parentSessionFileExists = false;
		}
	}
	return classifySessionScope({
		hasUI: ctx.hasUI,
		mode: ctx.mode,
		sessionFile,
		parentSessionFileExists,
	});
}

export function nextArmedState(percent: number, armed: boolean): boolean {
	if (percent <= RESET_PERCENT) return false;
	if (percent >= ARM_PERCENT) return true;
	return armed;
}

export function decideCompaction(input: CompactionDecisionInput): CompactionDecision {
	if (!input.armed) {
		return {
			shouldCompact: false,
			phase: "monitoring",
			reason: `Main context ${input.percent.toFixed(1)}% is below the ${ARM_PERCENT}% arm threshold`,
		};
	}
	if (input.compacting || input.invoking) {
		return { shouldCompact: false, phase: "waiting-compaction", reason: "a Main compaction is already running" };
	}
	const activeWork = Math.max(input.workerCount, input.asyncJobCount);
	if (activeWork > 0) {
		return {
			shouldCompact: false,
			phase: "waiting-worker",
			reason: `${activeWork} worker/asynchronous job(s) remain active; Main will wait without touching worker context`,
		};
	}
	if (input.willContinue || !input.idle) {
		return { shouldCompact: false, phase: "waiting-main", reason: "Main has not settled at an idle boundary" };
	}
	if (input.pendingMessages) {
		return { shouldCompact: false, phase: "waiting-queue", reason: "queued Main messages are waiting" };
	}
	const elapsed = Math.max(0, input.now - input.lastCompactionAt);
	if (input.lastCompactionAt > 0 && elapsed < COOLDOWN_MS) {
		return {
			shouldCompact: false,
			phase: "cooldown",
			reason: `Main compaction cooldown has ${Math.ceil((COOLDOWN_MS - elapsed) / 1000)}s remaining`,
		};
	}
	return {
		shouldCompact: true,
		phase: "armed",
		reason:
			input.percent >= HARD_PERCENT
				? `Main context passed the ${HARD_PERCENT}% upper target and the session is now safe`
				: `Main context is inside the ${ARM_PERCENT}-${HARD_PERCENT}% window and the session is safe`,
	};
}

function asyncJobsRunning(ctx: ExtensionContext): number {
	try {
		return ctx.getAsyncJobSnapshot()?.running.length ?? 0;
	} catch {
		return 0;
	}
}

function formatTokens(value: number | undefined): string {
	if (!value || value <= 0) return "0";
	if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(value >= 10_000_000 ? 0 : 2)}m`;
	if (value >= 1_000) return `${(value / 1_000).toFixed(value >= 100_000 ? 0 : 1)}k`;
	return String(Math.round(value));
}

function cleanScalar(value: string | undefined): string {
	if (!value) return "";
	const stripped = value.trim().replace(/\s+#.*$/, "").trim();
	if ((stripped.startsWith('"') && stripped.endsWith('"')) || (stripped.startsWith("'") && stripped.endsWith("'"))) {
		return stripped.slice(1, -1);
	}
	return stripped === "null" || stripped === "~" ? "" : stripped;
}

function scalar(source: string, key: string): string {
	const match = source.match(new RegExp(`^${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:\\s*(.*?)\\s*$`, "m"));
	return cleanScalar(match?.[1]);
}

function section(source: string, name: string): string {
	const lines = source.split(/\r?\n/);
	let start = -1;
	let indent = 0;
	for (let index = 0; index < lines.length; index++) {
		const match = lines[index].match(/^(\s*)([A-Za-z0-9_.-]+):\s*(?:#.*)?$/);
		if (match?.[2] === name) {
			start = index + 1;
			indent = match[1].length;
			break;
		}
	}
	if (start < 0) return "";
	const body: string[] = [];
	for (let index = start; index < lines.length; index++) {
		const line = lines[index];
		if (line.trim() && line.length - line.trimStart().length <= indent) break;
		body.push(line);
	}
	return body.join("\n");
}

function sectionScalar(source: string, name: string, key: string): string {
	const body = section(source, name);
	const match = body.match(new RegExp(`^\\s+${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:\\s*(.*?)\\s*$`, "m"));
	return cleanScalar(match?.[1]);
}

function compactText(value: string, max = 600): string {
	const normalized = value.replace(/\s+/g, " ").trim();
	return normalized.length <= max ? normalized : `${normalized.slice(0, max - 1)}…`;
}

function openItems(steps: string, currentStep: string): string[] {
	const lines = steps.split(/\r?\n/);
	let inside = false;
	const output: string[] = [];
	for (const line of lines) {
		const heading = line.match(/^##\s+([^\s—-]+)\s*(?:—|-)\s*(.+?)\s*$/);
		if (heading) {
			inside = heading[1] === currentStep;
			continue;
		}
		if (!inside) continue;
		const item = line.match(/^\s*-\s*\[ \]\s*(?:\[([^\]]+)\]\s*)?(.*?)\s*$/);
		if (!item) continue;
		const rendered = item[1] ? `[${item[1]}] ${item[2]}` : item[2];
		if (rendered.trim()) output.push(compactText(rendered, 240));
		if (output.length >= 16) break;
	}
	return output;
}

async function readCanonical(cwd: string, relative: string): Promise<{ text: string; error?: string }> {
	try {
		return { text: await readFile(`${cwd}/${relative}`, "utf8") };
	} catch (error) {
		return { text: "", error: `${relative}: ${error instanceof Error ? error.message : String(error)}` };
	}
}

function hash(value: string): string {
	return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

function anchor(snapshot: Record<string, unknown>): string[] {
	const canonical = snapshot.canonical as Record<string, unknown>;
	const runtimeView = snapshot.runtime as Record<string, unknown>;
	const hashes = snapshot.canonical_hashes as Record<string, unknown>;
	const items = Array.isArray(snapshot.open_items) ? snapshot.open_items.slice(0, 12).join(" | ") : "";
	return [
		"Authoritative Main-workflow anchor (navigation only; verify against files before changing state or gates):",
		`step=${canonical.current_step}; work_item=${canonical.current_work_item_id || "-"}; next_actor=${canonical.next_actor}`,
		`implementation=${canonical.implementation_status}; review=${canonical.review_status}; qa=${canonical.qa_status}; blocker=${canonical.blocker || "none"}`,
		`active_workers=${JSON.stringify(runtimeView.workers ?? [])}; async_jobs=${runtimeView.async_jobs_running ?? 0}`,
		`open_items=${items || "none parsed"}`,
		`last_human_instruction=${runtimeView.last_human_instruction || "none captured"}`,
		`hashes=state:${hashes.state},steps:${hashes.steps},decisions:${hashes.decisions}`,
		"This compaction belongs only to the top-level Main session. Worker sessions retain their full assignment context.",
		"Conversation history and this anchor are non-authoritative. Canonical workflow files, repository source, diff, tests, and artifacts win.",
	];
}

export default function workflowContextEconomy(pi: ExtensionAPI): void {
	const z = pi.zod;
	const workers = new Map<string, Worker>();
	let runtime = freshRuntime();
	let scope: SessionScope = "unknown";

	function activeWorkers(): Worker[] {
		return [...workers.values()]
			.filter(worker => ["started", "pending", "running"].includes(worker.status))
			.sort((left, right) => right.updatedAt - left.updatedAt);
	}

	function refreshScope(ctx: ExtensionContext): boolean {
		scope = detectSessionScope(ctx);
		runtime.scope = scope;
		if (scope !== "main") {
			runtime.armed = false;
			runtime.phase = "disabled";
			runtime.reason = scope === "subagent" ? "disabled in worker/subagent sessions" : "disabled outside interactive Main";
		}
		return scope === "main";
	}

	async function deactivateWorkerTool(): Promise<void> {
		try {
			const active = pi.getActiveTools();
			if (active.includes(TOOL_NAME)) await pi.setActiveTools(active.filter(name => name !== TOOL_NAME));
		} catch (error) {
			pi.logger.debug("Could not deactivate workflow_context outside Main", {
				error: error instanceof Error ? error.message : String(error),
			});
		}
	}

	function updateStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI || scope !== "main") {
			if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
			return;
		}
		const usage = ctx.getContextUsage();
		if (!usage) {
			ctx.ui.setStatus(STATUS_KEY, "MAIN ctx unavailable · main-only");
			return;
		}
		const state = runtime.compacting || runtime.invoking ? "compacting" : runtime.armed ? runtime.phase : "monitoring";
		ctx.ui.setStatus(STATUS_KEY, `MAIN ctx ${usage.percent.toFixed(1)}% · ${state} · 23-28%`);
	}

	function resetNotices(): void {
		runtime.armNoticeShown = false;
		runtime.waitingWorkerNoticeShown = false;
		runtime.startingNoticeShown = false;
		runtime.completionNoticeShown = false;
	}

	function notifyArmed(ctx: ExtensionContext, percent: number, decision: CompactionDecision, newlyArmed: boolean): void {
		if (!ctx.hasUI || scope !== "main") return;
		if (newlyArmed && !runtime.armNoticeShown) {
			const suffix = decision.phase === "waiting-worker"
				? " It will wait for the active worker; worker context will not be compacted or interrupted."
				: " It will run at the next safe Main idle boundary.";
			ctx.ui.notify(
				`Main context ${percent.toFixed(1)}%: Main-only compaction armed (${ARM_PERCENT}-${HARD_PERCENT}%).${suffix}`,
				"warning",
			);
			runtime.armNoticeShown = true;
			if (decision.phase === "waiting-worker") runtime.waitingWorkerNoticeShown = true;
		}
		if (decision.phase === "waiting-worker" && !runtime.waitingWorkerNoticeShown) {
			ctx.ui.notify(
				`Main context ${percent.toFixed(1)}% is waiting for the worker to finish before compaction. Worker context remains untouched.`,
				"warning",
			);
			runtime.waitingWorkerNoticeShown = true;
		}
	}

	async function captureAfter(ctx: ExtensionContext): Promise<void> {
		if (!refreshScope(ctx)) return;
		const usage = ctx.getContextUsage();
		if (usage) {
			runtime.lastAfterTokens = usage.tokens;
			runtime.armed = nextArmedState(usage.percent, false);
			if (!runtime.armed) resetNotices();
			if (ctx.hasUI && runtime.lastBeforeTokens && !runtime.completionNoticeShown) {
				ctx.ui.notify(
					`Main context compacted: ${formatTokens(runtime.lastBeforeTokens)} -> ${formatTokens(runtime.lastAfterTokens)} (${usage.percent.toFixed(1)}%).`,
					"info",
				);
				runtime.completionNoticeShown = true;
			}
		}
		updateStatus(ctx);
	}

	async function evaluate(ctx: ExtensionContext, willContinue = false): Promise<void> {
		if (!refreshScope(ctx)) return;
		const usage = ctx.getContextUsage();
		if (!usage) {
			runtime.phase = "monitoring";
			runtime.reason = "Main context usage unavailable";
			updateStatus(ctx);
			return;
		}
		const wasArmed = runtime.armed;
		runtime.armed = nextArmedState(usage.percent, runtime.armed);
		if (usage.percent <= RESET_PERCENT) resetNotices();
		const decision = decideCompaction({
			armed: runtime.armed,
			compacting: runtime.compacting,
			invoking: runtime.invoking,
			willContinue,
			idle: ctx.isIdle(),
			workerCount: activeWorkers().length,
			asyncJobCount: asyncJobsRunning(ctx),
			pendingMessages: ctx.hasPendingMessages(),
			lastCompactionAt: runtime.lastCompactionAt,
			now: Date.now(),
			percent: usage.percent,
		});
		runtime.phase = decision.phase;
		runtime.reason = decision.reason;
		notifyArmed(ctx, usage.percent, decision, !wasArmed && runtime.armed);
		updateStatus(ctx);
		if (!decision.shouldCompact || runtime.invoking || runtime.compacting) return;

		runtime.invoking = true;
		runtime.phase = "starting";
		runtime.reason = "starting Main-only configured shake -> soft compaction at a safe boundary";
		runtime.lastBeforeTokens = usage.tokens;
		runtime.lastAfterTokens = undefined;
		runtime.lastError = undefined;
		runtime.completionNoticeShown = false;
		if (ctx.hasUI && !runtime.startingNoticeShown) {
			ctx.ui.notify(
				`Main context ${usage.percent.toFixed(1)}%: starting Main-only shake -> soft compaction.`,
				"warning",
			);
			runtime.startingNoticeShown = true;
		}
		updateStatus(ctx);
		try {
			await ctx.compact({
				internalGuidance:
					"Compact only the top-level Main Orchestrator history. Preserve the workflow anchor, exact Human intent, accepted decisions, open gates, active role routing, and source-of-truth paths.",
				onComplete: () => {
					runtime.lastCompactionAt = Date.now();
					runtime.phase = "complete";
					runtime.reason = "Main-only floating compaction completed";
				},
				onError: error => {
					runtime.phase = "error";
					runtime.reason = "Main-only floating compaction failed";
					runtime.lastError = error.message;
					if (ctx.hasUI) ctx.ui.notify(`Main compaction failed: ${error.message}`, "error");
				},
			});
		} catch (error) {
			runtime.phase = "error";
			runtime.reason = "Main-only floating compaction threw before completion";
			runtime.lastError = error instanceof Error ? error.message : String(error);
			if (ctx.hasUI) ctx.ui.notify(`Main compaction failed: ${runtime.lastError}`, "error");
		} finally {
			runtime.invoking = false;
			ctx.setTimeout(() => void captureAfter(ctx), 300);
			updateStatus(ctx);
		}
	}

	async function workflowSnapshot(ctx: ExtensionContext): Promise<Record<string, unknown>> {
		const [stateFile, stepsFile, decisionsFile] = await Promise.all([
			readCanonical(ctx.cwd, STATE_PATH),
			readCanonical(ctx.cwd, STEPS_PATH),
			readCanonical(ctx.cwd, DECISIONS_PATH),
		]);
		const state = stateFile.text;
		const currentStep = scalar(state, "current_step") || "-";
		const usage = ctx.getContextUsage();
		return {
			schema_version: 3,
			generated_at: new Date().toISOString(),
			scope: {
				current: scope,
				policy: "top-level-interactive-main-only",
				worker_auto_compaction: false,
			},
			canonical: {
				current_step: currentStep,
				current_work_item_id: scalar(state, "current_work_item_id"),
				current_work_item: scalar(state, "current_work_item"),
				next_actor: scalar(state, "next_actor") || "orchestrator",
				implementation_status: sectionScalar(state, "implementation", "status") || "unknown",
				review_status: sectionScalar(state, "review", "status") || "unknown",
				qa_status: sectionScalar(state, "qa", "status") || "unknown",
				active_agent: sectionScalar(state, "omp", "active_agent"),
				active_role: sectionScalar(state, "omp", "active_role"),
				blocker: sectionScalar(state, "retry_guard", "blocker"),
			},
			open_items: openItems(stepsFile.text, currentStep),
			runtime: {
				workers: activeWorkers(),
				async_jobs_running: asyncJobsRunning(ctx),
				last_human_instruction: compactText(runtime.lastHumanInstruction, 800),
			},
			context: usage
				? { tokens: usage.tokens, context_window: usage.contextWindow, percent: Math.round(usage.percent * 10) / 10 }
				: null,
			compaction: {
				phase: runtime.phase,
				reason: runtime.reason,
				armed: runtime.armed,
				compacting: runtime.compacting || runtime.invoking,
				last_before_tokens: runtime.lastBeforeTokens,
				last_after_tokens: runtime.lastAfterTokens,
				last_error: runtime.lastError,
			},
			canonical_hashes: {
				state: hash(stateFile.text),
				steps: hash(stepsFile.text),
				decisions: hash(decisionsFile.text),
			},
			read_errors: [stateFile.error, stepsFile.error, decisionsFile.error].filter(Boolean),
		};
	}

	function statusText(ctx: ExtensionContext): string {
		const usage = ctx.getContextUsage();
		const beforeAfter = runtime.lastBeforeTokens
			? `\nLast compact: ${formatTokens(runtime.lastBeforeTokens)} -> ${formatTokens(runtime.lastAfterTokens)}`
			: "";
		return [
			`Scope: ${scope} · policy=top-level Main only`,
			"Worker auto-compaction: disabled",
			`Main context: ${usage ? `${usage.percent.toFixed(1)}% (${formatTokens(usage.tokens)}/${formatTokens(usage.contextWindow)})` : "unavailable"}`,
			`Floating window: arm ${ARM_PERCENT}% · upper target ${HARD_PERCENT}% · reset ${RESET_PERCENT}%`,
			`State: ${runtime.phase} · armed=${runtime.armed} · compacting=${runtime.compacting || runtime.invoking}`,
			`Reason: ${runtime.reason}`,
			`Active workers: ${activeWorkers().map(worker => `${worker.agent}:${worker.status}`).join(", ") || "none"}`,
			`Async jobs: ${asyncJobsRunning(ctx)}${beforeAfter}`,
			runtime.lastError ? `Last error: ${runtime.lastError}` : "",
		].filter(Boolean).join("\n");
	}

	pi.events.on("task:subagent:progress", payload => {
		if (scope !== "main") return;
		const progress = (payload as { progress?: Partial<Worker> }).progress;
		if (!progress?.id) return;
		const previous = workers.get(progress.id);
		workers.set(progress.id, {
			id: progress.id,
			agent: progress.agent ?? previous?.agent ?? "subagent",
			status: progress.status ?? previous?.status ?? "running",
			model: progress.model ?? previous?.model,
			task: progress.task ?? previous?.task,
			updatedAt: Date.now(),
		});
	});
	pi.events.on("task:subagent:lifecycle", payload => {
		if (scope !== "main") return;
		const event = payload as {
			id?: string;
			agent?: string;
			status?: string;
			resolvedModel?: string;
			task?: string;
		};
		if (!event.id) return;
		const previous = workers.get(event.id);
		const status = event.status === "started" ? "running" : (event.status ?? previous?.status ?? "running");
		workers.set(event.id, {
			id: event.id,
			agent: event.agent ?? previous?.agent ?? "subagent",
			status,
			model: event.resolvedModel ?? previous?.model,
			task: event.task ?? previous?.task,
			updatedAt: Date.now(),
		});
		if (!["started", "pending", "running"].includes(status)) {
			setTimeout(() => workers.delete(event.id!), 30_000).unref?.();
		}
	});

	pi.registerTool({
		name: TOOL_NAME,
		label: "Workflow Context",
		description:
			"Main-only: read a compact, non-authoritative index of workflow state, open items, active workers, Main context usage, and canonical file hashes. Verify against canonical files and real source before changing state.",
		parameters: z.object({}),
		approval: "read",
		loadMode: "essential",
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			if (!refreshScope(ctx)) {
				return {
					content: [{ type: "text", text: "workflow_context is disabled outside the top-level interactive Main session." }],
					details: { scope, enabled: false },
				};
			}
			const snapshot = await workflowSnapshot(ctx);
			return {
				content: [{ type: "text", text: JSON.stringify(snapshot, null, 2) }],
				details: snapshot,
			};
		},
	});

	pi.registerCommand("workflow-context", {
		description: "Show a compact Main workflow context snapshot",
		handler: async (_args, ctx) => {
			if (!refreshScope(ctx)) {
				ctx.ui.notify("workflow-context is disabled outside the top-level interactive Main session.", "warning");
				return;
			}
			ctx.ui.notify(JSON.stringify(await workflowSnapshot(ctx), null, 2), "info");
		},
	});
	pi.registerCommand("workflow-context-economy", {
		description: "Show Main-only floating compaction state without changing the session",
		handler: async (_args, ctx) => {
			refreshScope(ctx);
			ctx.ui.notify(statusText(ctx), runtime.lastError ? "warning" : "info");
		},
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!refreshScope(ctx)) return;
		if (event.prompt?.trim()) runtime.lastHumanInstruction = event.prompt.trim();
		updateStatus(ctx);
	});
	pi.on("session_start", async (_event, ctx) => {
		scope = detectSessionScope(ctx);
		workers.clear();
		runtime = freshRuntime(scope);
		if (scope !== "main") {
			await deactivateWorkerTool();
			updateStatus(ctx);
			return;
		}
		updateStatus(ctx);
		ctx.setInterval(() => void evaluate(ctx), CHECK_INTERVAL_MS);
		void evaluate(ctx);
	});
	pi.on("session_switch", async (_event, ctx) => {
		scope = detectSessionScope(ctx);
		workers.clear();
		runtime = freshRuntime(scope);
		if (scope !== "main") {
			await deactivateWorkerTool();
			updateStatus(ctx);
			return;
		}
		updateStatus(ctx);
		void evaluate(ctx);
	});
	pi.on("turn_end", async (_event, ctx) => {
		if (scope === "main") void evaluate(ctx);
	});
	pi.on("agent_end", async (event, ctx) => {
		if (scope === "main") void evaluate(ctx, event.willContinue === true);
	});
	pi.on("auto_compaction_start", async (_event, ctx) => {
		if (!refreshScope(ctx)) return;
		runtime.compacting = true;
		runtime.phase = "starting";
		runtime.reason = "Main automatic compaction started";
		runtime.lastBeforeTokens = ctx.getContextUsage()?.tokens;
		updateStatus(ctx);
	});
	pi.on("auto_compaction_end", async (event, ctx) => {
		if (!refreshScope(ctx)) return;
		runtime.compacting = false;
		if (event.result) {
			runtime.lastCompactionAt = Date.now();
			runtime.phase = "complete";
			runtime.reason = "Main automatic compaction completed";
		} else if (event.errorMessage) {
			runtime.phase = "error";
			runtime.reason = "Main automatic compaction failed";
			runtime.lastError = event.errorMessage;
		}
		ctx.setTimeout(() => void captureAfter(ctx), 300);
		updateStatus(ctx);
	});
	pi.on("session_compact", async (event, ctx) => {
		if (!refreshScope(ctx)) return;
		runtime.compacting = false;
		runtime.invoking = false;
		runtime.lastCompactionAt = Date.now();
		runtime.lastBeforeTokens = event.compactionEntry.tokensBefore ?? runtime.lastBeforeTokens;
		runtime.phase = "complete";
		runtime.reason = "Main session compaction entry persisted";
		ctx.setTimeout(() => void captureAfter(ctx), 300);
		updateStatus(ctx);
	});
	pi.on("session.compacting", async (_event, ctx) => {
		if (!refreshScope(ctx)) return;
		return {
			context: anchor(await workflowSnapshot(ctx)),
			preserveData: {
				workflowContextEconomy: {
					schemaVersion: 3,
					scope: "main-only",
					workerAutoCompaction: false,
					armPercent: ARM_PERCENT,
					hardPercent: HARD_PERCENT,
				},
			},
		};
	});
	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
	});
}
