# VaniScript — Cloud Provider Stabilization: Architectural Specification

> Стабилизация вкладки **API & Usage** в нативном Apple Silicon приложении после
> завершённого трека `API_USAGE`. Документ охватывает только наблюдения
> `OBS-001…OBS-005`: Qwen credential profiles, role-кнопки, model-level capabilities,
> price/context metadata, Anthropic и Custom routing.
>
> **Track:** `CLOUD_PROVIDER_STABILIZATION`
>
> **Status:** architecture ready; implementation not started
>
> **Companion:** `CLOUD_PROVIDER_STABILIZATION_STEPS.md`,
> `DECISIONS.md` (`D-2026-07-27-CLOUD_PROVIDER_STABILIZATION`)

## 1. Scope

### In scope

1. Один Qwen credential/profile, применяемый во всех совместимых native-поверхностях:
   validation, model discovery, translation/editing и embedded Qwen CLI chat.
2. Разделение Qwen Pay-as-you-go и Token Plan endpoint profiles.
3. Единая политика доступности ролей `transcription` / `translation`.
4. Model-level capabilities вместо одного provider-wide Boolean.
5. Контекстное окно и input/output price рядом с выбранной моделью.
6. Полноценный text translation routing для Anthropic и Custom providers.
7. Model-aware OpenRouter transcription только через реально подтверждённый audio route.
8. Regression tests и ручной black-box UI acceptance для `OBS-001…OBS-005`.

### Out of scope

- Electron.
- Изменение MCP protocol, MCP tools, scopes, ports или permission model.
- Codex/Grok behavior.
- Local WhisperKit/MLX routing.
- Usage aggregation и OpenRouter balance, уже реализованные треком `API_USAGE`.
- Автоматический runtime scraping HTML-страниц с ценами.
- Включение transcription для модели/тарифа без подтверждённого audio contract.
- Попутный redesign Settings.

## 2. Observation registry

| ID | Наблюдение | Root cause status | Severity |
|---|---|---|---|
| `OBS-001` | Активный Qwen Token Plan key не принимается | `VERIFIED` | High |
| `OBS-002` | `Use for Translation` не переключает OpenRouter/generic card | `UNKNOWN` до CPS-01 | High |
| `OBS-003` | Transcription capability задана на уровне provider, не model/route | `VERIFIED` | High |
| `OBS-004` | У модели нет context window и input/output price | `VERIFIED` | Medium |
| `OBS-005` | Anthropic/Custom видны в UI, но не подключены к workflow | `VERIFIED` | High |

## 3. As-is evidence

### 3.1 Qwen endpoint drift (`OBS-001`)

- `CloudModelCatalog.listRequest` фиксирует Qwen models URL на общем
  `dashscope-intl.aliyuncs.com`.
- `CloudChatRouter.route` отдельно фиксирует общий DashScope
  `chat/completions` URL.
- Qwen API key, model и embedded Qwen model хранятся раздельно.
- `QwenAgentService` запускает Qwen CLI и передаёт ему только MCP access token;
  API & Usage Qwen key/profile не является явным входом этого процесса.
- Token Plan со скриншота использует отдельный Singapore base URL. Alibaba
  документирует несовместимость API keys между billing/region profiles.

### 3.2 Role-selection split brain (`OBS-002`, `OBS-003`, `OBS-005`)

Решение о доступности и выборе роли сейчас распределено между:

1. `SettingsView.ProviderCardView` — `hasKey`, provider capability и локальное
   сравнение строковых provider ids.
2. `ProviderRegistry` — отдельный список доступных providers.
3. `WorkflowState.synchronizeProviderSelections` — перенос settings selection
   в текущий workflow/session.
4. `WorkflowStore.refreshProviderSelections` — повторная фильтрация после записи.
5. `CloudTextTranslationEngine` / `CloudAudioTranscriptionEngine` — фактические
   runtime cases.

UI может обещать роль, которую engine не умеет выполнить, либо блокировать роль,
для которой route уже существует. Для `OBS-002` статический анализ не объясняет
наблюдаемый no-op: при непустом OpenRouter key кнопка translation должна быть
enabled. До изменения поведения нужен воспроизводимый black-box сценарий CPS-01.

### 3.3 Model metadata loss (`OBS-003`, `OBS-004`)

