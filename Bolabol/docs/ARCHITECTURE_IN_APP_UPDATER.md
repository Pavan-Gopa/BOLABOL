# BOLABOL — архитектура бесшовного обновления внутри приложения

> **Статус:** implementation-ready architecture / ADR  
> **Целевая платформа:** macOS 14+, Apple silicon  
> **Текущая публичная версия на момент проектирования:** `1.0.4`  
> **Первая версия с механизмом самообновления:** следующая версия после `1.0.4` (рекомендуется `1.0.5`)  
> **Обновляющий фреймворк:** Sparkle `2.9.4`, зафиксированный точной версией

## 0. Контракт для ИИ-агента

Этот документ является техническим заданием на производство. Агент должен реализовать решение целиком, включая код приложения, упаковку, подпись, appcast, release-скрипты, проверки и тесты.

Обязательные правила:

1. **Не писать собственный установщик**, который делает `rm -rf /Applications/Bolabol.app`, скачивает непроверенный DMG или запускает shell-скрипт из интернета.
2. Использовать **Sparkle 2** как проверенный движок скачивания, криптографической проверки, атомарной замены `.app`, авторизации и перезапуска.
3. Источником бинарника остаётся **GitHub Releases** репозитория `Pavan-Gopa/BOLABOL`.
4. Обычный пользовательский путь должен быть таким: обновление заранее безопасно загружается в фоне → в правом верхнем углу окна появляется яркая кнопка `BOLABOL 1.0.5` → один клик → приложение корректно завершает работу → Sparkle устанавливает обновление поверх текущей версии → приложение запускается снова.
5. Не менять существующие идентификаторы и пути хранения пользовательских данных.
6. Release-сборка без Developer ID, нотарификации, Sparkle EdDSA-подписи или валидного appcast должна завершаться ошибкой.
7. После реализации агент обязан провести реальное интеграционное обновление между двумя нотарифицированными сборками на отдельной тестовой ленте.

---

## 1. Архитектурное решение

### 1.1. Принятое решение

Использовать следующую связку:

- `Sparkle 2.9.4` через Swift Package Manager;
- `SPUStandardUpdaterController` и стандартный updater engine;
- автоматические фоновые проверки и подготовку обновления;
- `SPUUpdaterDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` для сохранения безопасного `immediateInstallHandler`;
- собственную SwiftUI-кнопку в `NSTitlebarAccessoryViewController` справа в title bar;
- GitHub Release asset `BOLABOL.dmg` как бинарный источник;
- подписанный appcast в репозитории;
- EdDSA-подпись архива и appcast плюс Developer ID Code Signing и Apple notarization.

### 1.2. Почему не GitHub API + самописный bash-установщик

Самописный updater пришлось бы самостоятельно научить:

- защищаться от подмены release asset;
- проверять подпись и целостность до распаковки;
- безопасно работать с quarantine и App Translocation;
- атомарно заменять приложение и восстанавливаться после сбоя питания;
- получать права администратора только когда это действительно требуется;
- корректно закрывать и повторно запускать приложение;
- предотвращать downgrade;
- сохранять подпись вложенных helper-процессов;
- учитывать запуск приложения с read-only DMG;
- работать с delta-обновлениями.

Sparkle уже решает эти задачи. Собственный downloader/installer здесь увеличивает риск потери приложения или компрометации цепочки поставки и не даёт продуктовой выгоды.

### 1.3. Почему стандартный updater engine, но собственная кнопка

Полностью собственная реализация `SPUUserDriver` требует корректно реализовать все состояния Sparkle: разрешение на проверки, release notes, скачивание, распаковку, запрос администратора, ожидание relaunch, ошибки и отмену. Для BOLABOL это лишняя поверхность ошибок.

Нужный UX достигается безопаснее:

1. Sparkle в фоне находит и загружает обновление.
2. Когда обновление подготовлено к установке, delegate получает `immediateInstallHandler`.
3. BOLABOL показывает собственную заметную кнопку в title bar.
4. Нажатие кнопки является осознанным пользовательским действием и вызывает handler.
5. Sparkle закрывает, заменяет и перезапускает приложение без браузера и ручного DMG.

При недостаточных правах macOS может показать системный запрос администратора. Это единственное допустимое дополнительное взаимодействие, потому что обходить системную авторизацию нельзя.

---

## 2. Аудит текущего репозитория

Точки интеграции уже существуют:

- `Bolabol/Package.swift` — SwiftPM-манифест, macOS 14, target `NativeBolabol`;
- `Bolabol/Sources/NativeBolabol/App/NativeBolabolApp.swift` — `AppDelegate` уже находит главное окно, хранит `mainWindow` и настраивает title bar в `registerMainWindowIfNeeded(_:)`;
- `Bolabol/script/build_release_dmg.sh` — вручную собирает `.app`, генерирует `Info.plist`, подписывает приложение и создаёт `dist/BOLABOL.dmg`;
- bundle identifier: `com.bolabol.app`;
- Developer ID identity: `Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)`;
- текущий GitHub Release публикует asset `BOLABOL.dmg`;
- приложение не sandboxed, поэтому Sparkle sandbox-only XPC configuration не требуется.

### 2.1. Где находятся данные, которые нельзя потерять

Обновление заменяет только `.app` bundle. Пользовательские данные уже находятся вне bundle:

| Данные | Текущее место / механизм | Контракт |
|---|---|---|
| Заметки | `~/Library/Application Support/NativeBolabol/notes.json` | Путь не менять и не удалять |
| Записи | `~/Library/Application Support/NativeBolabol/Recordings/` | Путь не менять и не очищать при update |
| Общие настройки | `UserDefaults.standard`, ключ `general.settings` | Bundle ID должен остаться прежним |
| Другие `@AppStorage`-настройки | defaults domain приложения | Bundle ID должен остаться прежним |
| API-ключи | Keychain service `com.bolabol.app.api-provider-credentials` | Bundle ID и service-name не менять |
| Локальные модели | по умолчанию `~/AI_LOCAL_MODELS`, также configured/env roots | Updater не должен касаться этих каталогов |
| Системные разрешения | macOS TCC / Accessibility | Сохранять bundle ID, Team ID и designated requirement |

**Запрещено** переносить изменяемые пользовательские данные внутрь `Bolabol.app`.

---

## 3. Целевой пользовательский сценарий

### 3.1. Обычный путь

1. Приложение запускает Sparkle updater после инициализации AppDelegate.
2. Sparkle проверяет appcast по расписанию.
3. При наличии версии с большим `CFBundleVersion` Sparkle скачивает и проверяет DMG в фоне.
4. В процессе подготовки можно показать компактное неактивное состояние `BOLABOL 1.0.5 · Preparing…`.
5. Когда Sparkle вызывает `willInstallUpdateOnQuit`, состояние меняется на `ready`.
6. В указанном на макете правом верхнем углу появляется яркая capsule-кнопка:
   - иконка `arrow.down.circle.fill`;
   - текст `BOLABOL 1.0.5`;
   - движущийся световой блик/градиент;
   - tooltip `Install update and relaunch`;
   - анимация выключается при Reduce Motion.
7. Пользователь нажимает кнопку.
8. BOLABOL проверяет, что сейчас не идёт запись или критичная несохраняемая операция.
9. Состояние сохраняется, затем вызывается `immediateInstallHandler`.
10. Sparkle завершает приложение, атомарно устанавливает новую `.app` и запускает её.
11. Новая версия открывает прежние заметки, записи, настройки, API-ключи и модели.

### 3.2. Исключения

- **Идёт запись с микрофона:** не убивать запись. Кнопка остаётся видимой, но при клике сообщает, что запись надо завершить; после завершения становится доступна установка.
- **Идёт короткая транскрипция/полировка:** дождаться безопасной точки с ограниченным timeout; если операция не завершилась — отменить установку, а не работу пользователя.
- **Нужны права администратора:** разрешить Sparkle/macOS показать системный prompt.
- **Приложение запущено с DMG/read-only location:** показать понятное сообщение «Move BOLABOL to Applications to enable updates» и кнопку открытия `/Applications`.
- **Нет сети:** сохранить нормальное состояние приложения, показать retry только после явной ошибки.
- **Подпись не совпадает:** обновление не устанавливать ни при каких условиях.

### 3.3. Дополнительные точки входа

Добавить fallback-пункты:

- меню приложения: `Check for Updates…`;
- status-bar menu: `Check for Updates…`.

Они вызывают `updaterController.checkForUpdates(nil)` и используют стандартный Sparkle UI. Это нужно для диагностики, ручной проверки и случаев, когда автообновление отключено пользователем.

---

## 4. Компоненты

### 4.1. `UpdateCoordinator`

Новый файл:

```text
Bolabol/Sources/NativeBolabol/Services/UpdateCoordinator.swift
```

Ответственность:

- владеть `SPUStandardUpdaterController`;
- быть `SPUUpdaterDelegate` и `SPUStandardUserDriverDelegate`;
- публиковать состояние для SwiftUI;
- хранить display version найденного обновления;
- хранить `immediateInstallHandler`;
- инициировать безопасный relaunch через `UpdateRelaunchGate`;
- предоставлять ручной `checkForUpdates()`;
- никогда не скачивать release asset самостоятельно.