`CloudModel` содержит только `id`. Парсер OpenAI-compatible `/models` отбрасывает:

- context window;
- input/output modalities;
- provider-specific capabilities;
- prompt/completion price;
- maximum completion tokens;
- metadata provenance/freshness.

OpenRouter уже отдаёт эти поля через Models API. Gemini Models API отдаёт
расширенные limits/methods. OpenAI и Anthropic list APIs главным образом отвечают
на вопрос доступности модели и не являются полным pricing catalog.

### 3.4 Incomplete provider cards (`OBS-005`)

- Anthropic card: API key + hardcoded read-only model; role buttons отсутствуют.
- Custom section: CRUD configuration; выбора workflow role нет.
- `ProviderRegistry` и `CloudChatRouter` не возвращают Anthropic/Custom
  translation routes.

## 4. Root-cause consolidation

### RC-01 — Endpoint profile is not a first-class concept

Provider id `qwen` ошибочно считается достаточным для построения всех URLs.
Credential kind, billing plan и region фактически являются частью API contract.

Затрагивает: `OBS-001`.

### RC-02 — Role availability has multiple sources of truth

Settings UI, registry, workflow synchronization и engines самостоятельно решают,
можно ли выбрать provider. Строковые ids и provider-wide flags не гарантируют,
что UI selection соответствует executable route.

Затрагивает: `OBS-002`, `OBS-003`, `OBS-005`.

### RC-03 — Model catalog is identity-only

Модель представлена строкой id. Нельзя корректно определить capability,
показать price/context или выбрать transcription route.

Затрагивает: `OBS-003`, `OBS-004`.

### RC-04 — Provider presence was mistaken for workflow integration

Anthropic и Custom находятся в каталоге/Settings, но translation engine route
для них не создан.

Затрагивает: `OBS-005`.

## 5. Architectural decisions

### 5.1 Endpoint profile

Добавить Core-level value type:

```swift
public struct CloudEndpointProfile: Codable, Equatable, Sendable {
    public var id: String
    public var providerID: String
    public var credentialKind: CloudCredentialKind
    public var region: String?
    public var modelsBaseURL: URL
    public var textGenerationBaseURL: URL
    public var embeddedCredentialEnvironmentKey: String?
}
```

Минимальный подтверждённый Qwen набор:

- `qwen-payg-international`;
- `qwen-token-plan-singapore`.

`AppSettings` получает migration-safe `qwenEndpointProfileID`; default сохраняет
текущее Pay-as-you-go поведение. Один resolver строит URLs для validation,
model discovery и text runtime. Дублирующие endpoint literals удаляются из
`CloudModelCatalog` и `CloudChatRouter`.

`automatic` разрешён только как UI convenience: определённый profile сохраняется
явно до первого request. Key prefix может быть hint, но не единственным API contract.

### 5.2 Universal Qwen configuration

Термин **universal** означает:

- пользователь настраивает один Qwen credential/profile;
- profile доступен validation, models, translation/editing и embedded Qwen CLI;
- secret передаётся embedded child process только через environment;
- profile не меняет MCP server/config/scopes;
- роль включается только при совместимости plan + model + implemented route.

Это не означает принудительное включение audio transcription для text-only Token
Plan. Неподдерживаемая роль остаётся disabled с точной причиной.

### 5.3 Rich model descriptor

Расширить identity-only `CloudModel` до:

```swift
public struct CloudModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String?
    public var contextWindowTokens: Int?
    public var maxOutputTokens: Int?
    public var inputPricePerMillion: Decimal?
    public var outputPricePerMillion: Decimal?
    public var capabilities: CloudModelCapabilities
    public var transcriptionRoute: CloudTranscriptionRouteKind?
    public var metadataSource: CloudModelMetadataSource
    public var metadataAsOf: Date?
}
```

Все enriched поля optional. `nil` отображается как `Not provided`, а не как zero.
Price хранится сразу в user-facing unit `USD / 1M tokens`, чтобы исключить
повторное масштабирование в UI.

`CloudModelCapabilities` различает минимум:

- text input;
- text output;
- audio input;
- transcription output;
- image/video input (для честного отображения, не для расширения scope).

`CloudTranscriptionRouteKind` различает:

- dedicated audio transcription endpoint;
- chat/generate-content with audio input and text output;
- unavailable.