Рекомендуемая state machine:

```swift
@MainActor
enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case preparing(version: String)
    case ready(version: String)
    case waitingForSafeRelaunch(version: String)
    case installing(version: String)
    case failed(version: String?, message: String)
}
```

Стартовый каркас:

```swift
import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateCoordinator: NSObject, ObservableObject {
    @Published private(set) var phase: AppUpdatePhase = .idle

    private var updaterController: SPUStandardUpdaterController!
    private let relaunchGate: UpdateRelaunchGate
    private var pendingVersion: String?
    private var immediateInstallHandler: (() -> Void)?

    init(relaunchGate: UpdateRelaunchGate) {
        self.relaunchGate = relaunchGate
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func installPreparedUpdate() {
        guard let handler = immediateInstallHandler,
              let version = pendingVersion else {
            checkForUpdates()
            return
        }

        phase = .waitingForSafeRelaunch(version: version)

        Task { @MainActor in
            do {
                try await relaunchGate.prepareForUpdateRelaunch()
                phase = .installing(version: version)
                // Sparkle documents that the handler may be invoked again if
                // application termination was canceled. Do not clear it early.
                handler()
            } catch {
                phase = .failed(version: version, message: error.localizedDescription)
            }
        }
    }
}

extension UpdateCoordinator: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        pendingVersion = item.displayVersionString
        phase = .preparing(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        pendingVersion = item.displayVersionString
        self.immediateInstallHandler = immediateInstallHandler
        phase = .ready(version: item.displayVersionString)
        return true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        pendingVersion = nil
        immediateInstallHandler = nil
        phase = .idle
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        phase = .failed(version: pendingVersion, message: error.localizedDescription)
    }
}

extension UpdateCoordinator: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Near launch / urgent cases remain under Sparkle's standard UI.
        // Normal scheduled updates use the BOLABOL title-bar reminder.
        immediateFocus
    }

    func standardUserDriverWillFinishUpdateSession() {
        if case .installing = phase { return }
        if immediateInstallHandler == nil {
            phase = .idle
        }
    }
}
```

Этот код является стартовой реализацией. Агент обязан сверить сигнатуры с зафиксированной версией Sparkle `2.9.4` и довести код до компилируемого состояния, не меняя архитектурный поток.

### 4.2. `UpdateRelaunchGate`

Новый файл:

```text
Bolabol/Sources/NativeBolabol/Services/UpdateRelaunchGate.swift
```

Назначение — не дать updater оборвать активную запись или оставить изменяемый файл в промежуточном состоянии.

Интерфейс:

```swift
@MainActor
protocol UpdateRelaunchPreparing: AnyObject {
    func prepareForUpdateRelaunch() async throws
}

@MainActor
final class UpdateRelaunchGate: ObservableObject {
    // Регистрирует quiescence handlers от ContentView / аудио / worker stores.
    // Все handlers выполняются последовательно с общим timeout.
    func prepareForUpdateRelaunch() async throws {
        // 1. Проверить активную запись.
        // 2. Дождаться/безопасно остановить фоновые операции.
        // 3. Сохранить stores.
        // 4. Завершить worker-процессы.
        // 5. Вернуть управление только когда app можно закрыть.
    }
}
```

Требования:

- не делать forced quit;
- не удалять временные данные;
- timeout должен возвращать ошибку в UI, а не продолжать установку;
- добавить явный `flushForUpdate()` в `NoteStore`, если после аудита окажется, что текущего синхронного сохранения недостаточно;
- запись с микрофона не должна автоматически теряться;
- все callbacks выполняются на MainActor, тяжёлое ожидание — без блокировки main thread.

### 4.3. `UpdateTitlebarButton`

Новый файл:

```text
Bolabol/Sources/NativeBolabol/Views/UpdateTitlebarButton.swift
```

Стартовый SwiftUI-каркас:

```swift
import SwiftUI

struct UpdateTitlebarButton: View {
    @ObservedObject var coordinator: UpdateCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheenOffset: CGFloat = -1.5

    var body: some View {
        Group {
            switch coordinator.phase {
            case .preparing(let version):
                label(version: version, suffix: "Preparing…", enabled: false)
            case .ready(let version):
                label(version: version, suffix: nil, enabled: true)
            case .waitingForSafeRelaunch(let version):
                label(version: version, suffix: "Finishing work…", enabled: false)
            case .installing(let version):
                label(version: version, suffix: "Installing…", enabled: false)
            case .failed(let version, _):
                label(version: version ?? "Update", suffix: "Retry", enabled: true)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func label(version: String, suffix: String?, enabled: Bool) -> some View {
        Button {
            if case .failed = coordinator.phase {
                coordinator.checkForUpdates()
            } else {
                coordinator.installPreparedUpdate()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: enabled ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                Text(suffix.map { "BOLABOL \(version) · \($0)" } ?? "BOLABOL \(version)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 28)
            .foregroundStyle(.white)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.pink, .purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.65), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: proxy.size.width * 0.35)
                            .offset(x: sheenOffset * proxy.size.width)
                            .rotationEffect(.degrees(18))
                        }
                        .clipShape(Capsule())
                    }
            }
            .shadow(radius: enabled ? 5 : 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Install update and relaunch" : "Preparing update")
        .onAppear {
            guard !reduceMotion, enabled else { return }
            sheenOffset = -1.5
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                sheenOffset = 3.0
            }
        }
        .accessibilityLabel("Update BOLABOL to version \(version)")
    }
}
```

Финальная реализация должна:

- не использовать бесконечную анимацию при Reduce Motion;
- при потере активности окна снижать интенсивность анимации;
- иметь достаточный contrast в light/dark mode;
- не менять высоту title bar;
- не перекрывать системные window controls;
- иметь минимум 28 pt по высоте и стабильную ширину без скачков.

### 4.4. Встраивание в правый верхний угол

В `AppDelegate` создать и хранить:

```swift
private let updateRelaunchGate = UpdateRelaunchGate()
private lazy var updateCoordinator = UpdateCoordinator(relaunchGate: updateRelaunchGate)
private var updateTitlebarAccessory: NSTitlebarAccessoryViewController?
private var updatePhaseObservation: AnyCancellable?
```

В `registerMainWindowIfNeeded(_:)` после `configureMainWindowTitle(window)` вызвать:

```swift
configureUpdateAccessory(for: window)
```

Принцип размещения:

```swift
let host = NSHostingView(
    rootView: UpdateTitlebarButton(coordinator: updateCoordinator)
)
host.translatesAutoresizingMaskIntoConstraints = false

let accessory = NSTitlebarAccessoryViewController()
accessory.layoutAttribute = .right
accessory.view = host
window.addTitlebarAccessoryViewController(accessory)
updateTitlebarAccessory = accessory
```

Контроллер нужно добавлять только один раз на конкретное главное окно. При `idle` можно либо удалить accessory, либо скрыть его с нулевой intrinsic width; предпочтительнее добавлять/удалять по state transition, чтобы в title bar не оставалось пустого зазора.

Именно `NSTitlebarAccessoryViewController` с `.right` соответствует области, отмеченной на макете.

---

## 5. Swift Package Manager и bundle packaging

### 5.1. `Package.swift`

Добавить точную зависимость:

```swift
.package(
    url: "https://github.com/sparkle-project/Sparkle",
    exact: "2.9.4"
)
```

В dependencies target `NativeBolabol` добавить:

```swift
.product(name: "Sparkle", package: "Sparkle")
```

Не использовать moving branch или `from:` для release updater dependency. Обновление Sparkle должно быть отдельным осознанным PR с тестом upgrade-path.

### 5.2. Встраивание `Sparkle.framework`

BOLABOL собирается не через Xcode Archive, а вручную в `build_release_dmg.sh`. Поэтому одного SwiftPM dependency недостаточно.

Скрипт обязан:

1. Найти бинарный artifact Sparkle динамически под `.build/artifacts/`, не полагаясь на один жёсткий абсолютный путь.
2. Скопировать `Sparkle.framework` в `Bolabol.app/Contents/Frameworks/` с сохранением symlink и executable bits, используя `/usr/bin/ditto`.
3. Проверить, что main executable имеет runpath `@executable_path/../Frameworks`; при отсутствии добавить `install_name_tool -add_rpath`.
4. Проверить через `otool -L`, что BOLABOL ссылается на `@rpath/Sparkle.framework/.../Sparkle`.
5. Подписать вложенные Sparkle components до подписи основного `.app`.

Рекомендуемый поиск:

```bash
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" \
  -type d -name Sparkle.framework -print -quit)"

[[ -n "$SPARKLE_FRAMEWORK" ]] || {
  echo "error: Sparkle.framework was not produced by SwiftPM" >&2
  exit 1
}

/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
```

### 5.3. Порядок подписи Sparkle