Полный fetched model list остаётся session cache. Для согласованности UI, registry
и restart persistence сохраняется только non-secret snapshot выбранной модели:

```swift
public struct CloudModelSelectionSnapshot: Codable, Equatable, Sendable {
    public var providerID: String
    public var endpointProfileID: String?
    public var model: CloudModelDescriptor
}
```

`AppSettings.cloudModelSelectionSnapshots` использует ключ
`providerID:endpointProfileID`. Legacy string model fields остаются источником
совместимости; snapshot дополняет их capabilities/provenance. Manual model id
получает metadata source `manualUnknown`: text route может быть доступен, но
transcription не включается без подтверждённого route kind.

### 5.4 Metadata source hierarchy

1. Live provider metadata, если API возвращает нужное поле.
2. Версионированный bundled metadata snapshot для официально документированных
   моделей, если list API отдаёт только ids.
3. `Not provided`, если достоверного источника нет.

Каждое price/context значение несёт source и `asOf`. Runtime HTML scraping
запрещён: он хрупок и может молча показать неверную цену.

Provider-specific expectations:

| Provider | Live model list | Context/capability | Price |
|---|---|---|---|
| Gemini | API | API limits/methods + verified audio contract | bundled official snapshot where needed |
| OpenAI | API ids | bundled official model contract | bundled official snapshot |
| Anthropic | `/v1/models` | bundled official model contract | bundled official snapshot |
| Qwen | profile-specific API ids | profile allowlist + official capability snapshot | PAYG price or Token Plan Credits semantics |
| OpenRouter | `/api/v1/models` | live modalities/context | live prompt/completion price |
| Ollama Cloud | provider list | only returned/verified fields | `Not provided` unless official source exists |
| Custom | user-entered | explicit configuration only | existing user-entered values |

Token Plan Credits must never be labelled as PAYG `$ / 1M` unless Alibaba
publishes an equivalent unit for that plan/model.

### 5.5 One role policy

Добавить pure Core policy:

```swift
public enum CloudProviderRole: String, Codable, Sendable {
    case transcription
    case translation
}

public struct ProviderRoleAvailability: Equatable, Sendable {
    public var enabled: Bool
    public var reasonCode: String?
    public var message: String?
    public var effectiveModelID: String?
    public var routeKind: String?
}
```

`ProviderRolePolicy.resolve(...)` принимает:

- provider/profile;
- key presence;
- selected model metadata;
- registered runtime routes;
- target language.

Текущий validation result остаётся session-only connection state: `.invalid`
может дополнительно блокировать UI с точной ошибкой, но не записывается в
`AppSettings`. После restart сохранённый provider имеет состояние `.unverified`
до первой проверки, а не ошибочно `.valid`.

Один и тот же result используют:

- Settings buttons;
- `ProviderRegistry`;
- workflow/session synchronization guard;
- runtime preflight.

Инвариант:

> Если UI разрешает выбрать роль, registry обязан вернуть provider, а engine
> обязан построить executable route для того же effective model/profile.

Если роль disabled, UI показывает короткую причину, например:

- `API key required`;
- `Selected model is text-only`;
- `Token Plan does not include transcription`;
- `VaniScript has no verified audio route for this model`;
- `Translation is disabled because target language is Same`.

### 5.6 Provider routing completion

#### Anthropic

- Model discovery: Anthropic `/v1/models`.
- Translation/editing: Messages API adapter.
- Transcription: unavailable.
- No silent OpenAI-compatible emulation.

#### Custom

- Translation/editing: existing `baseUrl`, key and model through a constrained
  OpenAI-compatible chat adapter.
- Transcription: unavailable in this track unless a future explicit audio
  protocol enum is added.
- Invalid URL/protocol produces a preflight error; no request is sent.

#### OpenRouter transcription

- Enabled per selected model, not globally.
- Route kind selected from verified metadata/contract.
- Unsupported model remains disabled.
- Existing Gemini/OpenAI transcription behavior remains unchanged.

## 6. Target flow

```text
API & Usage
  └─ ProviderCard
      ├─ credential + endpoint profile
      ├─ CloudModelCatalog -> CloudModelDescriptor
      ├─ compact metadata line
      └─ ProviderRolePolicy
          ├─ Translation button
          └─ Transcription button + disabled reason

ProviderRolePolicy
  ├─ ProviderRegistry
  ├─ WorkflowState / WorkflowStore synchronization
  └─ runtime route preflight

CloudEndpointProfileResolver
  ├─ CloudKeyValidator
  ├─ CloudModelCatalog
  ├─ CloudChatRouter / provider-specific text adapters
  └─ QwenAgentService child environment
```