Для текущего manual packaging подписывать вложенные части в таком порядке, если они присутствуют:

```bash
SPARKLE="$APP_FRAMEWORKS/Sparkle.framework/Versions/B"

codesign_release "$SPARKLE/XPCServices/Installer.xpc"

# Sparkle >= 2.6: сохранить штатные entitlements Downloader.xpc.
/usr/bin/codesign --force --timestamp --options runtime \
  --sign "$SIGN_IDENTITY" \
  --preserve-metadata=entitlements \
  "$SPARKLE/XPCServices/Downloader.xpc"

codesign_release "$SPARKLE/Autoupdate"
codesign_release "$SPARKLE/Updater.app"
codesign_release "$APP_FRAMEWORKS/Sparkle.framework"
```

Затем подписывать остальные dylib/worker и основной app bundle.

**Нельзя использовать `codesign --deep` для подписи.** `--deep` допустим только как дополнительная проверка. Каждый nested code object должен иметь корректную собственную подпись.

Поскольку BOLABOL сейчас не sandboxed:

- не добавлять `SUEnableInstallerLauncherService`;
- не добавлять sandbox mach-lookup exceptions;
- на первом этапе не вырезать XPC/helper components из Sparkle — сначала добиться стабильной нотарифицированной цепочки.

### 5.4. Release mode не может быть ad-hoc

Сейчас build script допускает fallback на `SIGN_IDENTITY="-"`. Для локальной debug-сборки это можно сохранить, но публикация должна требовать:

```bash
RELEASE_BUILD=1
NOTARIZE=1
```

При `RELEASE_BUILD=1` ad-hoc identity — фатальная ошибка.

---

## 6. `Info.plist` и версия

`build_release_dmg.sh` генерирует реальный `Contents/Info.plist`, поэтому ключи необходимо добавлять именно туда, а не только в source plist.

Обязательные ключи:

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>${SPARKLE_PUBLIC_ED_KEY}</string>

<key>SUEnableAutomaticChecks</key>
<true/>

<key>SUAutomaticallyUpdate</key>
<true/>

<key>SUScheduledCheckInterval</key>
<integer>21600</integer>

<key>SUVerifyUpdateBeforeExtraction</key>
<true/>

<key>SURequireSignedFeed</key>
<true/>
```

Правила:

- `SPARKLE_PUBLIC_ED_KEY` — публичный ключ, его можно хранить в конфигурации/repo;
- приватный EdDSA-ключ запрещено коммитить;
- build script должен падать, если public key пустой в release mode;
- `CFBundleShortVersionString` — пользовательская semver, например `1.0.5`;
- `CFBundleVersion` — строго возрастающее целое, например UTC timestamp `202608171230`;
- `sparkle:version` в appcast должен совпадать с `CFBundleVersion`;
- `sparkle:shortVersionString` должен совпадать с `CFBundleShortVersionString`;
- Git tag должен совпадать с marketing version: `v1.0.5`.

Нельзя уменьшать `CFBundleVersion` даже при откате исходного кода.

---

## 7. Appcast и GitHub Releases

### 7.1. Стабильная лента

Файл:

```text
Bolabol/appcast.xml
```

Публичный URL:

```text
https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml
```

Enclosure каждого stable release должен указывать на immutable asset:

```text
https://github.com/Pavan-Gopa/BOLABOL/releases/download/v1.0.5/BOLABOL.dmg
```

Не использовать `releases/latest/download/...` внутри appcast: update item обязан быть привязан к конкретному immutable tag.

### 7.2. Ключи Sparkle

Один раз на защищённой release-машине:

```bash
/path/to/Sparkle/bin/generate_keys
```

- приватный ключ остаётся в macOS Keychain либо в зашифрованном offline backup;
- публичный ключ добавляется в release configuration;
- приватный ключ не должен попадать в git, GitHub Release, DMG, shell history или CI logs;
- сделать проверяемый зашифрованный backup ключа до первого публичного updater release.

### 7.3. Нельзя редактировать подписанный appcast после генерации

При `SURequireSignedFeed=true` appcast и release notes подписаны. Любая ручная правка URL после подписи сделает feed невалидным.

`generate_appcast` нужно запускать сразу с URL prefix GitHub Release. Перед реализацией скрипт обязан проверить актуальные параметры:

```bash
generate_appcast -h
```

Для Sparkle 2.9.4 ожидаемый принцип вызова:

```bash
"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/Pavan-Gopa/BOLABOL/releases/download/v${VERSION}/" \
  "$UPDATE_ARCHIVE_DIR"
```

Если CLI этой зафиксированной версии использует другое имя аргумента, агент должен адаптировать команду по `-h`, но **не должен** генерировать feed, затем менять enclosure через `sed`.

---

## 8. Release automation

Добавить:

```text
Bolabol/script/publish_update.sh
Bolabol/script/check_updater_release.sh
```

### 8.1. Обязательный порядок публикации

1. Проверить clean git tree и ветку.
2. Проверить semver, tag и строго возрастающий build number.
3. Собрать Developer ID signed app.
4. Подписать все Sparkle helpers и app bundle.
5. Создать `BOLABOL.dmg`.
6. Нотаризовать DMG и выполнить stapling.
7. Запустить локальный release validation.
8. Создать draft GitHub Release и загрузить `BOLABOL.dmg`.
9. Сгенерировать appcast с immutable URL будущего public release.
10. Проверить EdDSA signature, signed feed, версии, размер файла и URL.
11. Опубликовать GitHub Release.
12. Коммитнуть/запушить новый `Bolabol/appcast.xml`.
13. Проверить публичный appcast и asset по HTTPS.
14. Выполнить smoke update со старой версии.

Допустимо сначала опубликовать release, а затем appcast: короткое окно, когда новый DMG уже доступен, но клиенты ещё не видят его, безопаснее, чем appcast, который указывает на недоступный draft asset.

### 8.2. Каркас `publish_update.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: publish_update.sh <semver> <build>}"
BUILD="${2:?usage: publish_update.sh <semver> <build>}"
TAG="v${VERSION}"
REPO="Pavan-Gopa/BOLABOL"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="$ROOT_DIR/dist/BOLABOL.dmg"
UPDATE_ARCHIVE_DIR="$ROOT_DIR/dist/appcast-input"
APPCAST_OUT="$ROOT_DIR/appcast.xml"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "error: invalid semantic version: $VERSION" >&2
  exit 1
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "error: build must be numeric" >&2
  exit 1
}

git -C "$ROOT_DIR" diff --quiet
git -C "$ROOT_DIR" diff --cached --quiet

RELEASE_BUILD=1 NOTARIZE=1 \
  APP_VERSION="$VERSION" APP_BUILD="$BUILD" \
  "$ROOT_DIR/script/build_release_dmg.sh"

"$ROOT_DIR/script/check_updater_release.sh" "$DMG" "$VERSION" "$BUILD"

gh release create "$TAG" \
  --repo "$REPO" \
  --title "BOLABOL $VERSION" \
  --notes-file "$ROOT_DIR/docs/RELEASE_NOTES.md" \
  --target main \
  --draft

gh release upload "$TAG" "$DMG#BOLABOL.dmg" --repo "$REPO" --clobber

rm -rf "$UPDATE_ARCHIVE_DIR"
mkdir -p "$UPDATE_ARCHIVE_DIR"
/usr/bin/ditto "$DMG" "$UPDATE_ARCHIVE_DIR/BOLABOL.dmg"
cp "$ROOT_DIR/docs/RELEASE_NOTES.md" "$UPDATE_ARCHIVE_DIR/BOLABOL.md"

GENERATE_APPCAST="$(find "$ROOT_DIR/.build/artifacts" \
  -type f -name generate_appcast -perm -111 -print -quit)"
[[ -x "$GENERATE_APPCAST" ]] || {
  echo "error: Sparkle generate_appcast tool not found" >&2
  exit 1
}

"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  "$UPDATE_ARCHIVE_DIR"

cp "$UPDATE_ARCHIVE_DIR/appcast.xml" "$APPCAST_OUT"

# Implement this validator; it must verify versions, signatures and URLs.
"$ROOT_DIR/script/check_updater_release.sh" \
  "$DMG" "$VERSION" "$BUILD" "$APPCAST_OUT"

gh release edit "$TAG" --repo "$REPO" --draft=false --latest

git -C "$ROOT_DIR" add appcast.xml
git -C "$ROOT_DIR" commit -m "release: publish BOLABOL $VERSION appcast"
git -C "$ROOT_DIR" push origin HEAD

curl --fail --silent --show-error --location \
  "https://raw.githubusercontent.com/$REPO/main/Bolabol/appcast.xml" >/dev/null
curl --fail --silent --show-error --location --head \
  "https://github.com/$REPO/releases/download/$TAG/BOLABOL.dmg" >/dev/null