## 7. Compact UI contract

Provider card must not grow into a large model inspector.

Under the model picker, render at most two compact lines:

```text
Context 1M   Input $0.30/M   Output $2.50/M
Audio input • Text output
```

Rules:

1. Unknown fields are omitted or shown as `—`; never fabricated.
2. Tooltip/details may show source and `asOf`.
3. Disabled role remains visible and explains why.
4. Active role uses the existing orange selected style.
5. A successful click must update:
   - button state;
   - card header badge;
   - Cloud API Usage summary;
   - persisted settings;
   - active workflow/session when applicable.
6. If transcription uses a different effective audio model, show its id next to
   the role rather than implying that the text model is used.

## 8. Persistence and migration

- Existing API keys and selected text models remain readable.
- New settings fields use `decodeIfPresent`.
- `cloudModelSelectionSnapshots` хранит только metadata выбранных моделей; API
  keys и Authorization headers в snapshots запрещены.
- Default Qwen profile maps legacy installations to the current Pay-as-you-go
  international endpoint; no secret migration.
- Existing provider ids remain stable to preserve usage keys and saved projects.
- Custom provider ids remain stable.
- No key is written to logs, fixtures, screenshots or ADR.

## 9. Test architecture

### Unit

- endpoint profile resolution and migration;
- provider-specific request URL/header construction;
- rich model parsers with stored JSON fixtures;
- price unit conversion and unknown-field behavior;
- role policy truth table;
- Qwen child environment redaction/injection;
- Anthropic/Custom translation routing;
- OpenRouter transcription route selection.

### Integration

- Settings selection → persisted `AppSettings` → `WorkflowState` →
  `ProviderRegistry` → executable route;
- valid/invalid key state with mocked HTTP;
- model change immediately changes role availability;
- active session provider synchronization.

### Black-box QA

- real native Settings window at minimum supported window size;
- one provider at a time, with safe test credentials supplied outside repo;
- click state before/after;
- reopen Settings and restart app;
- real translation request for each implemented text route;
- short audio fixture for every enabled transcription route;
- screenshots defined per implementation step.

## 10. Safety and rollback invariants

1. No secret in source, fixtures, logs, command arguments or documentation.
2. Qwen API key enters child process via environment only.
3. MCP token and Qwen provider key remain separate secrets.
4. No silent provider/endpoint fallback after validation.
5. No role is enabled solely because provider id is present.
6. Each implementation step remains buildable and independently revertible.
7. Existing `UsageRecorder` and `CloudBalanceService` are reused, not recreated.

## 11. Open risks

| Risk | Status | Mitigation gate |
|---|---|---|
| Exact cause of OpenRouter translation button no-op | `UNKNOWN` | CPS-01 |
| Token Plan allowed-use/model allowlist may change | External/drift-prone | CPS-01, CPS-02 |
| Provider list APIs often omit pricing | Verified limitation | source hierarchy + `asOf` |
| OpenRouter audio support differs per model/route | Verified | model-level route kind |
| Custom endpoints are not uniformly compatible | Verified | constrained protocol + preflight |
| Embedded Qwen verified model may not belong to selected Token Plan allowlist | Open | CPS-01, CPS-04 |

## 12. Official references

- Alibaba Model Studio Base URLs:
  https://www.alibabacloud.com/help/en/model-studio/base-url
- Alibaba Token Plan:
  https://www.alibabacloud.com/help/en/model-studio/token-plan-overview
- Alibaba supported models/capabilities:
  https://www.alibabacloud.com/help/en/model-studio/models
- Alibaba PAYG pricing:
  https://www.alibabacloud.com/help/en/model-studio/model-pricing
- OpenRouter model metadata:
  https://openrouter.ai/docs/guides/overview/models
- OpenRouter speech-to-text:
  https://openrouter.ai/docs/guides/overview/multimodal/stt
- Gemini Models API:
  https://ai.google.dev/api/models
- Anthropic Models API:
  https://platform.claude.com/docs/en/api/models/list
- OpenAI Models API:
  https://platform.openai.com/docs/api-reference/models/object