echo "Published BOLABOL $VERSION ($BUILD)"
```

Каркас необходимо довести до production-grade:

- корректно обнаруживать имя appcast, которое создаёт `generate_appcast`;
- сохранять предыдущие update archives вне git для delta generation;
- не перезаписывать существующий tag без явного аварийного режима;
- делать cleanup draft release при ошибке;
- не печатать секреты;
- проверять, что release asset digest совпадает с локальным DMG;
- работать только с notarized build.

### 8.3. `check_updater_release.sh`

Скрипт должен минимум:

- смонтировать DMG read-only;
- найти `Bolabol.app`;
- проверить bundle ID, marketing/build version;
- проверить присутствие `Sparkle.framework`;
- проверить `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`;
- выполнить `codesign --verify --deep --strict --verbose=4`;
- выполнить `spctl -a -vv -t exec Bolabol.app`;
- выполнить `spctl -a -vv -t install BOLABOL.dmg`;
- выполнить `xcrun stapler validate BOLABOL.dmg`;
- проверить подписи nested Sparkle code objects;
- проверить, что appcast XML валиден;
- проверить соответствие `sparkle:version`, `sparkle:shortVersionString`, length и enclosure URL;
- проверить наличие EdDSA signature и signed-feed signature;
- проверить HTTPS-доступность enclosure после публикации.

---

## 9. Сохранение настроек, сообщений и разрешений

### 9.1. Инварианты identity

Следующие значения являются постоянным контрактом обновления:

```text
CFBundleIdentifier = com.bolabol.app
Application name   = Bolabol.app
Team ID            = 438UQRF7JV
Keychain service   = com.bolabol.app.api-provider-credentials
App Support root   = ~/Library/Application Support/NativeBolabol
```

Изменение любого из них требует отдельного migration plan и не должно быть частью updater-задачи.

### 9.2. Миграции данных

Обновление bundle само по себе не должно менять данные. Если новая версия меняет schema заметок/настроек:

1. До первой записи новой схемы создать backup:
   `~/Library/Application Support/NativeBolabol/Backups/pre-update-<old-build>/`.
2. Миграция должна быть forward-only, идемпотентной и тестируемой.
3. При ошибке оставить исходный файл нетронутым и запустить приложение в safe/recovery mode.
4. Нельзя использовать updater script для миграции пользовательских данных; миграция выполняется новой версией приложения после запуска.

### 9.3. Permissions

Для максимального сохранения Microphone/Accessibility/Apple Events permissions:

- не менять bundle identifier;
- подписывать каждую release-версию тем же Team ID и Developer ID lineage;
- не выпускать ad-hoc public builds;
- не менять designated requirement без отдельного теста;
- не менять путь приложения по умолчанию `/Applications/Bolabol.app`;
- проверять upgrade на чистом macOS user account.

Apple может повторно запросить разрешение при существенном изменении подписи или политики системы. Архитектура минимизирует этот риск, но не должна пытаться обходить TCC.

---

## 10. Bootstrap-ограничение

Версия `1.0.4` уже установлена у пользователей и не содержит updater-кода. Она физически не может сама получить эту новую функцию.

Поэтому:

- `1.0.5` (или другая первая версия с Sparkle) устанавливается пользователями вручную **один последний раз**;
- начиная с `1.0.6`, обновления выполняются внутри BOLABOL;
- release notes первой updater-версии должны явно сказать: «This is the final manual installation required; future updates install in-app».

Никакой архитектурой нельзя добавить код самообновления в уже выпущенный бинарник `1.0.4` без хотя бы одного переходного обновления.

---

## 11. Тестовая стратегия

### 11.1. Unit tests

Добавить тесты для:

- преобразования delegate callbacks в `AppUpdatePhase`;
- отображения версии;
- повторного вызова install handler после отменённого termination;
- `UpdateRelaunchGate` timeout/error;
- отсутствия установки во время активной записи;
- retry после сетевой ошибки;
- strict monotonic build version check.

### 11.2. UI/contract tests

Проверить:

- accessory расположен справа в title bar;
- он отсутствует в `idle`;
- `preparing` не кликабелен;
- `ready` кликабелен и заметен;
- Reduce Motion выключает движущийся sheen;
- кнопка доступна через VoiceOver;
- light/dark mode;
- изменение размера окна;
- full-screen и повторное создание окна;
- отсутствие дубликатов accessory controller.

### 11.3. Packaging tests

В CI или release validation:

- Sparkle.framework присутствует и загружается;
- symlink внутри framework сохранены;
- nested helpers подписаны;
- app и DMG нотарифицированы;
- Info.plist содержит production feed/public key;
- production build не ad-hoc;
- appcast и DMG signatures валидны;
- enclosure URL отдаёт ожидаемый файл.

### 11.4. End-to-end update matrix

Обязательный реальный тест:

| From | To | Location | Account | Ожидание |
|---|---|---|---|---|
| bridge build N | N+1 | `/Applications` | admin | один клик, relaunch |
| bridge build N | N+1 | `/Applications` | standard user | системная авторизация при необходимости |
| N | N+1 | custom writable folder | user | обновляется текущий bundle |
| N | N+1 | mounted DMG | user | отказ с инструкцией переноса |
| N | N+1 | `/Applications` | offline → online | retry без повреждения |
| N | tampered N+1 | `/Applications` | user | cryptographic rejection |
| N | lower build | `/Applications` | user | downgrade rejected |

### 11.5. Data preservation test

Перед обновлением создать:

- несколько заметок с Raw/Variant 1/Variant 2;
- microphone recording;
- импортированный audio path;
- изменённые настройки;
- API provider key в Keychain;
- выбранные модели и configured root;
- выданные microphone/accessibility permissions.

После обновления автоматически сравнить:

- checksum `notes.json` до первой schema migration;
- список и checksum Recordings;
- settings payload;
- доступность Keychain items;
- model paths;
- наличие разрешений;
- текущую версию приложения.

---

## 12. Definition of Done

Задача завершена только когда выполнено всё ниже:

- [ ] Sparkle `2.9.4` зафиксирован в SwiftPM.
- [ ] Sparkle.framework встроен в manual app bundle и корректно подписан.
- [ ] Production `Info.plist` содержит feed URL, public Ed key и security flags.
- [ ] Appcast подписан и опубликован через HTTPS.
- [ ] GitHub Release содержит нотарифицированный `BOLABOL.dmg`.
- [ ] В правом верхнем углу title bar появляется версия обновления.
- [ ] Нормальный idle-path устанавливает и перезапускает приложение одним кликом.
- [ ] Системный admin prompt корректно обрабатывается.
- [ ] Активная запись не теряется.
- [ ] Заметки, записи, настройки, API keys и модели сохраняются.
- [ ] Bundle ID, Team ID, Keychain service и App Support path не изменены.
- [ ] Повреждённое или неподписанное обновление отвергается.
- [ ] Release build не допускает ad-hoc signing.
- [ ] Реальный upgrade test N → N+1 пройден на нотарифицированных артефактах.
- [ ] `docs/RELEASE.md` обновлён новым процессом.
- [ ] Есть fallback `Check for Updates…` в app menu и status menu.
- [ ] Reduce Motion и VoiceOver поддержаны.

---

## 13. Рекомендуемый порядок коммитов агента

1. `build: add pinned Sparkle dependency and bundle embedding`
2. `build: sign and validate nested Sparkle helpers`
3. `feat: add update coordinator and relaunch safety gate`
4. `feat: add animated titlebar update action`
5. `feat: add manual check-for-updates menu actions`
6. `release: add signed appcast generation and validation`
7. `test: add updater unit packaging and preservation coverage`
8. `docs: update release and updater operations guide`

Каждый коммит должен собираться; security checks нельзя откладывать в отдельный «когда-нибудь» этап после публикации.

---

## 14. Официальные источники

- Sparkle repository: <https://github.com/sparkle-project/Sparkle>
- Basic setup: <https://sparkle-project.org/documentation/>
- Gentle update reminders / titlebar accessory: <https://sparkle-project.org/documentation/gentle-reminders/>
- Programmatic setup: <https://sparkle-project.org/documentation/programmatic-setup/>
- Publishing updates and EdDSA signing: <https://sparkle-project.org/documentation/publishing/>
- Code signing / sandbox notes: <https://sparkle-project.org/documentation/sandboxing/>
- `SPUUpdaterDelegate` API: <https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html>

---

## 15. Итоговая схема

```text
GitHub Release v1.0.6
    └── notarized + Developer-ID-signed BOLABOL.dmg
            └── EdDSA signature referenced by signed appcast

raw.githubusercontent.com/.../Bolabol/appcast.xml
    └── immutable enclosure URL for v1.0.6/BOLABOL.dmg

BOLABOL 1.0.5
    └── Sparkle scheduled check
            └── verifies signed feed
                    └── downloads + verifies DMG in background
                            └── delegate receives immediateInstallHandler
                                    └── titlebar button: “BOLABOL 1.0.6”
                                            └── one click
                                                    └── relaunch safety gate
                                                            └── atomic install
                                                                    └── BOLABOL 1.0.6 relaunches
                                                                            └── external user data remains intact
```

Это решение обеспечивает нужный продуктовый UX без ручного GitHub/DMG-процесса и без создания опасного самописного установщика.
