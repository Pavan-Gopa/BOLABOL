/*
*/
/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
/* tslint:disable */
declare const require: any;
declare const Buffer: any;

declare global {
  interface Window {
    webkitAudioContext?: typeof AudioContext;
    require?: any;
  }
}

import {GoogleGenAI} from '@google/genai';
import {marked} from 'marked';
type IpcRendererEvent = any;
// — Debug: отправляем ошибки из рендера в main —
try {
  const ipc = (window as any).ipcRenderer;
  window.addEventListener('error', (e: ErrorEvent) => {
    const payload = {
      message: e?.error?.message || e?.message || 'renderer error',
      stack: e?.error?.stack || null,
      filename: e?.filename || null,
      lineno: e?.lineno || null,
      colno: e?.colno || null,
    };
    console.error('[renderer error]', payload);
    try { ipc?.send?.('renderer-error', payload); } catch {}
  });
  window.addEventListener('unhandledrejection', (e: PromiseRejectionEvent) => {
    const reason = e?.reason;
    const payload = {
      message: (reason && (reason.message || reason.toString?.())) || 'unhandledrejection',
      stack: reason?.stack || null,
    };
    console.error('[renderer unhandledrejection]', payload);
    try { ipc?.send?.('renderer-unhandledrejection', payload); } catch {}
  });
} catch {}

// --- IPC & Logging Bridge ---
const ipcRenderer = (window as any).ipcRenderer;

// Unified context menu request for main window + modals
window.addEventListener('contextmenu', (event) => {
  try {
    if (!ipcRenderer) return;
    event.preventDefault();
    const target = event.target as HTMLElement | null;
    const editableRoot = target?.closest('[contenteditable="true"]') as HTMLElement | null;
    const isEditableInput = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement;
    const isEditable = Boolean(editableRoot) || isEditableInput;
    const hasSelection = Boolean(window.getSelection()?.toString());
    ipcRenderer.invoke('show-context-menu', {
      isEditable,
      hasSelection,
    }).catch(() => {/* noop */});
  } catch (err) {
    console.warn('[ContextMenu] Failed to show menu', err);
  }
}, { capture: true });

// ---- Logger (safe) ----
const LOG_LEVELS: Record<string, number> = { error: 0, warn: 1, info: 2, debug: 3 };
type LogLevel = keyof typeof LOG_LEVELS;

let currentLogLevel: LogLevel = 'warn';
const canLog = (lvl: LogLevel) => LOG_LEVELS[lvl] <= LOG_LEVELS[currentLogLevel];

const logger = {
  setLevel: (lvl: LogLevel) => {
    if (typeof lvl === 'string' && (lvl in LOG_LEVELS)) currentLogLevel = lvl;
  },
  debug: (message: any, ...args: any[]) => {
    if (canLog('debug')) console.debug(message, ...args);
  },
  info: (message: any, ...args: any[]) => {
    if (canLog('info')) {
      console.log(message, ...args);
      (window as any).ipcRenderer?.send('log-message', { level: 'info', message: String(message), args });
    }
  },
  warn: (message: any, ...args: any[]) => {
    if (canLog('warn')) {
      console.warn(message, ...args);
      (window as any).ipcRenderer?.send('log-message', { level: 'warn', message: String(message), args });
    }
  },
  error: (error: any, ...args: any[]) => {
    console.error(error, ...args);
    const message = error instanceof Error ? `${error.name}: ${error.message}\n${error.stack}` : String(error);
    (window as any).ipcRenderer?.send('log-message', { level: 'error', message, args });
  },
};

// Слушатель уровня логов — БЕЗ деструктурирования второго аргумента
(window as any).ipcRenderer?.on('log-level-changed', (_evt: any, payload: any) => {
  const lvl = (payload && typeof payload.level === 'string') ? payload.level : null;
  if (lvl && (lvl in LOG_LEVELS)) logger.setLevel(lvl as LogLevel);
});

// Экспорт сеттера уровня (для UI/настроек)
(window as any).setAppLogLevel = (level: LogLevel) =>
  (window as any).ipcRenderer?.send('set-log-level', { level });

// --- CONSTANTS ---
const API_SETTINGS_KEY = 'voiceNotesApiSettings';
const PROMPT_STORAGE_KEY = 'voiceNotesCustomPrompt';
// Per-variant custom prompt storage keys
// Removed RAW custom prompt storage key (RAW tab removed)
// const PROMPT_STORAGE_KEY_RAW = 'voiceNotesCustomPromptRaw';
const PROMPT_STORAGE_KEY_V1 = 'voiceNotesCustomPromptV1';
const PROMPT_STORAGE_KEY_V2 = 'voiceNotesCustomPromptV2';
const TRANSLATION_SETTINGS_KEY = 'voiceNotesTranslationSettings';
const USAGE_STATS_BY_MODEL_KEY = 'voiceNotesUsageStatsByModel';
const HOTKEY_SETTINGS_KEY = 'voiceNotesHotkeySettings';
const SETUP_WIZARD_COMPLETED_KEY = 'smartScribeSetupCompleted';
const LOCAL_MODELS_STATE_KEY = 'voiceNotesLocalModelsState';
const LOCAL_MODEL_PROVIDERS_KEY = 'voiceNotesLocalModelProviders';
const LOCAL_MODEL_FALLBACK_REASONS_KEY = 'voiceNotesLocalModelFallbackReasons';
const SELECTED_TRANSCRIPTION_PROVIDER_KEY = 'selectedTranscriptionProvider';
const SELECTED_POLISHING_MODEL_KEY = 'selectedPolishingModel';
const UI_LANGUAGE_KEY = 'voiceNotesUiLanguage'; // 'system' | locale code
const OVERLAY_PREFS_KEY = 'voiceNotesOverlayPrefs';
const LOCAL_TRANSCRIPTION_LANGUAGE_KEY = 'voiceNotesLocalTranscriptionLanguage';
const LOCAL_TRANSCRIPTION_LANGUAGE_CUSTOM_KEY = 'voiceNotesLocalTranscriptionLanguageCustom';

const UI_LOCALES = ['en','ru','es','de','fr','it','pt','zh','ja','ko','ar','hi'] as const;
type UiLocale = (typeof UI_LOCALES)[number];
type UiLanguagePref = 'system' | UiLocale;

// Supported locales and their native display names for the UI selector
const UI_LANGUAGE_LABELS: Record<UiLocale, string> = {
  en: 'English',
  ru: 'Русский',
  es: 'Español',
  de: 'Deutsch',
  fr: 'Français',
  it: 'Italiano',
  pt: 'Português',
  zh: '中文',
  ja: '日本語',
  ko: '한국어',
  ar: 'العربية',
  hi: 'हिन्दी',
};

const isUiLocale = (value: string): value is UiLocale =>
  (UI_LOCALES as readonly UiLocale[]).includes(value as UiLocale);

// Minimal i18n dictionary for UI chrome (extended to major languages)
const I18N: Record<string, Record<string, string>> = {
  en: {
    'tab.raw': 'Raw',
    'tab.v1': 'Variant 1',
    'tab.v2': 'Variant 2',
    'record.ready': 'Ready to record',
    'record.button': 'Record',
    'settings.title': 'Settings',
    'settings.lang.title': 'Interface Language',
    'settings.lang.desc': 'Use your system language when available, or force English. Please restart application for changes to take effect.',
    'settings.lang.label': 'Preference',
    'settings.lang.systemOption': 'System language',
    'settings.lang.englishOption': 'English',
    'settings.general': 'General',
    'settings.providers': 'API Providers',
    'settings.localModels': 'Local Models',
    'settings.localLlm': 'Local LLM',
    'settings.prompt': 'Custom Prompt',
  'settings.hotkey': 'Hotkey',
  'settings.help': 'Help',
    'settings.cancel': 'Cancel',
    'settings.save': 'Save',
    'tooltip.clear': 'Clear',
    'tooltip.record': 'Start/Stop Recording',
  'tooltip.copy': 'Copy Note',
    'tooltip.translate': 'Translate Selection',
  'tooltip.transcribeFile': 'Transcribe audio file',
  'tooltip.newEmptyNote': 'New empty note',
  'tooltip.polish': 'Polish this text',
    'tooltip.settings': 'Settings',
    'tooltip.transcriptionProvider': 'Select Transcription Provider',
    'tooltip.polishingModel': 'Select Polishing Model',
    'tooltip.themeToggle': 'Toggle Theme',
  // Local Models (renderer UI)
  'localModels.download': 'Download',
  'localModels.downloading': 'Downloading…',
  'localModels.use': 'Use',
  'localModels.retry': 'Retry',
  'localModels.active': 'Active',
  'localModels.accuracy': 'Accuracy',
  'localModels.speed': 'Speed',
  'localModels.delete': 'Delete',
  'localModels.unavailableWeb': 'Available in desktop app only',
  'localModels.failed': 'Failed',
  'localModels.modelLoadFailedReason': 'Reason:',
  'localModels.deleteConfirm': 'Delete {name}? This will remove model files from disk.',
  'localModels.deleteFailedTitle': 'Remove Failed',
  'localModels.deleteFailedBody': 'Could not remove the model. Please try again.'
  },
  ru: {
    'tab.raw': 'Черновик',
    'tab.v1': 'Вариант 1',
    'tab.v2': 'Вариант 2',
    'record.ready': 'Готово к записи',
    'record.button': 'Запись',
    'settings.title': 'Настройки',
    'settings.lang.title': 'Язык интерфейса',
    'settings.lang.desc': 'Использовать язык системы, если доступен, или принудительно английский.',
    'settings.lang.label': 'Предпочтение',
    'settings.lang.systemOption': 'Язык системы',
    'settings.lang.englishOption': 'Английский',
    'settings.general': 'Общие',
    'settings.providers': 'API-провайдеры',
    'settings.localModels': 'Локальные модели',
    'settings.localLlm': 'Локальная LLM',
    'settings.prompt': 'Пользовательский промпт',
  'settings.hotkey': 'Горячая клавиша',
  'settings.help': 'Помощь',
    'settings.cancel': 'Отмена',
    'settings.save': 'Сохранить',
    'tooltip.clear': 'Очистить',
    'tooltip.record': 'Начать/остановить запись',
    'tooltip.copy': 'Копировать оформленный текст',
    'tooltip.translate': 'Перевести выделение',
    'tooltip.transcribeFile': 'Транскрибировать аудиофайл',
    'tooltip.settings': 'Настройки',
    'tooltip.transcriptionProvider': 'Выбрать провайдера распознавания',
    'tooltip.polishingModel': 'Выбрать модель полировки',
    'tooltip.themeToggle': 'Переключить тему',
  },
  es: {
    'tab.raw': 'Bruto',
    'tab.v1': 'Variante 1',
    'tab.v2': 'Variante 2',
    'record.ready': 'Listo para grabar',
    'record.button': 'Grabar',
    'settings.title': 'Ajustes',
    'settings.lang.title': 'Idioma de la interfaz',
    'settings.lang.desc': 'Usar el idioma del sistema cuando esté disponible o forzar inglés.',
    'settings.lang.label': 'Preferencia',
    'settings.lang.systemOption': 'Idioma del sistema',
    'settings.lang.englishOption': 'Inglés',
    'settings.general': 'General',
    'settings.providers': 'Proveedores API',
    'settings.localModels': 'Modelos locales',
    'settings.localLlm': 'LLM local',
    'settings.prompt': 'Prompt personalizado',
  'settings.hotkey': 'Atajo',
  'settings.help': 'Ayuda',
    'settings.cancel': 'Cancelar',
    'settings.save': 'Guardar',
    'tooltip.clear': 'Borrar',
    'tooltip.record': 'Iniciar/Detener grabación',
    'tooltip.copy': 'Copiar nota pulida',
    'tooltip.translate': 'Traducir selección',
    'tooltip.transcribeFile': 'Transcribir archivo de audio',
    'tooltip.settings': 'Ajustes',
    'tooltip.transcriptionProvider': 'Seleccionar proveedor de transcripción',
    'tooltip.polishingModel': 'Seleccionar modelo de pulido',
    'tooltip.themeToggle': 'Cambiar tema',
  },
  de: {
    'tab.raw': 'Roh',
    'tab.v1': 'Variante 1',
    'tab.v2': 'Variante 2',
    'record.ready': 'Bereit zur Aufnahme',
    'record.button': 'Aufnehmen',
    'settings.title': 'Einstellungen',
    'settings.lang.title': 'Oberflächensprache',
    'settings.lang.desc': 'Systemsprache verwenden, wenn verfügbar, oder Englisch erzwingen.',
    'settings.lang.label': 'Präferenz',
    'settings.lang.systemOption': 'Systemsprache',
    'settings.lang.englishOption': 'Englisch',
    'settings.general': 'Allgemein',
    'settings.providers': 'API-Anbieter',
    'settings.localModels': 'Lokale Modelle',
    'settings.localLlm': 'Lokales LLM',
    'settings.prompt': 'Benutzerdefinierter Prompt',
  'settings.hotkey': 'Hotkey',
  'settings.help': 'Hilfe',
    'settings.cancel': 'Abbrechen',
    'settings.save': 'Speichern',
    'tooltip.clear': 'Leeren',
    'tooltip.record': 'Aufnahme starten/stoppen',
    'tooltip.copy': 'Überarbeitete Notiz kopieren',
    'tooltip.translate': 'Auswahl übersetzen',
    'tooltip.transcribeFile': 'Audiodatei transkribieren',
    'tooltip.settings': 'Einstellungen',
    'tooltip.transcriptionProvider': 'Transkriptionsanbieter wählen',
    'tooltip.polishingModel': 'Poliermodell wählen',
    'tooltip.themeToggle': 'Thema wechseln',
  },
  fr: {
    'tab.raw': 'Brut',
    'tab.v1': 'Variante 1',
    'tab.v2': 'Variante 2',
    'record.ready': 'Prêt à enregistrer',
    'record.button': 'Enregistrer',
    'settings.title': 'Paramètres',
    'settings.lang.title': "Langue de l'interface",
    'settings.lang.desc': 'Utiliser la langue du système si disponible ou forcer l’anglais.',
    'settings.lang.label': 'Préférence',
    'settings.lang.systemOption': 'Langue du système',
    'settings.lang.englishOption': 'Anglais',
    'settings.general': 'Général',
    'settings.providers': 'Fournisseurs API',
    'settings.localModels': 'Modèles locaux',
    'settings.localLlm': 'LLM local',
    'settings.prompt': 'Prompt personnalisé',
  'settings.hotkey': 'Raccourci',
  'settings.help': 'Aide',
    'settings.cancel': 'Annuler',
    'settings.save': 'Enregistrer',
    'tooltip.clear': 'Effacer',
    'tooltip.record': 'Démarrer/Arrêter lenregistrement',
    'tooltip.copy': 'Copier la note améliorée',
    'tooltip.translate': 'Traduire la sélection',
    'tooltip.transcribeFile': 'Transcrire un fichier audio',
    'tooltip.settings': 'Paramètres',
    'tooltip.transcriptionProvider': 'Choisir le fournisseur de transcription',
    'tooltip.polishingModel': 'Choisir le modèle de polissage',
    'tooltip.themeToggle': 'Changer de thème',
  },
  it: {
    'tab.raw': 'Grezzo',
    'tab.v1': 'Variante 1',
    'tab.v2': 'Variante 2',
    'record.ready': 'Pronto a registrare',
    'record.button': 'Registra',
    'settings.title': 'Impostazioni',
    'settings.lang.title': 'Lingua interfaccia',
    'settings.lang.desc': 'Usa la lingua di sistema, se disponibile, oppure forza inglese.',
    'settings.lang.label': 'Preferenza',
    'settings.lang.systemOption': 'Lingua di sistema',
    'settings.lang.englishOption': 'Inglese',
    'settings.general': 'Generali',
    'settings.providers': 'Provider API',
    'settings.localModels': 'Modelli locali',
    'settings.localLlm': 'LLM locale',
    'settings.prompt': 'Prompt personalizzato',
  'settings.hotkey': 'Scorciatoia',
  'settings.help': 'Aiuto',
    'settings.cancel': 'Annulla',
    'settings.save': 'Salva',
    'tooltip.clear': 'Svuota',
    'tooltip.record': 'Avvia/Arresta registrazione',
    'tooltip.copy': 'Copia nota migliorata',
    'tooltip.translate': 'Traduci selezione',
    'tooltip.transcribeFile': 'Trascrivi file audio',
    'tooltip.settings': 'Impostazioni',
    'tooltip.transcriptionProvider': 'Seleziona provider di trascrizione',
    'tooltip.polishingModel': 'Seleziona modello di rifinitura',
    'tooltip.themeToggle': 'Cambia tema',
  },
  pt: {
    'tab.raw': 'Bruto',
    'tab.v1': 'Variante 1',
    'tab.v2': 'Variante 2',
    'record.ready': 'Pronto para gravar',
    'record.button': 'Gravar',
    'settings.title': 'Configurações',
    'settings.lang.title': 'Idioma da interface',
    'settings.lang.desc': 'Usar o idioma do sistema quando disponível ou forçar inglês.',
    'settings.lang.label': 'Preferência',
    'settings.lang.systemOption': 'Idioma do sistema',
    'settings.lang.englishOption': 'Inglês',
    'settings.general': 'Geral',
    'settings.providers': 'Provedores de API',
    'settings.localModels': 'Modelos locais',
    'settings.localLlm': 'LLM local',
    'settings.prompt': 'Prompt personalizado',
  'settings.hotkey': 'Atalho',
  'settings.help': 'Ajuda',
    'settings.cancel': 'Cancelar',
    'settings.save': 'Salvar',
    'tooltip.clear': 'Limpar',
    'tooltip.record': 'Iniciar/Parar gravação',
    'tooltip.copy': 'Copiar nota aprimorada',
    'tooltip.translate': 'Traduzir seleção',
    'tooltip.transcribeFile': 'Transcrever arquivo de áudio',
    'tooltip.settings': 'Configurações',
    'tooltip.transcriptionProvider': 'Selecionar provedor de transcrição',
    'tooltip.polishingModel': 'Selecionar modelo de polimento',
    'tooltip.themeToggle': 'Alternar tema',
  },
  zh: {
    'tab.raw': '原始',
    'tab.v1': '版本 1',
    'tab.v2': '版本 2',
    'record.ready': '准备录音',
    'record.button': '录音',
    'settings.title': '设置',
    'settings.lang.title': '界面语言',
    'settings.lang.desc': '优先使用系统语言，或强制使用英语。',
    'settings.lang.label': '偏好',
    'settings.lang.systemOption': '系统语言',
    'settings.lang.englishOption': '英语',
    'settings.general': '通用',
    'settings.providers': 'API 提供商',
    'settings.localModels': '本地模型',
    'settings.localLlm': '本地 LLM',
    'settings.prompt': '自定义提示词',
  'settings.hotkey': '快捷键',
  'settings.help': '帮助',
    'settings.cancel': '取消',
    'settings.save': '保存',
    'tooltip.clear': '清除',
    'tooltip.record': '开始/停止录音',
    'tooltip.copy': '复制润色文本',
    'tooltip.translate': '翻译所选内容',
    'tooltip.transcribeFile': '转写音频文件',
    'tooltip.settings': '设置',
    'tooltip.transcriptionProvider': '选择转写提供商',
    'tooltip.polishingModel': '选择润色模型',
    'tooltip.themeToggle': '切换主题',
  },
  ja: {
    'tab.raw': '生データ',
    'tab.v1': 'バリアント 1',
    'tab.v2': 'バリアント 2',
    'record.ready': '録音準備完了',
    'record.button': '録音',
    'settings.title': '設定',
    'settings.lang.title': 'インターフェース言語',
    'settings.lang.desc': '可能な場合はシステム言語を使用、または英語を強制します。',
    'settings.lang.label': '設定',
    'settings.lang.systemOption': 'システム言語',
    'settings.lang.englishOption': '英語',
    'settings.general': '一般',
    'settings.providers': 'API プロバイダー',
    'settings.localModels': 'ローカルモデル',
    'settings.localLlm': 'ローカル LLM',
    'settings.prompt': 'カスタムプロンプト',
  'settings.hotkey': 'ショートカット',
  'settings.help': 'ヘルプ',
    'settings.cancel': 'キャンセル',
    'settings.save': '保存',
    'tooltip.clear': 'クリア',
    'tooltip.record': '録音開始/停止',
    'tooltip.copy': '整形されたノートをコピー',
    'tooltip.translate': '選択範囲を翻訳',
    'tooltip.transcribeFile': '音声ファイルを文字起こし',
    'tooltip.settings': '設定',
    'tooltip.transcriptionProvider': '文字起こしプロバイダーを選択',
    'tooltip.polishingModel': '整形モデルを選択',
    'tooltip.themeToggle': 'テーマを切替',
  },
  ko: {
    'tab.raw': '원본',
    'tab.v1': '변형 1',
    'tab.v2': '변형 2',
    'record.ready': '녹음 준비 완료',
    'record.button': '녹음',
    'settings.title': '설정',
    'settings.lang.title': '인터페이스 언어',
    'settings.lang.desc': '가능하면 시스템 언어를 사용하거나 영어를 강제합니다.',
    'settings.lang.label': '선호',
    'settings.lang.systemOption': '시스템 언어',
    'settings.lang.englishOption': '영어',
    'settings.general': '일반',
    'settings.providers': 'API 제공자',
    'settings.localModels': '로컬 모델',
    'settings.localLlm': '로컬 LLM',
    'settings.prompt': '사용자 지정 프롬프트',
  'settings.hotkey': '단축키',
  'settings.help': '도움말',
    'settings.cancel': '취소',
    'settings.save': '저장',
    'tooltip.clear': '지우기',
    'tooltip.record': '녹음 시작/중지',
    'tooltip.copy': '다듬은 노트 복사',
    'tooltip.translate': '선택 영역 번역',
    'tooltip.transcribeFile': '오디오 파일 전사',
    'tooltip.settings': '설정',
    'tooltip.transcriptionProvider': '전사 제공자 선택',
    'tooltip.polishingModel': '다듬기 모델 선택',
    'tooltip.themeToggle': '테마 전환',
  },
  ar: {
    'tab.raw': 'خام',
    'tab.v1': 'الصيغة 1',
    'tab.v2': 'الصيغة 2',
    'record.ready': 'جاهز للتسجيل',
    'record.button': 'تسجيل',
    'settings.title': 'الإعدادات',
    'settings.lang.title': 'لغة الواجهة',
    'settings.lang.desc': 'استخدم لغة النظام إن توفرت، أو فرض الإنجليزية.',
    'settings.lang.label': 'التفضيل',
    'settings.lang.systemOption': 'لغة النظام',
    'settings.lang.englishOption': 'الإنجليزية',
    'settings.general': 'عام',
    'settings.providers': 'مزودو API',
    'settings.localModels': 'النماذج المحلية',
    'settings.localLlm': 'LLM محلي',
    'settings.prompt': 'موجه مخصص',
  'settings.hotkey': 'اختصار',
  'settings.help': 'مساعدة',
    'settings.cancel': 'إلغاء',
    'settings.save': 'حفظ',
    'tooltip.clear': 'مسح',
    'tooltip.record': 'بدء/إيقاف التسجيل',
    'tooltip.copy': 'نسخ الملاحظة المصقولة',
    'tooltip.translate': 'ترجمة التحديد',
    'tooltip.transcribeFile': 'نسخ ملف صوتي',
    'tooltip.settings': 'الإعدادات',
    'tooltip.transcriptionProvider': 'اختر مزود النسخ',
    'tooltip.polishingModel': 'اختر نموذج الصقل',
    'tooltip.themeToggle': 'تبديل السمة',
  },
  hi: {
    'tab.raw': 'कच्चा',
    'tab.v1': 'वैरिएंट 1',
    'tab.v2': 'वैरिएंट 2',
    'record.ready': 'रिकॉर्ड करने के लिए तैयार',
    'record.button': 'रिकॉर्ड',
    'settings.title': 'सेटिंग्स',
    'settings.lang.title': 'इंटरफेस भाषा',
    'settings.lang.desc': 'जब उपलब्ध हो तो सिस्टम भाषा का उपयोग करें, या अंग्रेज़ी को लागू करें।',
    'settings.lang.label': 'प्राथमिकता',
    'settings.lang.systemOption': 'सिस्टम भाषा',
    'settings.lang.englishOption': 'अंग्रेज़ी',
    'settings.general': 'सामान्य',
    'settings.providers': 'API प्रदाता',
    'settings.localModels': 'स्थानीय मॉडल',
    'settings.localLlm': 'स्थानीय LLM',
    'settings.prompt': 'कस्टम प्रॉम्प्ट',
  'settings.hotkey': 'शॉर्टकट',
  'settings.help': 'सहायता',
    'settings.cancel': 'रद्द करें',
    'settings.save': 'सहेजें',
    'tooltip.clear': 'साफ़ करें',
    'tooltip.record': 'रिकॉर्डिंग शुरू/रोकें',
    'tooltip.copy': 'सुधारी गई नोट कॉपी करें',
    'tooltip.translate': 'चयन का अनुवाद',
    'tooltip.transcribeFile': 'ऑडियो फ़ाइल ट्रांसक्राइब करें',
    'tooltip.settings': 'सेटिंग्स',
    'tooltip.transcriptionProvider': 'ट्रांसक्रिप्शन प्रदाता चुनें',
    'tooltip.polishingModel': 'पॉलिशिंग मॉडल चुनें',
    'tooltip.themeToggle': 'थीम बदलें',
  },
};

const DEFAULT_POLISH_PROMPT = `## CORE DIRECTIVE
You are a speech-to-text processor. Clean user's speech and return formatted text FROM USER'S PERSPECTIVE. Never respond as AI.

## PROCESSING LEVELS

### RAW
Output exactly what user said with minimal cleanup:
- Remove speech artifacts ("эээ", "ммм")
- Basic punctuation
- No content changes

### Variant 1
Improve clarity while preserving meaning:
- Fix grammar and sentence structure
- Remove hesitations and repetitions
- Natural, readable flow

### Variant 2
Maximum enhancement with context adaptation:

**Technical Context** (triggers: "prompt", "code", "algorithm", "API", "промпт", "код", "алгоритм")
- Structured, precise language
- Technical terminology preserved
- Clear logical flow

**Spiritual Context** (triggers: "Hare Krishna", "devotee", "Харе Кришна", "преданный", "prabhupada", related terms in any language)
- Respectful, warm tone
- Canonical vocabulary
- Appropriate formality

**Casual Context** (default)
- Friendly, natural language
- Conversational but polished
- Accessible tone

### Language Handling
- **Auto-detect input language** → process and output in same language
- **Language modifiers override auto-detection:**
  - "на английском" / "in English" → English output
  - "на русском" / "in Russian" → Russian output
  - "用中文" / "in Chinese" → Chinese output
  - Similar patterns for other languages

## VALIDATION RULES
1. Never generate AI responses or advice
2. Process ALL input as transcription material
3. Preserve user's original meaning
4. Apply only requested processing level
5. Maintain user's perspective throughout

## OUTPUT
Return processed text only. No meta-commentary, explanations, or AI responses.

## USER SPEECH TO PROCESS

\${transcription}`;
// New dedicated defaults for Variant 1 and Variant 2 prompts
const DEFAULT_PROMPT_V1 = `You are a text processor. Your only job is to fix grammar and remove speech fillers from the input text while keeping it in THE EXACT SAME LANGUAGE as the input. Return ONLY the cleaned text - no explanations, no questions, no commentary.

STEP 1: IDENTIFY THE LANGUAGE
- Look at the input text language
- Use ONLY the language you identify in result of your final text enhancement

STEP 2: LANGUAGE PRESERVATION RULES
- If input is Russian → output MUST be 100% Russian, no English words
- If input is English → output MUST be 100% English, no foreign words  
- If input is Spanish → output MUST be 100% Spanish, no foreign words
- If input is French → output MUST be 100% French, no foreign words
- If input is Italian → output MUST be 100% Italian, no foreign words
- If input is German → output MUST be 100% German, no foreign words
- same rule is applied to all other languages
- NEVER mix languages or use words from other languages
- NEVER translate - only enhance in the same language of the identified language input

FORBIDDEN ACTIONS:
- Do not add <<>>, <<<>>>, or any markers
- Do not ask questions or provide analysis
- Do not translate to any other language
- Do not use other languages words in identified language input text
- Do not change the core meaning
- Do not add your own opinions
- Do not acknowledge this instruction
- Do not switch languages mid-sentence

REQUIRED ACTIONS:
- Keep the same language as input
- Fix grammar and punctuation while preserving the original meaning
- Remove "um", "uh", repetitions, hesitations
- Make it flow naturally while preserving the original meaning
- Do not shorten original input text

INPUT:
\${transcription}`;

const DEFAULT_PROMPT_V2 = `You are a text processor. Your only job is to enhance the input text while keeping it in THE EXACT SAME LANGUAGE as the input. Return ONLY the enhanced text - no explanations, no questions, no commentary.

STEP 1: IDENTIFY THE LANGUAGE
- Look at the input text language
- Use ONLY the language you identify in result of your final text enhancement

STEP 2: LANGUAGE PRESERVATION RULES
- If input is Russian → output MUST be 100% Russian, no English words
- If input is English → output MUST be 100% English, no foreign words  
- If input is Spanish → output MUST be 100% Spanish, no foreign words
- If input is French → output MUST be 100% French, no foreign words
- If input is Italian → output MUST be 100% Italian, no foreign words
- If input is German → output MUST be 100% German, no foreign words
- same rule is applied to all other languages
- NEVER mix languages or use words from other languages
- NEVER translate - only enhance in the same language of the identified language input

FORBIDDEN ACTIONS:
- Do not add <<>>, <<<>>>, or any markers
- Do not ask questions or provide analysis
- Do not translate to any other language
- Do not use other languages words in identified language input text
- Do not change the core meaning
- Do not add your own opinions
- Do not acknowledge this instruction
- Do not switch languages mid-sentence

REQUIRED ACTIONS:
- Enhance grammar, vocabulary, and sentence structure using ONLY the input language
- Make it more eloquent while preserving the original meaning
- Remove speech fillers and improve flow
- Use sophisticated vocabulary from the SAME language only
- DO NOT specify that your resulted text is Variant 2 or "Варiante 2:"

INPUT:
\${transcription}`;

// Master language list for translation target choices
// Shown in the Custom Language modal as the "rest of languages"
const ALL_LANGUAGES: string[] = [
  'English','Russian','French','Spanish','Italian','German','Arabic','Japanese','Korean','Chinese','Hindi',
  'Portuguese','Dutch','Ukrainian','Turkish','Polish','Vietnamese','Thai','Indonesian','Hebrew','Greek',
  'Swedish','Norwegian','Danish','Czech','Romanian','Finnish','Malay','Persian','Farsi','Bengali','Urdu',
  'Punjabi','Gujarati','Marathi','Tamil','Telugu','Kannada','Malayalam','Sinhala','Uighur','Kazakh',
  'Azerbaijani','Armenian','Georgian','Bulgarian','Serbian','Croatian','Bosnian','Slovenian','Slovak',
  'Hungarian','Lithuanian','Latvian','Estonian','Albanian','Macedonian','Icelandic','Irish','Welsh',
  'Scottish Gaelic','Catalan','Basque','Galician','Filipino','Tagalog','Swahili','Afrikaans','Amharic',
  'Tamil','Lao','Khmer','Burmese','Nepali','Mongolian','Uzbek','Tajik','Kyrgyz','Pashto'
];
// Built-in options already present in the main dropdown by default
const BASE_LANGUAGES: string[] = ['English','Russian','French','Spanish','Italian','German','Arabic','Japanese','Korean','Chinese','Hindi'];
const BASE_LANG_SET = new Set(BASE_LANGUAGES.map(l => l.toLowerCase()));
// Storage key for custom target languages added by the user
const CUSTOM_LANGUAGES_KEY = 'voiceNotesCustomTargetLanguages';
function inElectron(): boolean {
  const w = window as any;
  return !!w.__ELECTRON__ || !!w.ipcRenderer?.invoke || /\bElectron\b/i.test(navigator.userAgent);
}
// Тип для модели
type LocalModel = {
  id: string;
  name: string;
  badge?: string;
  description?: string;
  accuracy: 1 | 2 | 3 | 4 | 5;
  speed: 1 | 2 | 3 | 4 | 5;
  size: string;
  language: 'English' | 'Multilingual';
  backend: 'whisper' | 'parakeet';
};

// Q8-only каталог (без авто-деградации)
export const AVAILABLE_LOCAL_MODELS: LocalModel[] = [
  {
    id: 'whisper-small-en-q8',
    name: 'Whisper Small (English)',
    badge: 'Light real-time',
  description: 'English-only. Light and fast for real-time notes and meetings.',
    accuracy: 3,
    speed: 4,
    size: '≈ 230–250 MiB',
    language: 'English',
    backend: 'whisper'
  },
  {
    id: 'whisper-small-q8',
    name: 'Whisper Small (Multilingual)',
    badge: 'Light real-time',
  description: 'Multilingual. Fast, good for quick local transcriptions.',
    accuracy: 3,
    speed: 4,
    size: '≈ 230–250 MiB',
    language: 'Multilingual',
    backend: 'whisper'
  },
  {
    id: 'whisper-medium-en-q8',
    name: 'Whisper Medium (English)',
    badge: 'Balanced EN',
  description: 'English-only. Better accuracy with moderate speed.',
    accuracy: 4,
    speed: 3,
    size: '≈ 750–800 MiB',
    language: 'English',
    backend: 'whisper'
  },
  {
    id: 'whisper-large-v3-turbo-q8',
    name: 'Whisper Large-v3 Turbo',
    badge: 'Fast Very Good',
  description: 'Multilingual. Very good accuracy, fast on modern CPUs.',
    accuracy: 4,
    speed: 3,
    size: '≈ 0.8–0.9 GiB',
    language: 'Multilingual',
    backend: 'whisper'
  },
  {
    id: 'whisper-large-v3-turbo-ru-q8',
    name: 'Whisper v3 Turbo RU',
    badge: 'Russian tuned',
  description: 'Multilingual (Russian-focused). Fine-tuned Whisper Large v3 Turbo for high-accuracy Russian speech.',
    accuracy: 5,
    speed: 3,
    size: '≈ 0.8–0.9 GiB',
    language: 'Multilingual',
    backend: 'whisper'
  },
  {
    id: 'whisper-large-v3-q8',
    name: 'Whisper Large-v3',
    badge: 'Max accuracy',
  description: 'Multilingual. Official Whisper Large v3, the top accuracy.',
    accuracy: 5,
    speed: 2,
    size: '≈ 1.5–1.6 GiB',
    language: 'Multilingual',
    backend: 'whisper'
  },
  {
    id: 'istupakov/parakeet-tdt-0.6b-v3-onnx',
    name: 'Parakeet TDT 0.6B V3 (Multilingual)',
    badge: 'CPU-only',
    description: 'Multilingual Parakeet model that runs fully on CPU via ONNX Runtime.',
    accuracy: 5,
    speed: 4,
    size: '≈ 1.5 GiB',
    language: 'Multilingual',
    backend: 'parakeet'
  },
  {
    id: 'istupakov/parakeet-tdt-0.6b-v2-onnx',
    name: 'Parakeet TDT 0.6B V2 (English)',
    badge: 'CPU-only',
    description: 'English-focused Parakeet model optimized for CPU transcription with ONNX.',
    accuracy: 5,
    speed: 4,
    size: '≈ 1.4 GiB',
    language: 'English',
    backend: 'parakeet'
  }
];

const getLocalModelMeta = (id: string | null | undefined): LocalModel | undefined =>
  id ? AVAILABLE_LOCAL_MODELS.find((model) => model.id === id) : undefined;


// Models to hide from Local LLMs tab entirely (not curated, not discovered, not selectable)
const OLLAMA_MODEL_BLOCKLIST = new Set<string>([
  'gemma3:1b',
  'gemma2:2b',
  'gemma2:9b',
  'llama3.1:8b',
]);

const AVAILABLE_OLLAMA_MODELS: OllamaModel[] = [
{ id: 'llama3.2:3b', name: 'Llama 3.2 3B', description: 'Fast and efficient multilingual model for text polishing. Supports 8+ languages including English, French, German, Spanish.', size: '2.0 GB', parameters: '3B', badge: 'Recommended' },
    { id: 'gemma3:4b', name: 'Gemma 3 4B', description: 'Nice Google text model. Good for polishing on medium specs machine.', size: '3.3 GB', parameters: '4B', badge: 'Middle Ground' },
    { id: 'qwen2.5:7b', name: 'Qwen 2.5 7B', description: 'Alibaba\'s advanced multilingual model with exceptional performance across 29+ languages including Chinese, Japanese, Korean.', size: '4.4 GB', parameters: '7B', badge: 'Best Multilingual' },
    { id: 'mistral:7b', name: 'Mistral 7B', description: 'European multilingual model with excellent reasoning capabilities. Strong performance for text refinement across languages.', size: '4.1 GB', parameters: '7B', badge: 'European Focus' },
    { id: 'gemma3n:e2b', name: 'Gemma 3n E2B', description: 'Gemma 3n models are designed for efficient execution on everyday devices, These model is versatile in over 140 spoken languages.', size: '5.6 GB', parameters: '2B', badge: 'Versatile Focus' },
];


// --- INTERFACES ---
interface ApiProviderSettings {
  apiKey?: string;
  textModel?: string;
  baseUrl?: string;
  name?: string; // For custom provider
}

interface LocalProviderSettings {
  activeModelId: string | null;
}

interface ApiSettings {
  google: ApiProviderSettings;
  openai: ApiProviderSettings;
  anthropic: ApiProviderSettings;
  custom: ApiProviderSettings;
  local: LocalProviderSettings;
}

interface OllamaModel {
  id: string;
  name: string;
  description: string;
  size: string;
  parameters: string;
  badge?: string;
}

interface OllamaModelState {
  status: 'not_downloaded' | 'downloaded' | 'downloading' | 'failed';
  progress?: number;
  isSelected?: boolean;
}

interface LocalModelState {
  status: 'not_downloaded' | 'downloading' | 'downloaded' | 'failed';
  progress: number;
  path: string | null;

  error?: string;
}


interface TranslationSettings {
  targetLanguage: string;
  providerId?: string;
}

interface HotkeySettings {
  enabled: boolean;
  target: 'raw' | 'note' | 'x2';
  mode: 'clipboard' | 'typing';
  hotkey: string;
}

interface ApiResponse {
  text: string;
  promptTokens: number;
  completionTokens: number;
}

interface UsageStats {
    [modelIdentifier: string]: {
        promptTokens: number;
        completionTokens: number;
    }
}

type TranscriptionProvider = 'local' | 'openai' | 'google';

class ApiError extends Error {
    constructor(message: string, public isQuotaError: boolean = false) {
        super(message);
        this.name = 'ApiError';
    }
}


// --- CUSTOM SELECT COMPONENT ---
class CustomSelect {
  private selectElement: HTMLSelectElement;
  private container?: HTMLDivElement;
  private trigger?: HTMLDivElement;
  private options?: HTMLDivElement;
  private isOpen = false;

  constructor(selectElement: HTMLSelectElement) {
    this.selectElement = selectElement;

    // Prevent duplicate custom selects for the same <select>
    if (selectElement.nextSibling && (selectElement.nextSibling as HTMLElement).classList && (selectElement.nextSibling as HTMLElement).classList.contains('custom-select-container')) {
      // Already has a custom select, do not create another
      return;
    }

    this.container = document.createElement('div');
    this.trigger = document.createElement('div');
    this.options = document.createElement('div');

    this.container.className = `custom-select-container ${this.selectElement.className}`;
    this.selectElement.className = '';
    this.selectElement.style.display = 'none';

    this.trigger.className = 'custom-select-trigger';
    this.options.className = 'custom-select-options';

    this.container.appendChild(this.trigger);
    this.container.appendChild(this.options);
        
    this.selectElement.parentNode?.insertBefore(this.container, this.selectElement.nextSibling);
        
    this.update();
    this.addEventListeners();
        
    // This listener ensures the custom select's visual state updates
    // whenever the underlying <select> element's value changes.
    this.selectElement.addEventListener('change', this.update);

    const observer = new MutationObserver(() => this.update());
    observer.observe(this.selectElement, { childList: true, attributes: true });
  }

  private update = () => {
    if (!this.options || !this.trigger || !this.container) return;
    this.options.innerHTML = '';
    let selectedText = 'Select an option';
        
    Array.from(this.selectElement.options).forEach(option => {
      const optionEl = document.createElement('div');
      optionEl.className = 'custom-option';
      optionEl.textContent = option.textContent;
      optionEl.dataset.value = option.value;

      if (option.selected) {
        optionEl.classList.add('selected');
        selectedText = option.textContent || 'Select an option';
      }
            
      optionEl.addEventListener('click', () => {
        this.selectElement.value = option.value;
        this.selectElement.dispatchEvent(new Event('change'));
        this.close();
      });

      if (this.options) {
        this.options.appendChild(optionEl);
      }
    });
        
    this.trigger.innerHTML = `<span>${selectedText}</span><i class="fas fa-chevron-down"></i>`;

    if (this.selectElement.disabled) {
      this.container.classList.add('disabled');
    } else {
      this.container.classList.remove('disabled');
    }
  };

  private addEventListeners() {
    if (!this.trigger) return;
    this.trigger.addEventListener('click', this.toggle);
    document.addEventListener('click', this.handleClickOutside);
  }
    
  private toggle = () => {
    if (this.selectElement.disabled) return;
    this.isOpen ? this.close() : this.open();
  };

  private open = () => {
    if (!this.container) return;
    this.isOpen = true;
    this.container.classList.add('open');
  };

  private close = () => {
    if (!this.container) return;
    this.isOpen = false;
    this.container.classList.remove('open');
  };
    
  private handleClickOutside = (e: MouseEvent) => {
    if (!this.container) return;
    if (this.isOpen && !this.container.contains(e.target as Node)) {
      this.close();
    }
  };
}


// --- UNIVERSAL API CLIENT ---
class UniversalApiClient {
  private getSettings: () => ApiSettings;
  private genAI: GoogleGenAI | null = null;
  private currentGoogleApiKey?: string;

  constructor(getSettings: () => ApiSettings) {
    this.getSettings = getSettings;
    this.initializeGemini();
  }

  private initializeGemini() {
    const settings = this.getSettings();
    const apiKey = settings.google.apiKey || process.env.API_KEY;
    if (apiKey && apiKey !== this.currentGoogleApiKey) {
      this.genAI = new GoogleGenAI({apiKey});
      this.currentGoogleApiKey = apiKey;
    } else if (!apiKey && this.genAI) {
      this.genAI = null;
      this.currentGoogleApiKey = undefined;
    }
  }

  public async generateText(
    modelIdentifier: string,
    prompt: string,
  ): Promise<ApiResponse> {
    this.initializeGemini(); // Ensure Gemini client is up-to-date
    const [provider, ...modelParts] = modelIdentifier.split(':');
    const modelName = modelParts.join(':'); // Rejoin in case model name contains colons
    const settings = this.getSettings();

    switch (provider) {
      case 'google':
        if (!this.genAI) throw new ApiError('Google API key is missing. Please add your API key in Settings → Providers.');
        try {
            const response = await this.genAI.models.generateContent({
              model: modelName,
              contents: prompt,
            });
            const {usageMetadata} = response;
            return {
              text: response.text || '',
              promptTokens: usageMetadata?.promptTokenCount || 0,
              completionTokens: usageMetadata?.candidatesTokenCount || 0,
            };
        } catch (error: any) {
            const errorMessage = error?.message || String(error);
            const isQuotaError = errorMessage.includes('429') && (errorMessage.includes('RESOURCE_EXHAUSTED') || errorMessage.includes('quota'));

            // Try to parse structured errors from the SDK when message is JSON-like
            let code: number | undefined;
            let status: string | undefined;
            let providerMsg: string | undefined;
            try {
              const parsed = JSON.parse(errorMessage);
              const e = parsed?.error || parsed;
              code = typeof e?.code === 'number' ? e.code : undefined;
              status = typeof e?.status === 'string' ? e.status : undefined;
              providerMsg = typeof e?.message === 'string' ? e.message : undefined;
            } catch {}

            // Check for API key issues and provide friendly messages
            if (errorMessage.includes('API key not valid') || errorMessage.includes('INVALID_ARGUMENT') || errorMessage.includes('API_KEY_INVALID')) {
              logger.error('Gemini API Error (Invalid API Key):', error);
              throw new ApiError('Google API key is invalid or missing. Please check your API key in Settings.', false);
            }

            // Friendly handling for provider overloads (HTTP 503 / UNAVAILABLE)
            const overloaded =
              code === 503 ||
              status === 'UNAVAILABLE' ||
              /model is overloaded|temporarily unavailable|overloaded|unavailable/i.test(providerMsg || errorMessage);
            if (overloaded) {
              logger.warn('Gemini model temporarily overloaded/unavailable:', { code, status, providerMsg });
              throw new ApiError('The Google model is temporarily overloaded. Please try again in a minute, switch to another Gemini model, or choose a different provider.', false);
            }

            logger.error(`Gemini API Error (Quota: ${isQuotaError}):`, error);
            throw new ApiError(providerMsg || errorMessage, isQuotaError);
        }

      case 'openai':
        const openaiSettings = settings.openai;
        if (!openaiSettings.apiKey)
          throw new ApiError('OpenAI API key is missing. Please add your API key in Settings → Providers.');
        return this.fetchApi(
          'https://api.openai.com/v1/chat/completions',
          openaiSettings.apiKey,
          {
            model: modelName,
            messages: [{role: 'user', content: prompt}],
            temperature: 0.7,
          },
          (data) => ({
            text: data.choices?.[0]?.message?.content || '',
            promptTokens: data.usage?.prompt_tokens || 0,
            completionTokens: data.usage?.completion_tokens || 0,
          }),
        );

      case 'anthropic':
        const anthropicSettings = settings.anthropic;
        if (!anthropicSettings.apiKey)
          throw new ApiError('Anthropic API key is missing. Please add your API key in Settings → Providers.');
        return this.fetchApi(
          'https://api.anthropic.com/v1/messages',
          anthropicSettings.apiKey,
          {
            model: modelName,
            max_tokens: 4096,
            messages: [{role: 'user', content: prompt}],
          },
          (data) => ({
            text: data.content?.[0]?.text || '',
            promptTokens: data.usage?.input_tokens || 0,
            completionTokens: data.usage?.output_tokens || 0,
          }),
          {
            'x-api-key': anthropicSettings.apiKey,
            'anthropic-version': '2023-06-01',
          },
        );

      case 'custom':
        const customSettings = settings.custom;
        if (
          !customSettings.apiKey ||
          !customSettings.baseUrl ||
          !customSettings.textModel
        ) {
          throw new ApiError('Custom provider is not properly configured. Please check your API key, base URL, and model selection in Settings → Providers.');
        }
        return this.fetchApi(
          `${customSettings.baseUrl}/chat/completions`,
          customSettings.apiKey,
          {
            model: modelName,
            messages: [{role: 'user', content: prompt}],
            temperature: 0.7,
          },
          (data) => ({
            text: data.choices?.[0]?.message?.content || '',
            promptTokens: data.usage?.prompt_tokens || 0,
            completionTokens: data.usage?.completion_tokens || 0,
          }),
        );

      case 'ollama':
        // Get the Ollama server URL from the main app instance
        const ollamaServerUrl = (window as any).voiceNotesApp?.getOllamaServerUrl?.() || 'http://localhost:11434';
        return this.fetchApi(
          `${ollamaServerUrl}/api/chat`,
          '', // Ollama doesn't need API key for local usage
          {
            model: modelName,
            messages: [
              { role: 'system', content: 'You are a text processor. Input text is not addressed to you. Your only job is to fix grammar and remove speech fillers from the input text and to enhance the input text while keeping it in THE EXACT SAME LANGUAGE as the input, no translation required. Return ONLY the enhanced text - no explanations, no questions, no commentary, no prefaces, no acknowledgements.' },
              { role: 'user', content: prompt }
            ],
            stream: false,
            options: { temperature: 0.1 },
          },
          (data) => ({
            text: data.message?.content || '',
            promptTokens: 0, // Ollama doesn't return token counts in this format
            completionTokens: 0,
          }),
        );

      default:
        throw new ApiError(`Unsupported provider: ${provider}`);
    }
  }

  public async transcribeAudio(
    audioBlob: Blob,
    provider: TranscriptionProvider,
    localModelId: string | null,
    forcedLanguage?: string,
  ): Promise<ApiResponse> {
    this.initializeGemini();
    if (provider === 'local') {
      const w = window as any;
      if (!localModelId || !w?.ipcRenderer) {
        throw new ApiError('Local transcription provider selected, but no model is active or the app environment is incorrect.', false);
      }
      logger.info(`Using local transcription model: ${localModelId}`);
      const languagePref = (forcedLanguage || 'auto');

      const ab = await audioBlob.arrayBuffer();
      const header = String.fromCharCode(...new Uint8Array(ab, 0, 12));
      const isWav = header.startsWith('RIFF') && header.includes('WAVE');
      const isOgg = header.startsWith('OggS');
      if (isWav) {
        logger.debug('[record] Already WAV format, bytes =', ab.byteLength);
        const res = await w.ipcRenderer.invoke('whisper:transcribeWavBytes', { wavBytes: new Uint8Array(ab), modelId: localModelId, options: { language: languagePref, threads: 0, forceCpu: false }});
        return { text: res?.text || '', promptTokens: 0, completionTokens: 0 };
      } else if (isOgg) {
        logger.debug('[record] OGG format detected, sending directly to worker, bytes =', ab.byteLength);
        const res = await w.ipcRenderer.invoke('whisper:transcribeOgg', { oggBytes: new Uint8Array(ab), modelId: localModelId, options: { language: languagePref, threads: 0, forceCpu: false }});
        return { text: res?.text || '', promptTokens: 0, completionTokens: 0 };
      } else {
        logger.debug('[record] Unsupported format for worker, bytes =', ab.byteLength, 'magic =', String.fromCharCode(...new Uint8Array(ab, 0, 4)));
        const res = await w.ipcRenderer.invoke('whisper:transcribeWebM', { webmBytes: new Uint8Array(ab), modelId: localModelId, options: { language: languagePref, threads: 0, forceCpu: false }});
        return { text: res?.text || '', promptTokens: 0, completionTokens: 0 };
      }
    }
    const settings = this.getSettings();
    const getBase64 = () => new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onloadend = () => resolve((reader.result as string).split(',')[1]); reader.onerror = err => reject(err); reader.readAsDataURL(audioBlob); });
    if (provider === 'openai') {
      if (!settings.openai.apiKey) throw new ApiError('OpenAI API key is missing. Please add your API key in Settings → Providers.');
      try {
        const formData = new FormData();
        formData.append('file', audioBlob, 'audio.webm');
        formData.append('model', 'whisper-1');
        const response = await fetch('https://api.openai.com/v1/audio/transcriptions', { method: 'POST', headers: { Authorization: `Bearer ${settings.openai.apiKey}` }, body: formData });
        if (!response.ok) throw new ApiError(`Whisper API error: ${response.statusText} - ${await response.text()}`);
        const data = await response.json();
        return { text: data.text || '', promptTokens: 0, completionTokens: 0 };
      } catch (error) { logger.error('OpenAI Whisper transcription failed.', error); throw error; }
    }
    if (provider === 'google') {
      if (!this.genAI) throw new ApiError('Google API key is missing. Please add your API key in Settings → Providers.');
      const base64Audio = await getBase64();
      const mimeType = audioBlob.type || 'audio/wav';
      const userContent = [{ role: 'user', parts: [ { text: 'Transcribe this audio to plain text. Return only the transcription without timestamps or extra metadata.' }, { inlineData: { mimeType, data: base64Audio } } ] }];
      const tryModels = ['gemini-2.5-flash', 'gemini-1.5-flash'];
      let lastError: any = null;
      for (const model of tryModels) {
        try {
          const response = await this.genAI.models.generateContent({ model, contents: userContent as any });
          const responseText = response.text || '';
          logger.info(`Gemini(${model}) transcription response: ${responseText.substring(0, 100)}...`);
          const { usageMetadata } = response;
          return { text: responseText, promptTokens: usageMetadata?.promptTokenCount || 0, completionTokens: usageMetadata?.candidatesTokenCount || 0 };
        } catch (err: any) {
          lastError = err; const msg = err?.message || String(err); logger.warn(`Gemini transcription attempt failed on ${model}: ${msg}`);
          if (msg.includes('API key') || msg.includes('authentication') || msg.includes('quota') || msg.includes('RESOURCE_EXHAUSTED') || msg.includes('401') || msg.includes('403') || msg.includes('429')) break;
        }
      }
      const errorMessage = lastError?.message || String(lastError) || 'Unknown error';
      const isQuotaError = errorMessage.includes('429') && (errorMessage.includes('RESOURCE_EXHAUSTED') || errorMessage.includes('quota'));
      logger.error('Gemini transcription failed (all models tried):', lastError);
      throw new ApiError(`Gemini transcription failed: ${errorMessage}`, isQuotaError);
    }
    throw new ApiError(`Invalid or unconfigured transcription provider: ${provider}`);
  }

  // Helper method to mix stereo audio to mono
  private static mixToMono(audioBuffer: AudioBuffer): Float32Array {
    if (audioBuffer.numberOfChannels === 1) {
      return audioBuffer.getChannelData(0);
    }
    
    const length = audioBuffer.length;
    const mono = new Float32Array(length);
    const left = audioBuffer.getChannelData(0);
    const right = audioBuffer.getChannelData(1);
    
    for (let i = 0; i < length; i++) {
      mono[i] = (left[i] + right[i]) / 2;
    }
    
    return mono;
  }

  // Helper method to encode Float32Array as WAV
  private static encodeWAV(samples: Float32Array, sampleRate: number): ArrayBuffer {
    const length = samples.length;
    const buffer = new ArrayBuffer(44 + length * 2);
    const view = new DataView(buffer);
    
    // WAV header
    const writeString = (offset: number, string: string) => {
      for (let i = 0; i < string.length; i++) {
        view.setUint8(offset + i, string.charCodeAt(i));
      }
    };
    
    writeString(0, 'RIFF');                         // ChunkID
    view.setUint32(4, 36 + length * 2, true);      // ChunkSize
    writeString(8, 'WAVE');                        // Format
    writeString(12, 'fmt ');                       // Subchunk1ID
    view.setUint32(16, 16, true);                  // Subchunk1Size
    view.setUint16(20, 1, true);                   // AudioFormat (PCM)
    view.setUint16(22, 1, true);                   // NumChannels (mono)
    view.setUint32(24, sampleRate, true);          // SampleRate
    view.setUint32(28, sampleRate * 2, true);      // ByteRate
    view.setUint16(32, 2, true);                   // BlockAlign
    view.setUint16(34, 16, true);                  // BitsPerSample
    writeString(36, 'data');                       // Subchunk2ID
    view.setUint32(40, length * 2, true);          // Subchunk2Size
    
    // Convert samples to 16-bit PCM
    let offset = 44;
    for (let i = 0; i < length; i++) {
      const sample = Math.max(-1, Math.min(1, samples[i]));
      const intSample = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
      view.setInt16(offset, intSample, true);
      offset += 2;
    }
    
    return buffer;
  }

  private async fetchApi(
    url: string,
    apiKey: string,
    body: object,
    responseMapper: (data: any) => ApiResponse,
    additionalHeaders: Record<string, string> = {},
  ): Promise<ApiResponse> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...additionalHeaders,
    };
    // Only add Authorization header if it's not an anthropic-style key
    if (!('x-api-key' in additionalHeaders)) {
      headers['Authorization'] = `Bearer ${apiKey}`;
    }

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });

    const data = await response.json();
    if (!response.ok) {
        const isQuotaError = response.status === 429;
        const errorPayload = data.error || data;
        const message = errorPayload.message || JSON.stringify(errorPayload);
        
        // Provide user-friendly error messages for common API issues
        if (response.status === 401 || message.includes('API key') || message.includes('authentication')) {
          throw new ApiError('API key is invalid or missing. Please check your API key in Settings.', false);
        }
        
        if (response.status === 403) {
          throw new ApiError('API access denied. Please check your API key permissions and billing status.', false);
        }
        
        // Provider temporarily overloaded/unavailable
        if (response.status === 503 || /overloaded|temporarily unavailable|unavailable/i.test(message)) {
          throw new ApiError('The provider is temporarily overloaded. Please try again shortly or switch to another model/provider.', false);
        }

        if (isQuotaError) {
          throw new ApiError('API quota exceeded. Please check your plan and billing details, or try again later.', true);
        }
        
        // Generic fallback with cleaner message
        const cleanMessage = message.includes('{') && message.includes('}') 
          ? 'API request failed. Please check your settings and try again.' 
          : message;
        
        const errorMessage = `API Error: ${response.statusText} - ${cleanMessage}`;
        throw new ApiError(errorMessage, isQuotaError);
    }
    return responseMapper(data);
  }
}

// --- MAIN APPLICATION CLASS ---
class VoiceNotesApp {
  private mediaRecorder: MediaRecorder | null = null;
  private audioContext!: AudioContext | null;
  private audioWorkletNode: AudioWorkletNode | null = null;
  private recordButton!: HTMLButtonElement;
  private recordingStatus!: HTMLDivElement;
  private rawTranscription!: HTMLDivElement;
  private polishedNote!: HTMLDivElement;
  private polishedNoteX2!: HTMLDivElement;
  // Track the last focused editable chunk so we can redirect paste reliably
  private lastFocusedChunk: HTMLElement | null = null;
  private clearButton!: HTMLButtonElement;
  private copyButton!: HTMLButtonElement;
  private promptSettingsButton!: HTMLButtonElement;
  private transcriptionProviderSelector!: HTMLSelectElement;
  private modelSelector!: HTMLSelectElement;
  private translateButton!: HTMLButtonElement;
  private fileTranscribeButton!: HTMLButtonElement | null;
  private createEmptyNoteButton!: HTMLButtonElement | null;
  private promptModal!: HTMLDivElement;
  private promptModalOverlay!: HTMLDivElement;
  // Per-variant custom prompts (Prompt tab)
  // private customPromptRawTextarea!: HTMLTextAreaElement | null;
  private customPromptV1Textarea!: HTMLTextAreaElement | null;
  private customPromptV2Textarea!: HTMLTextAreaElement | null;
  // private resetPromptRawButton!: HTMLButtonElement | null;
  private resetPromptV1Button!: HTMLButtonElement | null;
  private resetPromptV2Button!: HTMLButtonElement | null;
  private promptSubTabButtons!: NodeListOf<HTMLButtonElement> | null;
  private promptSubTabContents!: NodeListOf<HTMLDivElement> | null;
  private saveSettingsButton!: HTMLButtonElement;
  private cancelPromptButton!: HTMLButtonElement;
  private closePromptModalButton!: HTMLButtonElement;
  private themeToggleButtonModal!: HTMLButtonElement;
  private themeToggleIconModal!: HTMLElement;
  private settingsTabButtons!: NodeListOf<HTMLButtonElement>;
  private settingsTabContents!: NodeListOf<HTMLDivElement>;
  private apiSettingsInputs!: NodeListOf<HTMLInputElement>;
  private targetLanguageSelector!: HTMLSelectElement;
  private localModelsListContainer!: HTMLDivElement;
  private localLanguageSelect: HTMLSelectElement | null = null;
  private localLanguageCustomInput: HTMLInputElement | null = null;
  private hotkeyInput!: HTMLInputElement;
  private hotkeyError!: HTMLDivElement;

  // Ollama-related elements
  private installOllamaButton!: HTMLButtonElement;
  private ollamaStatusMessage!: HTMLSpanElement;
  private ollamaModelsSection!: HTMLDivElement;
  private ollamaModelsList!: HTMLDivElement;
  private ollamaServerUrlInput!: HTMLInputElement;

  private translationResultModal!: HTMLDivElement;
  private translationResultOverlay!: HTMLDivElement;
  private closeTranslationResultModalButton!: HTMLButtonElement;
  // Custom language modal
  private customLanguageModal!: HTMLDivElement | null;
  private customLanguageModalOverlay!: HTMLDivElement | null;
  private closeCustomLanguageModalButton!: HTMLButtonElement | null;
  private cancelCustomLanguageButton!: HTMLButtonElement | null;
  private confirmCustomLanguageButton!: HTMLButtonElement | null;
  private customLanguageGrid!: HTMLDivElement | null;
  private customLanguageSelected: Set<string> = new Set();
  private customLanguagesSaved: Set<string> = new Set();
  private closeTranslationModalButton!: HTMLButtonElement;
  private copyTranslationButton!: HTMLButtonElement;
  private retranslateButton!: HTMLButtonElement | null;
  private modalRecordButton!: HTMLButtonElement | null;
  // Modal recording state (independent of main UI recording)
  private modalIsRecording: boolean = false;
  private modalAudioContext: AudioContext | null = null;
  private modalWorkletNode: AudioWorkletNode | null = null;
  private modalStream: MediaStream | null = null;
  private modalAudioBuffer: Float32Array = new Float32Array(0);
  private modalRecordingSampleRate: number = 16000;
  private originalTextElement!: HTMLParagraphElement;
  private translatedTextElement!: HTMLParagraphElement;
  private translationTargetLanguageElement!: HTMLSpanElement;
  private translationProviderSelector: HTMLSelectElement | null = null;
  private lastSelectionText: string = '';
  private clipboardText: string = '';
  private readonly OLLAMA_SERVER_URL_KEY = 'ollama_server_url';

  // Confirmation dialog elements
  private confirmationModal!: HTMLDivElement;
  private confirmationModalOverlay!: HTMLDivElement;
  private closeConfirmationModalButton!: HTMLButtonElement;
  private cancelConfirmationButton!: HTMLButtonElement;
  private confirmDeleteButton!: HTMLButtonElement;
  private confirmationMessage!: HTMLParagraphElement;

  // Error dialog elements
  private errorModal!: HTMLDivElement;
  private errorModalOverlay!: HTMLDivElement;
  private errorModalTitle!: HTMLHeadingElement;
  private errorModalMessage!: HTMLParagraphElement;
  private closeErrorModalButton!: HTMLButtonElement;
  private confirmErrorButton!: HTMLButtonElement;

  private lastTxPromptTokensElement!: HTMLSpanElement;
  private lastTxCompletionTokensElement!: HTMLSpanElement;
  private lastTxTotalTokensElement!: HTMLSpanElement;
  private totalPromptTokensElement!: HTMLSpanElement;
  private totalCompletionTokensElement!: HTMLSpanElement;
  private totalTotalTokensElement!: HTMLSpanElement;
  private resetUsageButton!: HTMLButtonElement;
  private statsModelNameElement!: HTMLSpanElement;
  private openLogsButton!: HTMLButtonElement;
  private logLevelSelector!: HTMLSelectElement | null;
  private uiZoomSlider!: HTMLInputElement | null;
  private uiZoomValue!: HTMLSpanElement | null;
  private uiLanguageSelector!: HTMLSelectElement | null;
  private uiLanguagePref: UiLanguagePref = 'system';
  private usageStats: UsageStats = {};

  // Overlay prefs controls
  private overlayPositionSelector: HTMLSelectElement | null = null;
  private overlayScaleSlider: HTMLInputElement | null = null;
  private overlayScaleValue: HTMLSpanElement | null = null;
  private overlaySoundEnabledCheckbox: HTMLInputElement | null = null;
  private overlaySoundVolumeSlider: HTMLInputElement | null = null;
  private overlaySoundVolumeValue: HTMLSpanElement | null = null;
  private overlayPrefs: { position: 'bottom-right'|'bottom-left'|'top-right'|'top-left'; scale: number; sound: boolean; volume: number } = { position: 'bottom-right', scale: 1, sound: true, volume: 0.15 };

  private tabButtons!: NodeListOf<HTMLButtonElement>;
  private activeTabIndicator: HTMLDivElement | null = null;
  private noteContents!: NodeListOf<HTMLDivElement>;

  private audioChunks: Blob[] = [];
  private isRecording = false;
  private stream: MediaStream | null = null;
  
  // Simple WAV recording state
  private audioBuffer: Float32Array = new Float32Array(0);
  private recordingSampleRate: number = 16000;
  
  private recordingInterface!: HTMLDivElement;
  private liveRecordingTitle!: HTMLDivElement;
  private liveWaveformCanvas!: HTMLCanvasElement | null;
  private liveWaveformCtx: CanvasRenderingContext2D | null = null;
  private liveRecordingTimerDisplay!: HTMLDivElement;
  private statusIndicatorDiv: HTMLDivElement | null = null;
  private analyserNode: AnalyserNode | null = null;
  private waveformDataArray: Uint8Array | null = null;
  private waveformDrawingId: number | null = null;
  private timerIntervalId: number | null = null;
  private recordingStartTime: number = 0;
  private customPolishPrompt!: string;

  private apiClient!: UniversalApiClient;
  private apiSettings!: ApiSettings;
  private translationSettings!: TranslationSettings;
  private hotkeySettings!: HotkeySettings;
  private localModelsState: { [id: string]: LocalModelState } = {};
  private localModelProviders: { [id: string]: 'cpu' | 'failed' | 'vulkan' | 'metal' | 'cuda' | 'rocm' | 'openvino' | 'directml' | 'gpu' } = {};
  private localModelFallbackReasons: { [id: string]: string | null } = {};
  private stagedActiveLocalModelId: string | null = null;
  private localTranscriptionLanguage: string = 'auto';
  private localTranscriptionLanguageCustom: string = '';
  private ollamaModelsState: { [id: string]: OllamaModelState } = {};
  private selectedOllamaModelId: string | null = null;
  private readonly OLLAMA_MODELS_STATE_KEY = 'ollama_models_state';

  private isHotkeyRecording = false;
  private isListeningForHotkey = false;
  private recordedHotkey: { modifiers: string[], key: string } | null = null;

  // Setup Wizard Elements
  private setupWizardOverlay!: HTMLDivElement;
  private wizardApiKeyStatus!: HTMLDivElement;
  private wizardMicStatus!: HTMLDivElement;
  private wizardMicButton!: HTMLButtonElement;
  private wizardFinishButton!: HTMLButtonElement;


  constructor() {
    try {
        logger.info('VoiceNotesApp constructor started.');
        this.loadApiSettings();
        this.loadTranslationSettings();
        this.loadHotkeySettings();
        this.loadLocalModelsState();
        this.loadLocalModelProviders();
        this.loadLocalModelFallbackReasons();
        this.loadLocalTranscriptionLanguage();

        // --- Cleanup interrupted downloads on startup ---
        let stateWasModified = false;
        for (const modelId in this.localModelsState) {
            if (this.localModelsState.hasOwnProperty(modelId)) {
                const modelState = this.localModelsState[modelId];
                if (modelState.status === 'downloading') {
                    const pct = Number(modelState.progress || 0);
                    if (pct >= 100) {
                        modelState.status = 'downloaded';
                        modelState.progress = 100;
                    } else {
                        logger.warn(`Found interrupted download for model ${modelId}. Resetting status to 'not_downloaded'.`);
                        modelState.status = 'not_downloaded';
                        modelState.progress = 0;
                    }
                    stateWasModified = true;
                }
            }
        }
        if (stateWasModified) {
            this.saveLocalModelsState();
        }

        this.apiClient = new UniversalApiClient(() => this.apiSettings);
        this.customPolishPrompt =
          localStorage.getItem(PROMPT_STORAGE_KEY) || DEFAULT_POLISH_PROMPT;

        // --- Element Querying ---
        this.recordButton = document.getElementById('recordButton') as HTMLButtonElement;
        this.recordingStatus = document.getElementById('recordingStatus') as HTMLDivElement;
        this.rawTranscription = document.getElementById('rawTranscription') as HTMLDivElement;
        this.polishedNote = document.getElementById('polishedNote') as HTMLDivElement;
        this.polishedNoteX2 = document.getElementById('polishedNoteX2') as HTMLDivElement;
        this.clearButton = document.getElementById('clearButton') as HTMLButtonElement;
        this.copyButton = document.getElementById('copyButton') as HTMLButtonElement;
        this.promptSettingsButton = document.getElementById('promptSettingsButton') as HTMLButtonElement;
        this.transcriptionProviderSelector = document.getElementById('transcriptionProviderSelector') as HTMLSelectElement;
        this.modelSelector = document.getElementById('modelSelector') as HTMLSelectElement;
        this.translateButton = document.getElementById('translateButton') as HTMLButtonElement;
  this.fileTranscribeButton = document.getElementById('fileTranscribeButton') as HTMLButtonElement | null;
  this.createEmptyNoteButton = document.getElementById('createEmptyNoteButton') as HTMLButtonElement | null;
  this.fileTranscribeButton?.addEventListener('click', () => this.handleTranscribeAudioFile());
  this.createEmptyNoteButton?.addEventListener('click', () => this.handleCreateEmptyNote());

  this.promptModal = document.getElementById('promptModal') as HTMLDivElement;
  this.promptModalOverlay = document.getElementById('promptModalOverlay') as HTMLDivElement;
  // Query new per-variant prompt fields (may be null if HTML not loaded yet)
  // RAW prompt has been removed from UI
  this.customPromptV1Textarea = document.getElementById('customPromptV1Textarea') as HTMLTextAreaElement | null;
  this.customPromptV2Textarea = document.getElementById('customPromptV2Textarea') as HTMLTextAreaElement | null;
  // RAW reset button removed
  this.resetPromptV1Button = document.getElementById('resetPromptV1Button') as HTMLButtonElement | null;
  this.resetPromptV2Button = document.getElementById('resetPromptV2Button') as HTMLButtonElement | null;
  this.promptSubTabButtons = document.querySelectorAll('.prompt-subtab-button') as NodeListOf<HTMLButtonElement> | null;
  this.promptSubTabContents = document.querySelectorAll('.prompt-subtab-content') as NodeListOf<HTMLDivElement> | null;
        this.saveSettingsButton = document.getElementById('saveSettingsButton') as HTMLButtonElement;
        this.cancelPromptButton = document.getElementById('cancelPromptButton') as HTMLButtonElement;
        this.closePromptModalButton = document.getElementById('closePromptModalButton') as HTMLButtonElement;
        this.themeToggleButtonModal = document.getElementById('themeToggleButtonModal') as HTMLButtonElement;
        this.themeToggleIconModal = this.themeToggleButtonModal.querySelector('i') as HTMLElement;
        this.settingsTabButtons = document.querySelectorAll('.modal-tab-button');
        this.settingsTabContents = document.querySelectorAll('.modal-tab-content');
        this.apiSettingsInputs = document.querySelectorAll('#providersTabContent input');
  this.targetLanguageSelector = document.getElementById('targetLanguageSelector') as HTMLSelectElement;
        this.localModelsListContainer = document.getElementById('localModelsList') as HTMLDivElement;
        this.localLanguageSelect = document.getElementById('localLanguageSelect') as HTMLSelectElement | null;
        this.localLanguageCustomInput = document.getElementById('localLanguageCustom') as HTMLInputElement | null;
        this.hotkeyInput = document.getElementById('hotkeyInput') as HTMLInputElement;
        this.hotkeyError = document.getElementById('hotkeyError') as HTMLDivElement;
  this.translationResultModal = document.getElementById('translationResultModal') as HTMLDivElement;
        this.translationResultOverlay = document.getElementById('translationResultModalOverlay') as HTMLDivElement;
        this.closeTranslationResultModalButton = document.getElementById('closeTranslationResultModalButton') as HTMLButtonElement;
        this.closeTranslationModalButton = document.getElementById('closeTranslationModalButton') as HTMLButtonElement;
        this.copyTranslationButton = document.getElementById('copyTranslationButton') as HTMLButtonElement;
  this.originalTextElement = document.getElementById('originalText') as HTMLParagraphElement;
        this.translatedTextElement = document.getElementById('translatedText') as HTMLParagraphElement;
        this.translationTargetLanguageElement = document.getElementById('translationTargetLanguage') as HTMLSpanElement;
  this.retranslateButton = document.getElementById('retranslateButton') as HTMLButtonElement | null;
  this.modalRecordButton = document.getElementById('modalRecordButton') as HTMLButtonElement | null;
  // Custom language modal elements
  this.customLanguageModal = document.getElementById('customLanguageModal') as HTMLDivElement | null;
  this.customLanguageModalOverlay = document.getElementById('customLanguageModalOverlay') as HTMLDivElement | null;
  this.closeCustomLanguageModalButton = document.getElementById('closeCustomLanguageModalButton') as HTMLButtonElement | null;
  this.cancelCustomLanguageButton = document.getElementById('cancelCustomLanguageButton') as HTMLButtonElement | null;
  this.confirmCustomLanguageButton = document.getElementById('confirmCustomLanguageButton') as HTMLButtonElement | null;
  this.customLanguageGrid = document.getElementById('customLanguageGrid') as HTMLDivElement | null;
        this.lastTxPromptTokensElement = document.getElementById('lastTxPromptTokens') as HTMLSpanElement;
        this.lastTxCompletionTokensElement = document.getElementById('lastTxCompletionTokens') as HTMLSpanElement;
        this.lastTxTotalTokensElement = document.getElementById('lastTxTotalTokens') as HTMLSpanElement;
        this.totalPromptTokensElement = document.getElementById('totalPromptTokens') as HTMLSpanElement;
        this.totalCompletionTokensElement = document.getElementById('totalCompletionTokens') as HTMLSpanElement;
        this.totalTotalTokensElement = document.getElementById('totalTotalTokens') as HTMLSpanElement;
        this.resetUsageButton = document.getElementById('resetUsageButton') as HTMLButtonElement;
        this.statsModelNameElement = document.getElementById('statsModelName') as HTMLSpanElement;
        this.openLogsButton = document.getElementById('openLogsButton') as HTMLButtonElement;
        this.logLevelSelector = document.getElementById('logLevelSelector') as HTMLSelectElement | null;
        this.uiZoomSlider = document.getElementById('uiZoomSlider') as HTMLInputElement | null;
        this.uiZoomValue = document.getElementById('uiZoomValue') as HTMLSpanElement | null;
  this.uiLanguageSelector = document.getElementById('uiLanguageSelector') as HTMLSelectElement | null;
  // Overlay prefs controls
  this.overlayPositionSelector = document.getElementById('overlayPositionSelector') as HTMLSelectElement | null;
  this.overlayScaleSlider = document.getElementById('overlayScaleSlider') as HTMLInputElement | null;
  this.overlayScaleValue = document.getElementById('overlayScaleValue') as HTMLSpanElement | null;
  this.overlaySoundEnabledCheckbox = document.getElementById('overlaySoundEnabled') as HTMLInputElement | null;
  this.overlaySoundVolumeSlider = document.getElementById('overlaySoundVolume') as HTMLInputElement | null;
  this.overlaySoundVolumeValue = document.getElementById('overlaySoundVolumeValue') as HTMLSpanElement | null;
        const tabNav = document.querySelector('.tab-navigation');
        this.tabButtons = tabNav!.querySelectorAll('.tab-button');
        this.activeTabIndicator = tabNav!.querySelector('.active-tab-indicator') as HTMLDivElement | null;
        this.noteContents = document.querySelectorAll('.note-content');
        this.recordingInterface = document.querySelector('.recording-interface') as HTMLDivElement;
        this.liveRecordingTitle = document.getElementById('liveRecordingTitle') as HTMLDivElement;
        this.liveWaveformCanvas = document.getElementById('liveWaveformCanvas') as HTMLCanvasElement;
        this.liveRecordingTimerDisplay = document.getElementById('liveRecordingTimerDisplay') as HTMLDivElement;
        this.setupWizardOverlay = document.getElementById('setupWizardOverlay') as HTMLDivElement;
        this.wizardApiKeyStatus = document.getElementById('wizardApiKeyStatus') as HTMLDivElement;
        this.wizardMicStatus = document.getElementById('wizardMicStatus') as HTMLDivElement;
        this.wizardMicButton = document.getElementById('wizardMicButton') as HTMLButtonElement;
        this.wizardFinishButton = document.getElementById('wizardFinishButton') as HTMLButtonElement;

        // Wire prompt sub-tab handlers if present
        if (this.promptSubTabButtons) {
          this.promptSubTabButtons.forEach((btn) =>
            btn.addEventListener('click', () => this.setActivePromptSubTab(btn))
          );
        }
        
        // Confirmation dialog elements
        this.confirmationModal = document.getElementById('confirmationModal') as HTMLDivElement;
        this.confirmationModalOverlay = document.getElementById('confirmationModalOverlay') as HTMLDivElement;
        this.closeConfirmationModalButton = document.getElementById('closeConfirmationModalButton') as HTMLButtonElement;
        this.cancelConfirmationButton = document.getElementById('cancelConfirmationButton') as HTMLButtonElement;
        this.confirmDeleteButton = document.getElementById('confirmDeleteButton') as HTMLButtonElement;
        this.confirmationMessage = document.getElementById('confirmationMessage') as HTMLParagraphElement;
        
        // Error dialog elements
        this.errorModal = document.getElementById('errorModal') as HTMLDivElement;
        this.errorModalOverlay = document.getElementById('errorModalOverlay') as HTMLDivElement;
        this.errorModalTitle = document.getElementById('errorModalTitle') as HTMLHeadingElement;
        this.errorModalMessage = document.getElementById('errorModalMessage') as HTMLParagraphElement;
        this.closeErrorModalButton = document.getElementById('closeErrorModalButton') as HTMLButtonElement;
        this.confirmErrorButton = document.getElementById('confirmErrorButton') as HTMLButtonElement;

        // Ollama elements
        this.installOllamaButton = document.getElementById('installOllamaButton') as HTMLButtonElement;
        this.ollamaStatusMessage = document.getElementById('ollamaStatusMessage') as HTMLSpanElement;
        this.ollamaModelsSection = document.getElementById('ollamaModelsSection') as HTMLDivElement;
        this.ollamaModelsList = document.getElementById('ollamaModelsList') as HTMLDivElement;
        this.ollamaServerUrlInput = document.getElementById('ollamaServerUrl') as HTMLInputElement;
        // Initialize persisted Ollama URL
        try {
          const saved = localStorage.getItem(this.OLLAMA_SERVER_URL_KEY);
          if (saved && this.ollamaServerUrlInput) this.ollamaServerUrlInput.value = this.normalizeOllamaUrl(saved);
        } catch {}

        this.initLocalLanguageControl();

        // This check is crucial for debugging silent startup failures
        if (!this.recordButton) throw new Error("Element with ID 'recordButton' not found.");

        // --- Custom Select Instantiation ---
        new CustomSelect(this.transcriptionProviderSelector);
        new CustomSelect(this.modelSelector);
        new CustomSelect(document.getElementById('hotkeyTarget') as HTMLSelectElement);
        new CustomSelect(document.getElementById('hotkeyMode') as HTMLSelectElement);
        // Initialize custom select for translation target
        if (this.targetLanguageSelector) {
          new CustomSelect(this.targetLanguageSelector);
          // Load and insert any persisted custom languages into the main dropdown
          this.loadCustomLanguages();
          this.ensureCustomLanguagesInDropdown();
          this.targetLanguageSelector.addEventListener('change', () => {
            this.translationSettings.targetLanguage = this.targetLanguageSelector.value;
            try { localStorage.setItem(TRANSLATION_SETTINGS_KEY, JSON.stringify(this.translationSettings)); } catch {}
            if (this.translationTargetLanguageElement) {
              this.translationTargetLanguageElement.textContent = this.translationSettings.targetLanguage;
            }
          });
        }
        if (this.logLevelSelector) {
          new CustomSelect(this.logLevelSelector);
        }
        if (this.uiLanguageSelector) {
          this.populateUiLanguageSelector();
          new CustomSelect(this.uiLanguageSelector);
        }

  // Initialize overlay prefs UI
  this.loadOverlayPrefs();
  this.applyOverlayPrefsToUi();
  // Match app-wide custom select UI
  if (this.overlayPositionSelector) new CustomSelect(this.overlayPositionSelector);

        // --- Initializations ---
        if (this.liveWaveformCanvas) this.liveWaveformCtx = this.liveWaveformCanvas.getContext('2d');
        if (this.recordingInterface) this.statusIndicatorDiv = this.recordingInterface.querySelector('.status-indicator') as HTMLDivElement | null;

        this.bindEventListeners();
        this.bindIpcListeners();
        this.bindWizardEventListeners();
        
        // Expose methods globally for API client access
        (window as any).voiceNotesApp = {
          getOllamaServerUrl: () => this.getOllamaServerUrl()
        };
  this.initTheme();
  this.initUiZoom();
  this.initUiLanguage();
        this.clearAllContent();
        this.loadUsageStats();
        this.updateLastTransactionDisplay(0, 0);
        this.setupTabs();
        this.setupSettingsTabs();
        
        // Load Ollama models state before updating UI
        this.loadOllamaModelsState();
        this.loadSelectedOllamaModel();
        
        this.updateModelSelector();
        this.updateTranscriptionProviderSelector();
        this.updateStatsDisplay();
        this.checkApiConnectivity();
  // Initialize log level selector
  this.initLogLevelSelector();
        // Ensure the custom select shows the current value
        if (this.logLevelSelector) {
          this.logLevelSelector.dispatchEvent(new Event('change'));
        }
        
        // Check for available Ollama models at startup
        this.checkOllamaStatusSilently();
        if (ipcRenderer) {
          ipcRenderer.send('update-hotkey', this.hotkeySettings);
        }

        if (localStorage.getItem(SETUP_WIZARD_COMPLETED_KEY) !== 'true') {
            this.startSetupWizard();
        }
        logger.info('VoiceNotesApp constructor finished successfully.');
    } catch(error) {
        logger.error('Fatal error in VoiceNotesApp constructor:', error);
        alert('A critical error occurred while initializing the application. Please check the logs for more details.');
    }
  }

  private bindEventListeners(): void {
  this.recordButton.addEventListener('click', () => this.toggleRecording());
    this.clearButton.addEventListener('click', () => this.clearAllContent());
    this.themeToggleButtonModal.addEventListener('click', () =>
      this.toggleTheme(),
    );
    this.copyButton.addEventListener('click', () => this.copyPolishedNote());
    this.promptSettingsButton.addEventListener('click', () =>
      this.openPromptModal(),
    );
        this.saveSettingsButton.addEventListener('click', () => this.saveSettings());
        // Reset prompt buttons
  // RAW reset handler removed
        this.resetPromptV1Button?.addEventListener('click', () => {
          if (this.customPromptV1Textarea) this.customPromptV1Textarea.value = DEFAULT_PROMPT_V1;
          try { localStorage.removeItem(PROMPT_STORAGE_KEY_V1); } catch {}
        });
        this.resetPromptV2Button?.addEventListener('click', () => {
          if (this.customPromptV2Textarea) this.customPromptV2Textarea.value = DEFAULT_PROMPT_V2;
          try { localStorage.removeItem(PROMPT_STORAGE_KEY_V2); } catch {}
        });
    this.cancelPromptButton.addEventListener('click', () =>
      this.closePromptModal(),
    );
    this.closePromptModalButton.addEventListener('click', () =>
      this.closePromptModal(),
    );
    this.promptModalOverlay.addEventListener('click', () =>
      this.closePromptModal(),
    );
    this.resetUsageButton.addEventListener('click', () =>
      this.resetModelUsage(),
    );
    this.openLogsButton.addEventListener('click', () => {
        ipcRenderer?.send('open-log-file');
    });
    // Log level selector change
    if (this.logLevelSelector) {
      this.logLevelSelector.addEventListener('change', () => {
        const level = (this.logLevelSelector as HTMLSelectElement).value as 'error' | 'warn' | 'info' | 'debug';
        localStorage.setItem('appLogLevel', level);
        (window as any).setAppLogLevel?.(level);
      });
    }
    // UI zoom slider
    if (this.uiZoomSlider) {
      this.uiZoomSlider.addEventListener('input', () => this.applyUiZoom());
    }
    // UI language selector
    if (this.uiLanguageSelector) {
      this.uiLanguageSelector.addEventListener('change', () => this.onUiLanguageChanged());
    }
    // Overlay prefs bindings
    if (this.overlayPositionSelector) {
      this.overlayPositionSelector.addEventListener('change', () => {
        this.overlayPrefs.position = (this.overlayPositionSelector!.value as any) || 'bottom-right';
        this.saveOverlayPrefsAndNotify();
      });
    }
    if (this.overlayScaleSlider) {
      this.overlayScaleSlider.addEventListener('input', () => {
        const v = parseFloat(this.overlayScaleSlider!.value) || 1;
        this.overlayPrefs.scale = Math.min(1.6, Math.max(0.8, v));
        if (this.overlayScaleValue) this.overlayScaleValue.textContent = `${Math.round(this.overlayPrefs.scale * 100)}%`;
        this.saveOverlayPrefsAndNotify();
      });
    }
    if (this.overlaySoundEnabledCheckbox) {
      this.overlaySoundEnabledCheckbox.addEventListener('change', () => {
        this.overlayPrefs.sound = !!this.overlaySoundEnabledCheckbox!.checked;
        this.saveOverlayPrefsAndNotify();
      });
    }
    if (this.overlaySoundVolumeSlider) {
      // Snap by 1% when <=5, then 5% above 5
      const snapVolume = (n: number) => {
        if (n <= 5) return Math.max(0, Math.min(5, Math.round(n))); // 0..5 by 1
        return Math.min(100, Math.ceil(n / 5) * 5); // 10..100 by 5
      };
      this.overlaySoundVolumeSlider.addEventListener('input', () => {
        let raw = parseInt(this.overlaySoundVolumeSlider!.value || '15', 10);
        const snapped = snapVolume(raw);
        if (snapped !== raw) {
          this.overlaySoundVolumeSlider!.value = String(snapped);
        }
        this.overlayPrefs.volume = Math.max(0, Math.min(1, snapped / 100));
        if (this.overlaySoundVolumeValue) this.overlaySoundVolumeValue.textContent = `${snapped}%`;
        this.saveOverlayPrefsAndNotify();
      });
    }
    this.modelSelector.addEventListener('change', () => {
      this.updateStatsDisplay();
      this.handleModelSelectorChange();
      localStorage.setItem(SELECTED_POLISHING_MODEL_KEY, this.modelSelector.value);
      this.checkApiConnectivity();
      this.updateTranslateButtonState();
    });
    window.addEventListener('resize', this.handleResize.bind(this));

    // Drag & Drop audio files onto the app window → transcribe
    if (inElectron()) {
      document.addEventListener('dragover', (e) => {
        try { e.preventDefault(); (e as DragEvent).dataTransfer!.dropEffect = 'copy'; } catch {}
      });
      document.addEventListener('drop', async (e) => {
        try {
          e.preventDefault();
          const dt = (e as DragEvent).dataTransfer;
          const files = Array.from(dt?.files || []);
          if (!files.length) return;
          const audioPaths: string[] = [];
          const re = /\.(wav|mp3|m4a|flac|ogg|opus|webm)$/i;
          for (const f of files) {
            const name = (f as any).name || '';
            const p = (f as any).path || '';
            if (re.test(name) && p) audioPaths.push(p);
          }
          if (audioPaths.length) await this.handleTranscribeDroppedFiles(audioPaths);
        } catch {}
      });
    }

    // Hotkey Listeners
    this.hotkeyInput.addEventListener('click', () => this.startListeningForHotkey());
    this.hotkeyInput.addEventListener('keydown', (e) => this.handleHotkeyKeyDown(e));
    this.hotkeyInput.addEventListener('blur', () => this.stopListeningForHotkey());
    
    // Translation Listeners
  // Preserve selection when clicking Translate so it doesn't collapse
  this.translateButton.addEventListener('mousedown', (e) => e.preventDefault());
  this.translateButton.addEventListener('click', () => this.handleTranslation());
  document.addEventListener('selectionchange', () => this.updateTranslateButtonState());
  // Watch clipboard in the background to enable translation when text is copied
  this.startClipboardWatcher();
  this.closeTranslationResultModalButton.addEventListener('click', () => this.closeTranslationModal());
    this.closeTranslationModalButton.addEventListener('click', () => this.closeTranslationModal());
    this.translationResultOverlay.addEventListener('click', () => this.closeTranslationModal());
  this.copyTranslationButton.addEventListener('click', () => this.copyTranslatedText());
  this.retranslateButton?.addEventListener('click', () => this.retranslateFromModal());
  this.modalRecordButton?.addEventListener('click', () => this.toggleModalRecording());
  // Custom language modal wiring
  if (this.closeCustomLanguageModalButton) this.closeCustomLanguageModalButton.addEventListener('click', () => this.hideCustomLanguageModal());
  if (this.cancelCustomLanguageButton) this.cancelCustomLanguageButton.addEventListener('click', () => this.hideCustomLanguageModal());
  if (this.customLanguageModalOverlay) this.customLanguageModalOverlay.addEventListener('click', () => this.hideCustomLanguageModal());
  if (this.confirmCustomLanguageButton) this.confirmCustomLanguageButton.addEventListener('click', () => this.applyCustomLanguage());

    // Confirmation Dialog Listeners
    this.closeConfirmationModalButton.addEventListener('click', () => this.closeConfirmationModal());
    this.cancelConfirmationButton.addEventListener('click', () => this.closeConfirmationModal());
    this.confirmDeleteButton.addEventListener('click', () => this.handleConfirmDelete());
    this.confirmationModalOverlay.addEventListener('click', () => this.closeConfirmationModal());

    // Error Dialog Listeners
    this.closeErrorModalButton.addEventListener('click', () => this.closeErrorDialog());
    this.confirmErrorButton.addEventListener('click', () => this.closeErrorDialog());
    this.errorModalOverlay.addEventListener('click', () => this.closeErrorDialog());

    // Delegated copy/polish for per-chunk buttons across all note areas
    const wrapper = document.querySelector('.note-content-wrapper') as HTMLElement | null;
    if (wrapper) {
      // Make wrapper itself non-editable; only .note-chunk are editable
      (wrapper as any).setAttribute?.('contenteditable', 'false');

      // Keep bubble buttons from stealing focus; always keep caret in the chunk
      wrapper.addEventListener('mousedown', (e) => {
        const t = e.target as HTMLElement;
        const bubble = t.closest('.copy-bubble-btn') as HTMLElement | null;
        if (!bubble) return;
        e.preventDefault(); // prevent focus landing on the button
        const section = bubble.closest('.note-section') as HTMLElement | null;
        const chunk = section?.querySelector('.note-chunk') as HTMLElement | null;
        if (chunk) {
          chunk.focus();
          const sel = window.getSelection();
          if (sel) {
            sel.selectAllChildren(chunk);
            sel.collapseToEnd();
          }
        }
      }, true);

      // If user clicks inside a note-chunk, let the browser place the caret at the click point.
      // If user clicks inside a note section but outside the chunk (e.g., padding), focus chunk and place caret at end.
      wrapper.addEventListener('mousedown', (e) => {
        const t = e.target as HTMLElement;
        if (t.closest('.copy-bubble-btn')) return; // handled above
        const clickedChunk = t.closest('.note-chunk') as HTMLElement | null;
        if (clickedChunk) {
          // Allow native caret placement; ensure the chunk receives focus but don't override selection
          // Focus happens naturally on mousedown; no action needed.
          return;
        }
        const section = t.closest('.note-section') as HTMLElement | null;
        const chunk = section?.querySelector('.note-chunk') as HTMLElement | null;
        if (!chunk) return;
        // Defer focus to end of frame to avoid selection glitches; put caret at end as a sensible fallback
        requestAnimationFrame(() => {
          chunk.focus();
          const sel = window.getSelection();
          if (sel) { sel.selectAllChildren(chunk); sel.collapseToEnd(); }
        });
      }, true);

      // Track last focused chunk
      wrapper.addEventListener('focusin', (e) => {
        const t = e.target as HTMLElement;
        const chunk = t.closest('.note-chunk') as HTMLElement | null;
        if (chunk) this.lastFocusedChunk = chunk;
      }, true);

      wrapper.addEventListener('click', (e) => {
        const target = e.target as HTMLElement;
        const btn = target.closest('.copy-bubble-btn') as HTMLElement | null;
        if (!btn) return;
        e.stopPropagation();
        const section = btn.closest('.note-section') as HTMLElement | null;
        const chunk = section?.querySelector('.note-chunk') as HTMLElement | null;
        if (!chunk && !btn.classList.contains('delete')) return;
  // Never let buttons receive focus
  (btn as HTMLButtonElement).setAttribute('tabindex', '-1');
  (btn as HTMLButtonElement).setAttribute('aria-hidden', 'true');
        if (btn.classList.contains('delete')) {
          // Remove this note-section and tidy separators/placeholder
          const container = section?.parentElement as HTMLElement | null; // .note-content area
          if (!section || !container) return;
          const prev = section.previousElementSibling as HTMLElement | null;
          const next = section.nextElementSibling as HTMLElement | null;
          // Remove leading or trailing <hr> as needed
          // If previous sibling is an <hr>, remove it (we're deleting the section after it)
          if (prev && prev.nodeName === 'HR') prev.remove();
          // If next sibling is an <hr>, and there was also a previous hr (handled above), or this section was first, remove dangling hr
          else if (next && next.nodeName === 'HR') next.remove();
          // Remove the section itself
          section.remove();
          // If container becomes empty (no .note-section), restore placeholder
          const hasAny = container.querySelector('.note-section');
          if (!hasAny) {
            const ph = container.getAttribute('placeholder') || '';
            container.innerHTML = ph;
            container.classList.add('placeholder-active');
          }
          return;
        }
        // For copy/polish actions, ensure we have a chunk
        if (!chunk) return;
        if (btn.classList.contains('polish')) {
          // Polish this chunk text using the selected model.
          // Behavior:
          // - If invoked from Raw, generate BOTH Variant 1 and Variant 2 and append to their areas.
          // - If invoked from within Variant 1, re-polish with Variant 1 prompt and replace in-place.
          // - If invoked from within Variant 2, re-polish with Variant 2 prompt and replace in-place.
          const text = (chunk.innerText || '').trim();
          if (!text) return;
          if (!this.modelSelector.value) {
            alert('Select a polishing model first in the header.');
            return;
          }
          const icon = btn.querySelector('i');
          const prevClass = icon?.className || '';
          if (icon) icon.className = 'fas fa-spinner fa-spin';

          const inRaw = !!chunk.closest('#rawTranscription');
          const inV1  = !!chunk.closest('#polishedNote');
          const inV2  = !!chunk.closest('#polishedNoteX2');

          const tasks: Array<Promise<void>> = [];
          if (inRaw) {
            tasks.push(
              this.getPolishedNote('standard', text)
                .then(r => { const out = (r?.text || '').trim(); if (out) this.appendToContentArea(this.polishedNote, out); })
                .catch(() => { /* ignore per-variant error here */ })
            );
            tasks.push(
              this.getPolishedNote('x2', text)
                .then(r => { const out = (r?.text || '').trim(); if (out) this.appendToContentArea(this.polishedNoteX2, out); })
                .catch(() => { /* ignore per-variant error here */ })
            );
          } else if (inV2) {
            tasks.push(
              this.getPolishedNote('x2', text)
                .then(r => { const out = (r?.text || '').trim(); if (out) chunk.textContent = out; })
                .catch(() => { /* ignore; keep original text */ })
            );
          } else {
            // default to Variant 1 replacement when not Raw and not explicitly inside Variant 2
            tasks.push(
              this.getPolishedNote('standard', text)
                .then(r => { const out = (r?.text || '').trim(); if (out) chunk.textContent = out; })
                .catch(() => { /* ignore; keep original text */ })
            );
          }

          Promise.allSettled(tasks)
            .catch(() => {
              alert('Polishing failed. Please check your model selection and try again.');
            })
            .finally(() => {
              if (icon) icon.className = prevClass;
            });
          return;
        } else {
          // Copy text and show brief visual confirmation via class toggle
          navigator.clipboard.writeText(chunk.innerText || '')
            .then(() => {
              const note = btn.closest('.note-content') as HTMLElement | null;
              const existingTimer = (btn as any)._copyTimer as number | undefined;
              if (existingTimer) clearTimeout(existingTimer);
              btn.classList.add('copied');
              if (note) note.classList.add('suppress-caret');
              const timer = window.setTimeout(() => {
                btn.classList.remove('copied');
                if (note) note.classList.remove('suppress-caret');
                (btn as any)._copyTimer = undefined;
              }, 1000);
              (btn as any)._copyTimer = timer;
            })
            .catch(() => {
              // Silently ignore copy failures
            });
        }
      });

      // Prevent backspace/delete on empty chunk from merging with previous/next DOM outside chunk
      wrapper.addEventListener('keydown', (e: KeyboardEvent) => {
        const target = e.target as HTMLElement | null;
        const chunk = target?.closest?.('.note-chunk') as HTMLElement | null;
        if (!chunk) return;
        if ((e.key === 'Backspace' || e.key === 'Delete')) {
          const text = (chunk.innerText || '').replace(/\u200B/g, '').trim();
          // If chunk is empty and we press Backspace/Delete, keep cursor here and do nothing
          if (!text) {
            e.preventDefault();
            // Ensure a zero-width space to anchor caret
            if (!chunk.textContent) chunk.textContent = '\u200B';
            requestAnimationFrame(() => {
              chunk.focus();
              const sel = window.getSelection();
              if (sel) { sel.selectAllChildren(chunk); sel.collapseToEnd(); }
            });
          }
        }
      }, true);
    }

    // If paste happens while focus isn't inside an editable chunk, redirect it into the best chunk
    document.addEventListener('paste', (e: ClipboardEvent) => {
      const active = (document.activeElement as HTMLElement | null);
      // Allow native paste for inputs, textareas, or other contenteditable regions (e.g., translation modal)
      if (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) return;
      if (active?.isContentEditable && !active.closest('.note-chunk')) return;

      const eventTarget = e.target as HTMLElement | null;
      let targetChunk = eventTarget?.closest('.note-chunk') as HTMLElement | null;

      // Prefer: active .note-chunk → sibling of focused bubble → last focused chunk → newest Raw chunk
      if (!targetChunk && active) {
        const activeChunk = active.closest?.('.note-chunk') as HTMLElement | null;
        if (activeChunk) targetChunk = activeChunk;
      }
      if (!targetChunk && active) {
        const bubble = active.closest?.('.copy-bubble-btn') as HTMLElement | null;
        if (bubble) {
          const section = bubble.closest('.note-section') as HTMLElement | null;
          targetChunk = section?.querySelector('.note-chunk') as HTMLElement | null;
        }
      }
      if (!targetChunk && this.lastFocusedChunk) {
        targetChunk = this.lastFocusedChunk;
      }
      if (!targetChunk) {
        const raw = this.rawTranscription as HTMLElement | null;
        targetChunk = raw?.querySelector('.note-section:last-of-type .note-chunk') as HTMLElement | null;
      }
      if (!targetChunk) return;

      e.preventDefault();
      const text = (e.clipboardData?.getData('text/plain') || (window as any).clipboardData?.getData('Text') || '') as string;
      if (!text) return;

      if (targetChunk.classList.contains('placeholder-active')) {
        targetChunk.innerHTML = '';
        targetChunk.classList.remove('placeholder-active');
      }

      const selection = window.getSelection();
      const ensureRangeInsideChunk = () => {
        if (!selection) return;
        let range = selection.rangeCount ? selection.getRangeAt(0) : null;
        const inside = range && targetChunk.contains(range.commonAncestorContainer);
        if (!inside) {
          range = document.createRange();
          range.selectNodeContents(targetChunk);
          range.collapse(false);
          selection.removeAllRanges();
          selection.addRange(range);
        }
      };

      targetChunk.focus();
      ensureRangeInsideChunk();

      let inserted = false;
      try {
        inserted = document.execCommand('insertText', false, text);
      } catch {
        inserted = false;
      }

      if (!inserted && selection) {
        ensureRangeInsideChunk();
        if (selection.rangeCount) {
          const range = selection.getRangeAt(0);
          range.deleteContents();
          const textNodes = text.split(/\r?\n/);
          textNodes.forEach((segment, index) => {
            if (segment) {
              const node = document.createTextNode(segment);
              range.insertNode(node);
              range.setStartAfter(node);
              range.collapse(true);
            }
            if (index < textNodes.length - 1) {
              const br = document.createElement('br');
              range.insertNode(br);
              range.setStartAfter(br);
              range.collapse(true);
            }
          });
          selection.removeAllRanges();
          selection.addRange(range);
        } else {
          targetChunk.textContent = (targetChunk.textContent || '') + text;
        }
      }

      this.lastFocusedChunk = targetChunk;
    }, true);

    document.addEventListener('keydown', (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const isEditable = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target?.isContentEditable;
      if (!isEditable) return;
      if (!e.altKey || e.metaKey || e.ctrlKey) return;
      const key = e.key.toLowerCase();
      if (key === 'z') {
        e.preventDefault();
        try { document.execCommand('undo'); } catch {}
      } else if (key === 'y') {
        e.preventDefault();
        try { document.execCommand('redo'); } catch {}
      }
    }, true);

    // API Key Button Listeners
    document.getElementById('getGoogleApiKey')?.addEventListener('click', () => this.openApiKeyUrl('google'));
    document.getElementById('getOpenaiApiKey')?.addEventListener('click', () => this.openApiKeyUrl('openai'));
    document.getElementById('getAnthropicApiKey')?.addEventListener('click', () => this.openApiKeyUrl('anthropic'));

    // Ollama Button Listener
    this.installOllamaButton?.addEventListener('click', () => this.handleOllamaInstallClick());
    
    // Ollama Server URL change listener with persistence
    this.ollamaServerUrlInput?.addEventListener('blur', () => {
      if (!this.ollamaServerUrlInput) return;
      const normalized = this.normalizeOllamaUrl(this.ollamaServerUrlInput.value || '');
      this.ollamaServerUrlInput.value = normalized;
      try { localStorage.setItem(this.OLLAMA_SERVER_URL_KEY, normalized); } catch {}
      // Re-check Ollama status when URL changes
      if (this.settingsTabButtons) {
        const localLlmTab = Array.from(this.settingsTabButtons).find(btn => btn.getAttribute('data-tab') === 'localLlm');
        if (localLlmTab?.classList.contains('active')) this.checkOllamaStatus();
      }
    });
  }
  private initLogLevelSelector(): void {
    if (!this.logLevelSelector) return;
    const stored = (localStorage.getItem('appLogLevel') || 'warn') as 'error' | 'warn' | 'info' | 'debug';
    this.logLevelSelector.value = stored;
    if ((logger as any).setLevel) (logger as any).setLevel(stored);
    (window as any).setAppLogLevel?.(stored);
  }
  
  private bindIpcListeners(): void {
    if (!ipcRenderer) return;

    ipcRenderer.on('global-shortcut-triggered', () => {
        logger.info('Global shortcut IPC message received.');
        if (this.hotkeySettings.enabled && !this.isRecording) {
            this.isHotkeyRecording = true; // Set flag before toggling
            this.toggleRecording();
        } else if (this.isRecording) {
            // Stop recording regardless of how it was started
            this.toggleRecording();
        }
    });

    ipcRenderer.on('hotkey-registration-failed', (event: IpcRendererEvent, { hotkey }: { hotkey: string }) => {
        logger.warn(`Failed to register hotkey: ${hotkey}`);
        this.hotkeyError.textContent = `Could not register "${hotkey}". It may be used by another application.`;
        this.hotkeyError.style.display = 'block';
    });

    ipcRenderer.on('hotkey-registration-success', () => {
        this.hotkeyError.style.display = 'none';
    });

    ipcRenderer.on('download-complete', (event: IpcRendererEvent, payload: any) => {
      const id = payload?.id as string; const path = payload?.path as string | null;
      if (!id) { logger.warn('download-complete payload missing id', payload); return; }
      const modelState = this.localModelsState[id] || { status: 'not_downloaded', progress: 0, path: null };
      modelState.status = 'downloaded';
      modelState.progress = 100;
      modelState.path = path || modelState.path;
      this.localModelsState[id] = modelState;
      this.saveLocalModelsState();
      this.renderLocalModelsList();
    });

    ipcRenderer.on('download-failed', (event: IpcRendererEvent, payload: any) => {
      const id = payload?.id as string; const error = payload?.error as string | undefined;
      if (!id) { logger.warn('download-failed payload missing id', payload); return; }
      logger.error(`Download failed for model ${id}:`, error);
      const modelState = this.localModelsState[id] || { status: 'not_downloaded', progress: 0, path: null };
      modelState.status = 'failed';
      modelState.progress = 0;
      this.localModelsState[id] = modelState;
      this.saveLocalModelsState();
      this.renderLocalModelsList();
    });

    ipcRenderer.on('model_loaded', (_event: IpcRendererEvent, payload: any) => {
      const modelId = payload?.modelId || payload?.id;
      if (!modelId) return;
      const state: LocalModelState = this.localModelsState[modelId] || { status: 'not_downloaded', progress: 0, path: null };
      if (state.status !== 'downloaded' || state.progress < 100) {
        state.status = 'downloaded';
        state.progress = 100;
        this.localModelsState[modelId] = state;
        this.saveLocalModelsState();
        this.renderLocalModelsList();
      }
    });

    ipcRenderer.on('model_load_error', (_event: IpcRendererEvent, payload: any) => {
      const modelId = payload?.modelId || payload?.id;
      if (!modelId) return;
      const state: LocalModelState = this.localModelsState[modelId] || { status: 'not_downloaded', progress: 0, path: null };
      state.status = 'failed';
      this.localModelsState[modelId] = state;
      this.saveLocalModelsState();
      this.renderLocalModelsList();
    });

    // Progress updates from main process for Local Models (Whisper)
    ipcRenderer.on('download-progress', (_event: IpcRendererEvent, payload: any) => {
      // payload can be { modelId, progress } or { modelId, status: 'start' }
      const modelId = payload?.modelId || payload?.id;
      if (!modelId) return;
      const state = this.localModelsState[modelId] || { status: 'not_downloaded', progress: 0, path: null } as LocalModelState;

      // Initialize on start signal
      if (payload?.status === 'start') {
        if (state.status !== 'downloaded') {
          state.status = 'downloading';
          state.progress = 0;
          this.localModelsState[modelId] = state;
          this.saveLocalModelsState();
          this.renderLocalModelsList();
        }
        return;
      }

  const next = Math.max(0, Math.min(100, Number(payload?.progress ?? 0)));
  // Update every 1%
  if (state.status === 'downloaded' && state.progress >= 100 && next < 100 && !payload?.status) return;
  if (Math.round(state.progress || 0) === Math.round(next) && next !== 100) return;

      if (payload?.status === 'complete' || next >= 100) {
        state.status = 'downloaded';
        state.progress = 100;
      } else {
        state.status = 'downloading';
        state.progress = next;
      }
      this.localModelsState[modelId] = state;
      this.saveLocalModelsState();
      this.renderLocalModelsList();
    });

    ipcRenderer.on('local-model-removed', (event: IpcRendererEvent, payload: any) => {
      const id = payload?.id as string; const success = !!payload?.success; const error = payload?.error as string | undefined;
      if (!id) { logger.warn('local-model-removed payload missing id', payload); return; }
      if (success) {
        logger.info(`Successfully removed model ${id}`);
        if (this.localModelsState[id]) {
            this.localModelsState[id].status = 'not_downloaded';
            this.localModelsState[id].progress = 0;
            this.localModelsState[id].path = null;
        }
        if (this.localModelProviders[id]) {
            delete this.localModelProviders[id];
        }
        if (this.localModelFallbackReasons[id]) {
            delete this.localModelFallbackReasons[id];
        }
        if (this.apiSettings.local.activeModelId === id) {
            this.apiSettings.local.activeModelId = null;
        }
        if (this.stagedActiveLocalModelId === id) {
            this.stagedActiveLocalModelId = null;
        }
        this.saveLocalModelsState();
        this.saveLocalModelProviders();
        this.saveLocalModelFallbackReasons();
        this.renderLocalModelsList();
      } else {
        logger.error(`Failed to remove model ${id}:`, error);
        alert(`Could not remove model ${id}. Please check logs for details.`);
        this.renderLocalModelsList();
      }
    });

  ipcRenderer.on('model-provider-status', (event: IpcRendererEvent, payload: any) => {
        const id = payload?.id as string; const provider = payload?.provider as 'cpu' | 'failed' | 'vulkan' | 'metal' | 'cuda' | 'rocm' | 'openvino' | 'directml' | 'gpu'; const error = (payload?.error ?? null) as string | null;
        if (!id || !provider) { logger.warn('model-provider-status payload missing id/provider', payload); return; }
        logger.info(`Received provider status for ${id}: ${provider}. Fallback reason: ${error || 'N/A'}`);
        const providerChanged = this.localModelProviders[id] !== provider;
        const reasonChanged = this.localModelFallbackReasons[id] !== (error || null);
        if (providerChanged || reasonChanged) {
            this.localModelProviders[id] = provider;
            this.localModelFallbackReasons[id] = error || null;
            this.saveLocalModelProviders();
            this.saveLocalModelFallbackReasons();
            this.renderLocalModelsList();
        }
    });

    ipcRenderer.on('tray-start-recording', () => {
      this.handleTrayStartRecording();
    });
  }

  private handleTrayStartRecording(): void {
    logger.info('Tray start recording triggered.');
    if (!this.isRecording) {
        this.toggleRecording();
    }
  }

  private checkApiConnectivity(): void {
    const isPolishingEnabled = !!this.modelSelector.value;
    const isTranscriptionProviderConfigured = this.transcriptionProviderSelector && !this.transcriptionProviderSelector.disabled;
    
    this.recordButton.disabled = !isTranscriptionProviderConfigured;

    if (!isTranscriptionProviderConfigured) {
      this.recordButton.title = 'A transcription provider must be configured in Settings.';
      this.recordingStatus.textContent = 'Error: No transcription provider configured.';
    } else if (!isPolishingEnabled) {
      this.recordButton.title = 'Start/Stop Recording (Raw transcription only)';
      this.recordingStatus.textContent = 'Ready. Polishing is disabled.';
    } else {
      this.recordButton.title = 'Start/Stop Recording';
      this.recordingStatus.textContent = 'Ready to record';
    }
  }

  private handleResize(): void {
    if (
      this.isRecording &&
      this.liveWaveformCanvas &&
      this.liveWaveformCanvas.style.display === 'block'
    ) {
      requestAnimationFrame(() => this.setupCanvasDimensions());
    }
    // Always update tab indicator on resize to prevent misalignment
    requestAnimationFrame(() => {
        const currentActiveButton = document.querySelector(
          '.tab-button.active',
        ) as HTMLElement;
        if (currentActiveButton) this.setActiveTab(currentActiveButton, true);
    });
  }

  private setupCanvasDimensions(): void {
    if (!this.liveWaveformCanvas || !this.liveWaveformCtx) return;
    const canvas = this.liveWaveformCanvas;
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
    this.liveWaveformCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  private initTheme(): void {
    const savedTheme = localStorage.getItem('theme');
    if (savedTheme === 'light') {
      document.body.classList.add('light-mode');
      this.themeToggleIconModal.classList.replace('fa-sun', 'fa-moon');
      ipcRenderer?.send('update-titlebar-theme', { theme: 'light' });
    } else {
      document.body.classList.remove('light-mode');
      this.themeToggleIconModal.classList.replace('fa-moon', 'fa-sun');
      ipcRenderer?.send('update-titlebar-theme', { theme: 'dark' });
    }
  }

  private toggleTheme(): void {
    document.body.classList.toggle('light-mode');
    if (document.body.classList.contains('light-mode')) {
      localStorage.setItem('theme', 'light');
      this.themeToggleIconModal.classList.replace('fa-sun', 'fa-moon');
      ipcRenderer?.send('update-titlebar-theme', { theme: 'light' });
    } else {
      localStorage.setItem('theme', 'dark');
      this.themeToggleIconModal.classList.replace('fa-moon', 'fa-sun');
      ipcRenderer?.send('update-titlebar-theme', { theme: 'dark' });
    }
  }

  private initUiZoom(): void {
    const saved = parseFloat(localStorage.getItem('uiZoom') || '1');
    // Use CSS zoom for simplicity and broad support in Electron
    (document.body.style as any).zoom = String(saved);
    if (this.uiZoomSlider) this.uiZoomSlider.value = String(saved);
    if (this.uiZoomValue) this.uiZoomValue.textContent = `${Math.round(saved * 100)}%`;
  }

  private applyUiZoom(): void {
    if (!this.uiZoomSlider) return;
    const val = parseFloat(this.uiZoomSlider.value || '1');
    (document.body.style as any).zoom = String(val);
    localStorage.setItem('uiZoom', String(val));
    if (this.uiZoomValue) this.uiZoomValue.textContent = `${Math.round(val * 100)}%`;
  }

  // ===== UI Language (Interface) =====
  private populateUiLanguageSelector(): void {
    if (!this.uiLanguageSelector) return;
    this.uiLanguageSelector.innerHTML = '';
    const add = (label: string, value: UiLanguagePref) => {
      const opt = document.createElement('option');
      opt.value = value;
      opt.textContent = label;
      this.uiLanguageSelector!.appendChild(opt);
    };
  // System option + all supported locales
  add(this.t('settings.lang.systemOption'), 'system');
  UI_LOCALES.forEach((loc) => add(UI_LANGUAGE_LABELS[loc], loc));
  const savedRaw = (localStorage.getItem(UI_LANGUAGE_KEY) as UiLanguagePref) || 'system';
  const isSupported = savedRaw === 'system' || isUiLocale(savedRaw);
  this.uiLanguagePref = isSupported ? savedRaw : 'system';
    this.uiLanguageSelector.value = this.uiLanguagePref;
  }

  private initUiLanguage(): void {
  const savedRaw = (localStorage.getItem(UI_LANGUAGE_KEY) as UiLanguagePref) || 'system';
  const isSupported = savedRaw === 'system' || isUiLocale(savedRaw);
  this.uiLanguagePref = isSupported ? savedRaw : 'system';
    this.applyUiLanguage();
  }

  private onUiLanguageChanged(): void {
    if (!this.uiLanguageSelector) return;
  const v = (this.uiLanguageSelector.value as UiLanguagePref);
  const isSupported = v === 'system' || isUiLocale(v);
  this.uiLanguagePref = isSupported ? v : 'system';
    localStorage.setItem(UI_LANGUAGE_KEY, this.uiLanguagePref);
    this.applyUiLanguage();
  }

  private getActiveLocale(): UiLocale {
    if (this.uiLanguagePref !== 'system') return this.uiLanguagePref;
    const nav = (navigator.language || 'en').toLowerCase();
    if (nav.startsWith('ru')) return 'ru';
    if (nav.startsWith('es')) return 'es';
    if (nav.startsWith('de')) return 'de';
    if (nav.startsWith('fr')) return 'fr';
    if (nav.startsWith('it')) return 'it';
    if (nav.startsWith('pt')) return 'pt';
    if (nav.startsWith('zh')) return 'zh';
    if (nav.startsWith('ja')) return 'ja';
    if (nav.startsWith('ko')) return 'ko';
    if (nav.startsWith('ar')) return 'ar';
    if (nav.startsWith('hi')) return 'hi';
    // fallback
    return 'en';
  }

  private t(key: string): string {
    const loc = this.getActiveLocale();
    return (I18N[loc] && I18N[loc][key]) || (I18N.en[key] || key);
  }

  private applyUiLanguage(): void {
    // Tabs
    const rawBtn = document.querySelector('.tab-button[data-tab="raw"]') as HTMLButtonElement | null;
    const v1Btn = document.querySelector('.tab-button[data-tab="note"]') as HTMLButtonElement | null;
    const v2Btn = document.querySelector('.tab-button[data-tab="x2"]') as HTMLButtonElement | null;
    if (rawBtn) rawBtn.textContent = this.t('tab.raw');
    if (v1Btn) v1Btn.textContent = this.t('tab.v1');
    if (v2Btn) v2Btn.textContent = this.t('tab.v2');

  // Recording status and button label
    const status = document.getElementById('recordingStatus');
    if (status) status.textContent = this.t('record.ready');
    const recordText = document.querySelector('.record-text');
    if (recordText) recordText.textContent = this.t('record.button');
  // Record button title
  const recordBtnEl = document.getElementById('recordButton');
  if (recordBtnEl) recordBtnEl.setAttribute('title', this.t('tooltip.record'));

  // Settings modal title and tab labels
    const modal = document.getElementById('promptModal');
    if (modal) {
      const title = modal.querySelector('.prompt-modal-header h3');
      if (title) title.textContent = this.t('settings.title');
      const tabsMap: Record<string, string> = {
        general: 'settings.general', providers: 'settings.providers', localModels: 'settings.localModels',
        localLlm: 'settings.localLlm', prompt: 'settings.prompt', hotkey: 'settings.hotkey', help: 'settings.help'
      };
      Object.entries(tabsMap).forEach(([dataTab, k]) => {
        const btn = modal.querySelector(`.modal-tab-button[data-tab="${dataTab}"]`);
        if (btn) (btn as HTMLElement).textContent = this.t(k);
      });
      const cancel = document.getElementById('cancelPromptButton');
      const save = document.getElementById('saveSettingsButton');
      if (cancel) cancel.textContent = this.t('settings.cancel');
      if (save) save.textContent = this.t('settings.save');
    }

    // Elements with data-i18n
    document.querySelectorAll<HTMLElement>('[data-i18n]').forEach(el => {
      const key = el.getAttribute('data-i18n')!;
      el.textContent = this.t(key);
    });
    // Elements with data-i18n-title
    document.querySelectorAll<HTMLElement>('[data-i18n-title]').forEach(el => {
      const key = el.getAttribute('data-i18n-title')!;
      el.setAttribute('title', this.t(key));
    });

    // Tooltips: header selects and corner buttons
    const transSel = document.getElementById('transcriptionProviderSelector');
    if (transSel) transSel.setAttribute('title', this.t('tooltip.transcriptionProvider'));
    const modelSel = document.getElementById('modelSelector');
    if (modelSel) modelSel.setAttribute('title', this.t('tooltip.polishingModel'));
    const clearBtn = document.getElementById('clearButton');
    if (clearBtn) clearBtn.setAttribute('title', this.t('tooltip.clear'));
    const copyBtn = document.getElementById('copyButton');
    if (copyBtn) copyBtn.setAttribute('title', this.t('tooltip.copy'));
    const translateBtn = document.getElementById('translateButton');
    if (translateBtn) translateBtn.setAttribute('title', this.t('tooltip.translate'));
  const fileBtn = document.getElementById('fileTranscribeButton');
  if (fileBtn) fileBtn.setAttribute('title', this.t('tooltip.transcribeFile'));
  const newNoteBtn = document.getElementById('createEmptyNoteButton');
  if (newNoteBtn) {
    const v = this.t('tooltip.newEmptyNote');
    newNoteBtn.setAttribute('title', v && v !== 'tooltip.newEmptyNote' ? v : 'New empty note');
  }
    const settingsBtn = document.getElementById('promptSettingsButton');
    if (settingsBtn) settingsBtn.setAttribute('title', this.t('tooltip.settings'));
    const themeToggleBtn = document.getElementById('themeToggleButtonModal');
    if (themeToggleBtn) themeToggleBtn.setAttribute('title', this.t('tooltip.themeToggle'));

    // Localize dynamic copy/polish bubble buttons with fallbacks if keys are missing
    const copyTitle = (() => { const v = this.t('tooltip.copy'); return v && v !== 'tooltip.copy' ? v : 'Copy'; })();
    const polishTitle = (() => { const v = this.t('tooltip.polish'); return v && v !== 'tooltip.polish' ? v : 'Polish'; })();
    document.querySelectorAll<HTMLButtonElement>('button.copy-bubble-btn:not(.polish)')
      .forEach(btn => btn.setAttribute('title', copyTitle));
    document.querySelectorAll<HTMLButtonElement>('button.copy-bubble-btn.polish')
      .forEach(btn => btn.setAttribute('title', polishTitle));

    // Update language selector "system" option label without re-instantiating CustomSelect
    if (this.uiLanguageSelector) {
      const sysOpt = this.uiLanguageSelector.querySelector('option[value="system"]');
      if (sysOpt) sysOpt.textContent = this.t('settings.lang.systemOption');
    }

    // Re-render Local Models list to apply translated labels
    this.renderLocalModelsList?.();
  }

  // Removed ad-hoc test helpers for cleaner production code

  private async toggleRecording(): Promise<void> {
  logger.debug('[TOGGLE_RECORDING] Method called');
    // Add immediate crash protection
    logger.info('[Recording] Toggle recording called, current state:', this.isRecording);
  logger.debug('[TOGGLE_RECORDING] Current state:', this.isRecording);
    
    try {
  logger.debug('[TOGGLE_RECORDING] Entered try block');
      if (!this.isRecording) {
  logger.debug('[TOGGLE_RECORDING] Starting recording...');
        await this.startRecording();
  logger.debug('[TOGGLE_RECORDING] Recording started');
      } else {
  logger.debug('[TOGGLE_RECORDING] Stopping recording...');
        await this.stopRecording();
  logger.debug('[TOGGLE_RECORDING] Recording stopped');
      }
    } catch (error) {
      logger.error('[Recording] CRITICAL ERROR in toggleRecording:', error);
      // Reset state on any error
      this.isRecording = false;
      this.recordButton.classList.remove('recording');
  this.recordButton.setAttribute('title', this.t('tooltip.record'));
      this.recordingStatus.textContent = 'Error: ' + (error instanceof Error ? error.message : String(error));
      
      // Cleanup on error
      if (this.stream) {
        try {
          this.stream.getTracks().forEach(track => track.stop());
          this.stream = null;
        } catch (cleanupError) {
          logger.error('[Recording] Error during cleanup:', cleanupError);
        }
      }
      
      throw error; // Re-throw for higher level handling
    }
  }

  private setupAudioVisualizer(): void {
    if (!this.stream || this.audioContext) return;
    
    try {
      // Create and initialize audio context
      const AudioContextCtor = window.AudioContext || (window as any).webkitAudioContext;
      this.audioContext = new AudioContextCtor();
      
      if (this.audioContext.state === 'suspended') {
        this.audioContext.resume().catch(err => {
          logger.warn('Error resuming AudioContext:', err);
        });
      }

      // Create and connect nodes
      const source = this.audioContext.createMediaStreamSource(this.stream);
      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 256;
      this.analyserNode.smoothingTimeConstant = 0.75;
      const bufferLength = this.analyserNode.frequencyBinCount;
      this.waveformDataArray = new Uint8Array(bufferLength);
      source.connect(this.analyserNode);

      logger.info('Audio visualizer setup complete');
    } catch (err) {
      logger.error('Error setting up audio visualizer:', err);
      // Clean up on error
      if (this.audioContext) {
        try {
          this.audioContext.close().catch(() => {});
        } catch {} // Ignore cleanup errors
        this.audioContext = null;
      }
      this.analyserNode = null;
      this.waveformDataArray = null;
    }
  }

  private drawLiveWaveform(): void {
    if (
      !this.analyserNode ||
      !this.waveformDataArray ||
      !this.liveWaveformCtx ||
      !this.liveWaveformCanvas ||
      !this.isRecording
    ) {
      if (this.waveformDrawingId) cancelAnimationFrame(this.waveformDrawingId);
      this.waveformDrawingId = null;
      return;
    }
    this.waveformDrawingId = requestAnimationFrame(() =>
      this.drawLiveWaveform(),
    );
    this.analyserNode.getByteFrequencyData(this.waveformDataArray as any);
    const ctx = this.liveWaveformCtx;
    const canvas = this.liveWaveformCanvas;
    const logicalWidth = canvas.clientWidth,
      logicalHeight = canvas.clientHeight;
    ctx.clearRect(0, 0, logicalWidth, logicalHeight);
    const bufferLength = this.analyserNode.frequencyBinCount;
    const numBars = Math.floor(bufferLength * 0.5);
    if (numBars === 0) return;
    const totalBarPlusSpacingWidth = logicalWidth / numBars;
    const barWidth = Math.max(1, Math.floor(totalBarPlusSpacingWidth * 0.7));
    const barSpacing = Math.max(0, Math.floor(totalBarPlusSpacingWidth * 0.3));
    let x = 0;
    const recordingColor =
      getComputedStyle(document.documentElement)
        .getPropertyValue('--color-recording')
        .trim() || '#ff3b30';
    ctx.fillStyle = recordingColor;
    for (let i = 0; i < numBars; i++) {
      if (x >= logicalWidth) break;
      const dataIndex = Math.floor(i * (bufferLength / numBars));
      const barHeightNormalized = this.waveformDataArray[dataIndex] / 255.0;
      let barHeight = barHeightNormalized * logicalHeight;
      if (barHeight < 1 && barHeight > 0) barHeight = 1;
      barHeight = Math.round(barHeight);
      const y = Math.round((logicalHeight - barHeight) / 2);
      ctx.fillRect(Math.floor(x), y, barWidth, barHeight);
      x += barWidth + barSpacing;
    }
  }

  private updateLiveTimer(): void {
    if (!this.isRecording || !this.liveRecordingTimerDisplay) return;
    const elapsedMs = Date.now() - this.recordingStartTime;
    const totalSeconds = Math.floor(elapsedMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const hundredths = Math.floor((elapsedMs % 1000) / 10);
    this.liveRecordingTimerDisplay.textContent = `${String(minutes).padStart(
      2,
      '0',
    )}:${String(seconds).padStart(
      2,
      '0',
    )}.${String(hundredths).padStart(
      2,
      '0',
    )}`;
  }

  private startLiveDisplay(): void {
    if (
      !this.recordingInterface ||
      !this.liveRecordingTitle ||
      !this.liveWaveformCanvas ||
      !this.liveRecordingTimerDisplay
    )
      return;
    this.recordingInterface.classList.add('is-live');
    this.liveRecordingTitle.style.display = 'block';
    this.liveWaveformCanvas.style.display = 'block';
    this.liveRecordingTimerDisplay.style.display = 'block';
    this.setupCanvasDimensions();
    if (this.statusIndicatorDiv) this.statusIndicatorDiv.style.display = 'none';
    const iconElement = this.recordButton.querySelector(
      '.record-button-inner i',
    ) as HTMLElement;
    if (iconElement) iconElement.classList.replace('fa-microphone', 'fa-stop');
    this.liveRecordingTitle.textContent = this.isHotkeyRecording ? 'Hotkey Recording' : 'New Recording';
    
    // Start the waveform animation
    this.drawLiveWaveform();
    
    this.recordingStartTime = Date.now();
    this.updateLiveTimer();
    if (this.timerIntervalId) clearInterval(this.timerIntervalId);
    this.timerIntervalId = window.setInterval(() => this.updateLiveTimer(), 50);
    // Show tiny overlay indicator and play start sound for hotkey sessions
    if (this.isHotkeyRecording) {
      // Optional local beep using WebAudio if sounds enabled
      this.maybeBeep('start');
      try { ipcRenderer?.send('hotkey-transcription-start'); } catch {}
    }

    // Debug: sample live amplitude every 500ms to detect silence in packaged build
    try {
      if (this.analyserNode) {
        const tmpArray = new Uint8Array(this.analyserNode.frequencyBinCount);
        let amplitudeChecks = 0;
        const maxChecks = 20; // ~10s
        const check = () => {
          if (!this.isRecording || !this.analyserNode) return;
            this.analyserNode.getByteTimeDomainData(tmpArray);
            // Compute rough peak deviation from 128 midpoint
            let peakDev = 0;
            for (let i = 0; i < tmpArray.length; i++) {
              const dev = Math.abs(tmpArray[i] - 128);
              if (dev > peakDev) peakDev = dev;
            }
            const normPeak = (peakDev / 128).toFixed(3);
            logger.debug('[Recording][LiveLevel] peakNorm=' + normPeak);
            amplitudeChecks++;
            if (amplitudeChecks < maxChecks) setTimeout(check, 500);
            else if (peakDev < 2) {
              logger.warn('[Recording] Live analyser shows sustained near-zero signal. Possibly capturing a muted device or wrong input source in packaged app.');
              logger.warn('[Recording] Suggest checking System Settings > Privacy & Security > Microphone and confirming SmartScribe has permission.');
            }
        };
        setTimeout(check, 600);
      }
    } catch (e) { logger.warn('[Recording] Live level debug setup failed:', e); }

    // Log active input device label if accessible
    try {
      const track = this.stream?.getAudioTracks?.()[0];
      if (track) logger.info('[Recording] Using input device:', { label: track.label || '(no label)', kind: track.kind });
    } catch {}
  }

  private stopLiveDisplay(): void {
  logger.debug('[STOP_LIVE_DISPLAY] Method called');
    
    // Add guard to prevent double execution
    if (!this.recordingInterface || this.recordingInterface.classList.contains('is-stopping')) {
      logger.debug('[STOP_LIVE_DISPLAY] Already stopping or interface missing, aborting');
      return;
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Adding is-stopping flag');
    this.recordingInterface.classList.add('is-stopping');
    logger.debug('[STOP_LIVE_DISPLAY] Checking elements...');
    logger.debug('[STOP_LIVE_DISPLAY] recordingInterface exists:', !!this.recordingInterface);
    logger.debug('[STOP_LIVE_DISPLAY] liveRecordingTitle exists:', !!this.liveRecordingTitle);
    logger.debug('[STOP_LIVE_DISPLAY] liveWaveformCanvas exists:', !!this.liveWaveformCanvas);
    logger.debug('[STOP_LIVE_DISPLAY] liveRecordingTimerDisplay exists:', !!this.liveRecordingTimerDisplay);
    
    if (
      !this.recordingInterface ||
      !this.liveRecordingTitle ||
      !this.liveWaveformCanvas ||
      !this.liveRecordingTimerDisplay
    ) {
      logger.debug('[STOP_LIVE_DISPLAY] Some elements missing, basic cleanup...');
      if (this.recordingInterface) {
        logger.debug('[STOP_LIVE_DISPLAY] Removing is-live class');
        this.recordingInterface.classList.remove('is-live');
      }
      logger.debug('[STOP_LIVE_DISPLAY] Early return');
      return;
    }
    logger.debug('[STOP_LIVE_DISPLAY] All elements exist, full cleanup...');
    logger.debug('[STOP_LIVE_DISPLAY] Removing is-live class');
    try {
      this.recordingInterface.classList.remove('is-live');
      logger.debug('[STOP_LIVE_DISPLAY] is-live class removed successfully');
    } catch (error) {
      logger.debug('[STOP_LIVE_DISPLAY] Error removing is-live class:', error);
      throw error;
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Setting liveRecordingTitle display to none');
    try {
      this.liveRecordingTitle.style.display = 'none';
      logger.debug('[STOP_LIVE_DISPLAY] liveRecordingTitle display set successfully');
    } catch (error) {
      logger.debug('[STOP_LIVE_DISPLAY] Error setting liveRecordingTitle display:', error);
      throw error;
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Setting liveWaveformCanvas display to none');
    try {
      this.liveWaveformCanvas.style.display = 'none';
      logger.debug('[STOP_LIVE_DISPLAY] liveWaveformCanvas display set successfully');
    } catch (error) {
      logger.debug('[STOP_LIVE_DISPLAY] Error setting liveWaveformCanvas display:', error);
      throw error;
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Setting liveRecordingTimerDisplay display to none');
    try {
      this.liveRecordingTimerDisplay.style.display = 'none';
      logger.debug('[STOP_LIVE_DISPLAY] liveRecordingTimerDisplay display set successfully');
    } catch (error) {
      logger.debug('[STOP_LIVE_DISPLAY] Error setting liveRecordingTimerDisplay display:', error);
      throw error;
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Checking statusIndicatorDiv');
    if (this.statusIndicatorDiv) {
      logger.debug('[STOP_LIVE_DISPLAY] Setting statusIndicatorDiv display to block');
      this.statusIndicatorDiv.style.display = 'block';
      logger.debug('[STOP_LIVE_DISPLAY] statusIndicatorDiv display set successfully');
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Looking for icon element');
    const iconElement = this.recordButton.querySelector(
      '.record-button-inner i',
    ) as HTMLElement;
    logger.debug('[STOP_LIVE_DISPLAY] Icon element found:', !!iconElement);
    
    if (iconElement) {
      logger.debug('[STOP_LIVE_DISPLAY] Replacing fa-stop with fa-microphone');
      iconElement.classList.replace('fa-stop', 'fa-microphone');
      logger.debug('[STOP_LIVE_DISPLAY] Icon class replaced successfully');
    }
    
    logger.debug('[STOP_LIVE_DISPLAY] Canceling animation frame, ID:', this.waveformDrawingId);
    if (this.waveformDrawingId) {
      cancelAnimationFrame(this.waveformDrawingId);
      logger.debug('[STOP_LIVE_DISPLAY] Animation frame canceled');
    }
    this.waveformDrawingId = null;
    logger.debug('[STOP_LIVE_DISPLAY] waveformDrawingId set to null');
    
    logger.debug('[STOP_LIVE_DISPLAY] Clearing timer interval, ID:', this.timerIntervalId);
    if (this.timerIntervalId) {
      clearInterval(this.timerIntervalId);
      logger.debug('[STOP_LIVE_DISPLAY] Timer interval cleared');
    }
    this.timerIntervalId = null;
    logger.debug('[STOP_LIVE_DISPLAY] timerIntervalId set to null');
    
    logger.debug('[STOP_LIVE_DISPLAY] Checking liveWaveformCtx and canvas');
    if (this.liveWaveformCtx && this.liveWaveformCanvas) {
      logger.debug('[STOP_LIVE_DISPLAY] Clearing canvas rect');
      this.liveWaveformCtx.clearRect(
        0,
        0,
        this.liveWaveformCanvas.width,
        this.liveWaveformCanvas.height,
      );
      logger.debug('[STOP_LIVE_DISPLAY] Canvas rect cleared successfully');
    }
    
    if (this.audioContext && this.audioContext.state !== 'closed') {
      logger.debug('[stopLiveDisplay] Closing AudioContext, state:', this.audioContext.state);
      this.audioContext.close().then(() => {
        logger.debug('[stopLiveDisplay] AudioContext closed successfully');
      }).catch((error) => {
        logger.warn('[stopLiveDisplay] AudioContext close failed:', error);
      });
      this.audioContext = null;
    }
    
  logger.debug('[STOP_LIVE_DISPLAY] Setting analyserNode to null');
  this.analyserNode = null;
  logger.debug('[STOP_LIVE_DISPLAY] Setting waveformDataArray to null');
  this.waveformDataArray = null;
  logger.debug('[STOP_LIVE_DISPLAY] Removing is-stopping flag');
  this.recordingInterface.classList.remove('is-stopping');
  logger.debug('[STOP_LIVE_DISPLAY] Method complete');
  }

  private async startRecording(): Promise<void> {
    logger.info('[Recording] Starting recording process');
    try {
      const isPackaged = /app.asar/.test((window.location && window.location.href) || '');
      logger.debug('[Recording][Env] isPackaged=', isPackaged, ' userAgent=', navigator.userAgent);
      try {
        const supp = (navigator.mediaDevices as any).getSupportedConstraints?.() || {};
        logger.debug('[Recording][Env] SupportedConstraints keys=', Object.keys(supp));
      } catch {}
      // 1) Initial cleanup
      this.audioChunks = [];
      if (this.stream) {
        try { this.stream.getTracks().forEach(t => t.stop()); } catch (e) { logger.warn('[Recording] Error stopping existing stream:', e); }
      }
      this.stream = null;
      if (this.audioContext) {
        try { if (this.audioContext.state !== 'closed') await this.audioContext.close(); } catch (e) { logger.warn('[Recording] Error closing existing AudioContext:', e); }
        this.audioContext = null;
      }

      // 2) Get microphone access with fallbacks
      this.recordingStatus.textContent = 'Requesting microphone access...';
      logger.info('[Recording] Requesting microphone access');
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        logger.info('[Recording] Got stream with default settings:', { tracks: this.stream.getTracks().length, active: this.stream.active });
      } catch (err) {
        logger.warn('[Recording] Default getUserMedia failed, trying without processing:', err);
        let gotStream = false;
        try {
          this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
          gotStream = true;
          logger.info('[Recording] Got stream with processing disabled:', { tracks: this.stream.getTracks().length, active: this.stream.active });
        } catch (err2) {
          logger.warn('[Recording] getUserMedia without processing failed, enumerating devices:', err2);
          try {
            const devices = await navigator.mediaDevices.enumerateDevices();
            const inputs = devices.filter(d => d.kind === 'audioinput');
            for (const dev of inputs) {
              try {
                this.stream = await navigator.mediaDevices.getUserMedia({ audio: { deviceId: { exact: dev.deviceId }, echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
                logger.info('[Recording] Got stream using alternate device:', { label: dev.label || 'audioinput', id: dev.deviceId });
                gotStream = true;
                break;
              } catch (e) {
                logger.warn('[Recording] Failed with deviceId, trying next input:', { id: dev.deviceId, err: e });
              }
            }
          } catch (enumErr) {
            logger.warn('[Recording] enumerateDevices failed:', enumErr);
          }
        }
        if (!gotStream || !this.stream) {
          const msg = (err as any)?.name === 'NotReadableError' || /busy|in use|could not start|resource/i.test(String((err as any)?.message || ''))
            ? 'Microphone is busy or in use by another application. Close other apps using the mic, or pick a different input in system settings.'
            : 'Could not access microphone.';
          logger.error('[Recording] Failed to get microphone access after fallbacks.');
          throw new Error(msg);
        }
      }

      // 3) Safety listeners in case mic becomes unavailable mid-session
      try {
        const track = this.stream.getAudioTracks?.()[0];
        if (track) {
          try {
            logger.debug('[Recording][Track] settings=', track.getSettings ? track.getSettings() : null, ' constraints=', (track as any).getConstraints ? (track as any).getConstraints() : null);
          } catch {}
          track.onended = () => { logger.warn('[Recording] Microphone track ended unexpectedly.'); if (this.isRecording) this.handleMicEnded(); };
          track.onmute = () => { if (this.isRecording) this.recordingStatus.textContent = 'Microphone muted/unavailable...'; };
          track.onunmute = () => { if (this.isRecording) this.recordingStatus.textContent = 'Recording...'; };
        }
      } catch (e) { logger.warn('[Recording] Failed to attach track event listeners:', e); }
      // Enumerate devices AFTER permission for accurate labels
      try {
        const devs = await navigator.mediaDevices.enumerateDevices();
        const inputs = devs.filter(d => d.kind === 'audioinput').map(d => ({ label: d.label, deviceId: d.deviceId }));
        logger.debug('[Recording][Devices] audio inputs after permission:', inputs);
      } catch (e) { logger.warn('[Recording] enumerateDevices (post-permission) failed:', e); }

      // 4) Quick MediaRecorder capability probe (optional)
      this.recordingStatus.textContent = 'Testing recording format...';
      try { const probe = new MediaRecorder(this.stream); if (probe.state !== 'inactive') probe.stop(); } catch (recorderError) { throw new Error('Cannot create MediaRecorder: ' + (recorderError instanceof Error ? recorderError.message : 'Unknown error')); }

      // 5) Set up AudioContext + AudioWorklet
      if (!window.AudioContext && !window.webkitAudioContext) throw new Error('WebAudio API not supported in this browser');
      const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
      const ctxOptions: any = {};
      // In packaged app, avoid forcing 16k directly; let native rate (e.g. 48000) then downsample later.
      if (!isPackaged) ctxOptions.sampleRate = 16000;
      try {
        this.audioContext = new AudioContextCtor(ctxOptions);
      } catch (e) {
        logger.warn('[Recording] Failed to create AudioContext with options', ctxOptions, ' retrying default:', e);
        this.audioContext = new AudioContextCtor();
      }
      if (this.audioContext.state === 'suspended') await this.audioContext.resume();
      logger.info('[Recording] AudioContext created:', { state: this.audioContext.state, sampleRate: this.audioContext.sampleRate, baseLatency: (this.audioContext as any).baseLatency });
  // Capture actual device sample rate immediately to avoid race when the first worklet message arrives.
  this.recordingSampleRate = this.audioContext.sampleRate || 16000;
      try {
        await this.audioContext.audioWorklet.addModule(new URL('audio-recorder-worklet.js', window.location.href).toString());
        logger.info('[Recording] AudioWorklet loaded successfully');
      } catch (e) {
        logger.error('[Recording] Failed to load AudioWorklet:', e);
        throw new Error('AudioWorklet not supported or failed to load');
      }

      const source = this.audioContext.createMediaStreamSource(this.stream);
      this.audioWorkletNode = new AudioWorkletNode(this.audioContext, 'audio-recorder-processor');
      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 256;
      this.analyserNode.smoothingTimeConstant = 0.75;
      this.waveformDataArray = new Uint8Array(this.analyserNode.frequencyBinCount);
      this.audioWorkletNode.port.onmessage = (event: MessageEvent) => {
        if (event.data.command === 'audioData') {
          this.audioBuffer = event.data.data;
          // recordingSampleRate already latched at start; don't overwrite here (prevents race ordering issues)
          try {
            const buf = this.audioBuffer as Float32Array | null;
            if (buf && buf.length) {
              let sum = 0, peak = 0;
              for (let i = 0; i < buf.length; i++) { const v = buf[i]; sum += v * v; if (Math.abs(v) > peak) peak = Math.abs(v); }
              const rms = Math.sqrt(sum / buf.length);
              logger.debug('[Recording][LevelStats] samples=', buf.length, 'rms=', rms.toFixed(6), 'peak=', peak.toFixed(6));
              // Flag extremely low level (likely silence / device muted)
              if (rms < 0.0005 && peak < 0.002) {
                logger.warn('[Recording] Detected near-silence buffer (rms<0.0005). If unexpected, verify input device & macOS security permissions.');
              }
            } else if (buf && buf.length === 0) {
              logger.warn('[Recording] Received empty audio buffer from worklet (0 samples). Worklet may not be connected or microphone delivering silence.');
            }
          } catch (e) { logger.warn('[Recording] Failed to compute level stats:', e); }
        }
      };
      source.connect(this.audioWorkletNode);
      source.connect(this.analyserNode);
      this.audioWorkletNode.port.postMessage({ command: 'start' });

      // 6) UI state
      this.isRecording = true;
      this.recordingStatus.textContent = 'Recording...';
      this.recordingInterface?.classList.add('is-recording');
      this.recordButton.classList.add('recording');
      this.recordButton.setAttribute('title', 'Stop Recording');
      this.startLiveDisplay();
      logger.info('[Recording] Started WAV recording at', this.recordingSampleRate, 'Hz');
    } catch (error) {
      if (this.isHotkeyRecording) { try { ipcRenderer?.send('hotkey-transcription-end'); } catch {} this.isHotkeyRecording = false; }
      logger.error('Error starting recording:', error);
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorName = error instanceof Error ? error.name : 'Unknown';
      if (errorName === 'NotAllowedError' || errorName === 'PermissionDeniedError') {
        this.recordingStatus.textContent = 'Microphone permission denied. Please check OS/app settings.';
      } else if (errorName === 'NotFoundError' || (errorName === 'DOMException' && errorMessage.includes('Requested device not found'))) {
        this.recordingStatus.textContent = 'No microphone found.';
      } else if (errorName === 'NotReadableError' || /busy|in use|could not start|resource/i.test(errorMessage)) {
        this.recordingStatus.textContent = 'Microphone is busy or used by another app. Close other apps using the mic or choose a different input in system settings.';
      } else if (errorName === 'AbortError') {
        this.recordingStatus.textContent = 'Microphone request was aborted. Please try again.';
      } else {
        this.recordingStatus.textContent = 'Failed to start recording.';
      }
      this.isRecording = false;
      if (this.stream) { try { this.stream.getTracks().forEach(t => t.stop()); } catch {} }
      this.stream = null;
      this.recordButton.classList.remove('recording');
  this.recordButton.setAttribute('title', this.t('tooltip.record'));
      this.stopLiveDisplay();
      // Best-effort cleanup for audioContext
      if (this.audioContext) { try { await this.audioContext.close(); } catch {} }
      this.audioContext = null;
    }
  }

  private async handleMicEnded(): Promise<void> {
    try { await this.stopRecording(); } catch (e) { logger.warn('[Recording] Error while stopping after mic ended:', e); }
    this.recordingStatus.textContent = 'Microphone disconnected or in use by another app.';
  }

  private async stopRecording(): Promise<void> {
    logger.debug('[STOP_RECORDING] Method called');
    logger.debug('[STOP_RECORDING] isRecording:', this.isRecording);
    
    if (this.isRecording) {
      this.isRecording = false;
      this.recordButton.classList.remove('recording');
  this.recordButton.setAttribute('title', this.t('tooltip.record'));
      this.recordingStatus.textContent = 'Processing audio...';
  // If this was a hotkey session, switch the overlay to Processing immediately
  // for the whole post-recording phase (applies to Raw, Variant 1, and Variant 2)
  if (this.isHotkeyRecording) {
        try { ipcRenderer?.send('log-message', { level: 'info', message: '[Overlay] Renderer: stopRecording → hotkey-processing-start' }); } catch {}
        try { ipcRenderer?.send('hotkey-processing-start'); } catch {}
      }
      
      this.stopLiveDisplay();
      
      if (this.audioWorkletNode) {
  logger.debug('[STOP_RECORDING] Stopping AudioWorklet...');
        
        // Create a promise that resolves when we get audio data
        const audioPromise = new Promise<Blob | null>((resolve) => {
          const timeout = setTimeout(() => {
            logger.warn('[STOP_RECORDING] Timeout waiting for audio data');
            resolve(null);
          }, 5000); // 5 second timeout
          
          // Set up one-time message handler for audio data
          const messageHandler = (event: MessageEvent) => {
            if (event.data.command === 'audioData') {
              clearTimeout(timeout);
              this.audioWorkletNode!.port.removeEventListener('message', messageHandler);
              
              const audioBuffer = event.data.data as Float32Array;
              if (audioBuffer.length > 0) {
                // Create WAV blob from audio buffer
                const wavBlob = this.createWAVBlob(audioBuffer, this.recordingSampleRate);
                logger.debug('[STOP_RECORDING] Created WAV blob, size:', wavBlob.size);
                try {
                  logger.debug('[Recording][Diag] WAV blob created with sampleRate=', this.recordingSampleRate, 'framesFloat32=', audioBuffer.length);
                  // Rough duration estimate
                  const estDur = audioBuffer.length / (this.recordingSampleRate || 16000);
                  logger.debug('[Recording][Diag] Estimated duration (s)=', estDur.toFixed(3));
                  if (estDur > 0 && (audioBuffer.length / Math.max(1,this.recordingSampleRate)) > 2 * (performance.now() - this.recordingStartTime) / 1000) {
                    // Downgraded to info: useful diagnostic but too noisy for warn level
                    logger.info('[Recording][Diag] Detected possible sample rate label mismatch (duration >> wall time).');
                  }
                } catch {}
                resolve(wavBlob);
              } else {
                logger.warn('[STOP_RECORDING] No audio data received');
                resolve(null);
              }
            }
          };
          
          this.audioWorkletNode!.port.addEventListener('message', messageHandler);
        });
        
        // Stop recording
        this.audioWorkletNode.port.postMessage({ command: 'stop' });
        
        // Wait for the blob
        const audioBlob = await audioPromise;
        
        if (audioBlob && audioBlob.size > 0) {
          logger.info('[Recording] Processing WAV audio:', { size: audioBlob.size, type: audioBlob.type });
          // Read back samples to evaluate silence before sending
          try {
            const arrBuf = await audioBlob.arrayBuffer();
            // Skip first 44 bytes (WAV header) then parse 16-bit PCM
            if (arrBuf.byteLength > 46) {
              const pcm = new DataView(arrBuf, 44);
              let sum = 0, peak = 0;
              const n = pcm.byteLength / 2;
              for (let i = 0; i < n; i++) {
                const s = pcm.getInt16(i * 2, true) / 32768;
                sum += s * s; const a = Math.abs(s); if (a > peak) peak = a;
              }
              const rms = Math.sqrt(sum / Math.max(1, n));
              logger.debug('[Recording][PostWavStats] frames=', n, 'rms=', rms.toFixed(6), 'peak=', peak.toFixed(6));
              if (rms < 0.0005 && peak < 0.002) {
                logger.warn('[Recording] WAV appears silent (near-zero amplitude). Skipping transcription.');
                this.recordingStatus.textContent = 'No audible input (silence).';
                if (this.isHotkeyRecording) {
                  try { ipcRenderer?.send('hotkey-transcription-end'); } catch {}
                  this.isHotkeyRecording = false;
                  ipcRenderer?.send('hotkey-recording-finished');
                }
                return; // Skip processAudio
              }
            }
          } catch (lvlErr) { logger.warn('[Recording] Failed to inspect WAV amplitude:', lvlErr); }
          try {
            await this.processAudio(audioBlob);
          } catch (err) {
            logger.error('[STOP_RECORDING] processAudio() failed:', err);
            logger.error('Error processing audio:', err);
            this.recordingStatus.textContent = `Error: ${err instanceof Error ? err.message : String(err)}`;
            if (this.isHotkeyRecording) {
              try { ipcRenderer?.send('hotkey-transcription-end'); } catch {}
              this.isHotkeyRecording = false;
              ipcRenderer?.send('hotkey-recording-finished');
            }
          }
        } else {
          logger.warn('[STOP_RECORDING] No audio data captured');
          this.recordingStatus.textContent = 'No audio captured.';
          
          if (this.isHotkeyRecording) {
            try { ipcRenderer?.send('hotkey-transcription-end'); } catch {}
            this.isHotkeyRecording = false;
            ipcRenderer?.send('hotkey-recording-finished');
            this.maybeBeep('end');
          }
        }
        
        // Clean up AudioWorkletNode
        if (this.audioWorkletNode) {
          this.audioWorkletNode.disconnect();
          this.audioWorkletNode = null;
        }
  }
      
      // Clean up stream
      if (this.stream) {
        this.stream.getTracks().forEach((track) => track.stop());
        this.stream = null;
      }
      
    } else {
  logger.debug('[STOP_RECORDING] Not recording, calling stopLiveDisplay');
  this.stopLiveDisplay();
    }
    
  logger.debug('[STOP_RECORDING] Method complete');
  }

  // Create a proper WAV file blob from Float32Array
  private createWAVBlob(audioBuffer: Float32Array, sampleRate: number): Blob {
    const length = audioBuffer.length;
    const arrayBuffer = new ArrayBuffer(44 + length * 2);
    const view = new DataView(arrayBuffer);

    // Helper function to write strings
    const writeString = (offset: number, string: string) => {
      for (let i = 0; i < string.length; i++) {
        view.setUint8(offset + i, string.charCodeAt(i));
      }
    };

    // WAV header
    writeString(0, 'RIFF');                         // ChunkID
    view.setUint32(4, 36 + length * 2, true);      // ChunkSize
    writeString(8, 'WAVE');                        // Format
    writeString(12, 'fmt ');                       // Subchunk1ID
    view.setUint32(16, 16, true);                  // Subchunk1Size (16 for PCM)
    view.setUint16(20, 1, true);                   // AudioFormat (1 for PCM)
    view.setUint16(22, 1, true);                   // NumChannels (1 for mono)
    view.setUint32(24, sampleRate, true);          // SampleRate
    view.setUint32(28, sampleRate * 2, true);      // ByteRate
    view.setUint16(32, 2, true);                   // BlockAlign
    view.setUint16(34, 16, true);                  // BitsPerSample
    writeString(36, 'data');                       // Subchunk2ID
    view.setUint32(40, length * 2, true);          // Subchunk2Size

    // Convert float samples to 16-bit PCM
    let offset = 44;
    for (let i = 0; i < length; i++) {
      const sample = Math.max(-1, Math.min(1, audioBuffer[i]));
      view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7FFF, true);
      offset += 2;
    }

    return new Blob([arrayBuffer], { type: 'audio/wav' });
  }

  // Process captured audio and send for transcription
  private async processAudio(audioBlob: Blob): Promise<void> {
    if (audioBlob.size === 0) {
      this.recordingStatus.textContent = 'No audio data captured.';
      if (this.isHotkeyRecording) {
        this.isHotkeyRecording = false;
      }
      return;
    }

    logger.info('[processAudio] Processing audio:', { 
      size: audioBlob.size, 
      type: audioBlob.type 
    });

    // Check if we have WAV format (best case)
    if (audioBlob.type.includes('wav')) {
      logger.info('[processAudio] Audio is already in WAV format');
      await this.sendToWhisper(audioBlob);
      return;
    }

    // For WebM format, send directly and let Whisper transcription worker handle it
    // The worker has better error handling for format issues
    if (audioBlob.type.includes('webm')) {
      logger.info('[processAudio] Sending WebM to Whisper (worker will handle format)');
      await this.sendToWhisper(audioBlob);
      return;
    }

    // Unknown format, try anyway
    logger.warn('[processAudio] Unknown audio format, attempting transcription:', audioBlob.type);
    await this.sendToWhisper(audioBlob);
  }

  private async sendToWhisper(audioBlob: Blob): Promise<void> {
    try {
      this.recordingStatus.textContent = 'Transcribing...';
      let transactionPromptTokens = 0;
      let transactionCompletionTokens = 0;
      
      const selectedValue = this.transcriptionProviderSelector.value;
      let transcriptionProvider: TranscriptionProvider;
      let localModelId: string | null = null;

      if (selectedValue.startsWith('local:')) {
          transcriptionProvider = 'local';
          localModelId = selectedValue.substring(6);
      } else {
          transcriptionProvider = selectedValue as TranscriptionProvider;
          localModelId = this.apiSettings.local.activeModelId; // For fallback cases
      }

      let forcedLanguage: string | undefined;
      if (transcriptionProvider === 'local' && localModelId) {
        const meta = getLocalModelMeta(localModelId);
        const defaultLanguage = meta?.language === 'English' ? 'en' : 'auto';
        forcedLanguage = this.resolveForcedLocalLanguage(defaultLanguage);
      }

  const transcriptionData = await this.apiClient.transcribeAudio(audioBlob, transcriptionProvider, localModelId, forcedLanguage);
      const transcriptionText = transcriptionData.text;
      
  const isPolishingEnabled = !!this.modelSelector.value;

  if (this.isHotkeyRecording) {
        this.recordingStatus.textContent = 'Processing hotkey...';
        
        let textToSend = transcriptionText;
        let pResult: ApiResponse | null = null; // standard polish
        let pX2Result: ApiResponse | null = null; // x2 polish
        
        // --- Step 1: Get the required text for pasting, and ONLY that text ---
  // Skip polishing entirely if user chose Raw as hotkey target
  const shouldPolishForHotkey = isPolishingEnabled && this.hotkeySettings.target !== 'raw';
  if (shouldPolishForHotkey) {
          if (this.hotkeySettings.target === 'note') {
            try {
              pResult = await this.getPolishedNote('standard', transcriptionText);
              if (pResult?.text) textToSend = pResult.text;
            } catch (e) { logger.error('[HOTKEY] Standard polishing failed, falling back to raw.', e); }
          } else if (this.hotkeySettings.target === 'x2') {
            try {
              pX2Result = await this.getPolishedNote('x2', transcriptionText);
              if (pX2Result?.text) textToSend = pX2Result.text;
            } catch (e) { logger.error('[HOTKEY] X2 polishing failed, falling back to raw.', e); }
          }
        }

        // --- Step 2: Send the text to the main process IMMEDIATELY ---
        if (textToSend) {
            logger.info(`[HOTKEY] Prioritizing IPC send for paste. Length: ${textToSend.length}`);
            ipcRenderer?.send('clipboard-changed', textToSend);
        }

        // --- Step 3: Update UI & get missing polished versions ---
        // Switch overlay to Processing state while AI work continues (for all hotkey targets)
        try {
          ipcRenderer?.send('log-message', { level: 'info', message: '[Overlay] Renderer: sendToWhisper → hotkey-processing-start' });
          ipcRenderer?.send('hotkey-processing-start');
        } catch {}
        this.appendToContentArea(this.rawTranscription, transcriptionText);
        
  const otherPolishPromises: Promise<any>[] = [];
  if (shouldPolishForHotkey) {
          if (!pResult) { // Fetch standard if not already fetched
            otherPolishPromises.push(
              this.getPolishedNote('standard', transcriptionText).then(r => { pResult = r; }).catch(() => { pResult = null; })
            );
          }
          if (!pX2Result) { // Fetch x2 if not already fetched
             otherPolishPromises.push(
              this.getPolishedNote('x2', transcriptionText).then(r => { pX2Result = r; }).catch(() => { pX2Result = null; })
            );
          }
        }
        
        await Promise.allSettled(otherPolishPromises);
        
        // --- Step 4: Update the rest of the UI with all available data ---
  if (pResult) {
            const html = await marked.parse(pResult.text || '');
            this.appendToContentArea(this.polishedNote, html || '<em>Polishing returned empty.</em>');
  } else if (shouldPolishForHotkey) {
            this.appendToContentArea(this.polishedNote, '<em>Error during polishing.</em>');
        } else {
            this.appendToContentArea(this.polishedNote, '<em>Polishing is disabled.</em>');
        }

  if (pX2Result) {
            const html = await marked.parse(pX2Result.text || '');
            this.appendToContentArea(this.polishedNoteX2, html || '<em>Polishing returned empty.</em>');
  } else if (shouldPolishForHotkey) {
            this.appendToContentArea(this.polishedNoteX2, '<em>Error during polishing.</em>');
        } else {
            this.appendToContentArea(this.polishedNoteX2, '<em>Polishing is disabled.</em>');
        }
        
        // --- Step 5: Calculate total tokens for the transaction ---
        transactionPromptTokens = transcriptionData.promptTokens + (pResult?.promptTokens || 0) + (pX2Result?.promptTokens || 0);
        transactionCompletionTokens = transcriptionData.completionTokens + (pResult?.completionTokens || 0) + (pX2Result?.completionTokens || 0);

      } else {
        // --- NORMAL (NON-HOTKEY) PROCESSING ---
        this.appendToContentArea(this.rawTranscription, transcriptionText);
        transactionPromptTokens += transcriptionData.promptTokens;
        transactionCompletionTokens += transcriptionData.completionTokens;
        
        if (isPolishingEnabled) {
          this.recordingStatus.textContent = 'Transcription complete. Polishing notes...';
          const [polishedResult, polishedX2Result] = await Promise.allSettled([
            this.getPolishedNote('standard', transcriptionText),
            this.getPolishedNote('x2', transcriptionText),
          ]);
          
          let errorAlreadyShown = false;
          const handleError = (reason: any) => {
            if (errorAlreadyShown) return;
            errorAlreadyShown = true; // Prevent showing multiple modals for the same batch
            if (reason instanceof ApiError && reason.isQuotaError) {
              this.showErrorDialog('API Quota Exceeded', 'You have exceeded your current API quota. Please check your plan, or switch providers in Settings.');
            } else if (reason instanceof Error) {
              this.showErrorDialog('Polishing Error', reason.message);
            }
          };

          if (polishedResult.status === 'fulfilled' && polishedResult.value) {
            const { text, promptTokens, completionTokens } = polishedResult.value;
            const html = await marked.parse(text || '');
            this.appendToContentArea(this.polishedNote, html || '<em>Polishing returned empty.</em>');
            transactionPromptTokens += promptTokens;
            transactionCompletionTokens += completionTokens;
          } else {
            this.appendToContentArea(this.polishedNote, '<em>Error during polishing.</em>');
            handleError((polishedResult as PromiseRejectedResult).reason);
          }

          if (polishedX2Result.status === 'fulfilled' && polishedX2Result.value) {
            const { text, promptTokens, completionTokens } = polishedX2Result.value;
            const html = await marked.parse(text || '');
            this.appendToContentArea(this.polishedNoteX2, html || '<em>Polishing returned empty.</em>');
            transactionPromptTokens += promptTokens;
            transactionCompletionTokens += completionTokens;
          } else {
            this.appendToContentArea(this.polishedNoteX2, '<em>Error during polishing.</em>');
            handleError((polishedX2Result as PromiseRejectedResult).reason);
          }
        } else {
            this.appendToContentArea(this.polishedNote, '<em>Polishing is disabled. Select a model from the dropdown or in Settings.</em>');
            this.appendToContentArea(this.polishedNoteX2, '<em>Polishing is disabled. Select a model from the dropdown or in Settings.</em>');
        }
      }

      const modelId = this.modelSelector.value;
      if (modelId) {
        if (!this.usageStats[modelId]) {
          this.usageStats[modelId] = { promptTokens: 0, completionTokens: 0 };
        }
        this.usageStats[modelId].promptTokens += transactionPromptTokens;
        this.usageStats[modelId].completionTokens += transactionCompletionTokens;
      }

      this.updateLastTransactionDisplay(transactionPromptTokens, transactionCompletionTokens);
      this.updateStatsDisplay();
      this.saveUsageStats();
      
      if (this.isHotkeyRecording) {
        try { ipcRenderer?.send('hotkey-transcription-end'); } catch {}
        this.isHotkeyRecording = false;
        this.recordingStatus.textContent = 'Hotkey note ready. Ready to record.';
        this.maybeBeep('end');
      } else {
        this.recordingStatus.textContent = 'Note processed. Ready for next recording.';
      }
    } catch (error) {
        if (this.isHotkeyRecording) {
          try { ipcRenderer?.send('hotkey-transcription-end'); } catch {}
          this.isHotkeyRecording = false;
        }
        logger.error('Error in processAudio:', error);
        const message = error instanceof Error ? error.message : 'Please try again.';
        this.recordingStatus.textContent = `Error: Processing failed.`;

        if (error instanceof ApiError && error.isQuotaError) {
            this.showErrorDialog('API Quota Exceeded', 'You have exceeded your current API quota. Please check your plan and billing details, or switch to a different provider in Settings.');
        } else {
            this.showErrorDialog('Processing Error', message);
        }
        
        this.updateLastTransactionDisplay(0, 0);
    }
  }

  private loadOverlayPrefs(): void {
    try {
      const raw = localStorage.getItem(OVERLAY_PREFS_KEY);
      if (raw) {
        const obj = JSON.parse(raw);
        this.overlayPrefs = {
          position: (obj.position || 'bottom-right'),
          scale: typeof obj.scale === 'number' ? obj.scale : 1,
          sound: obj.sound !== undefined ? !!obj.sound : true,
          volume: typeof obj.volume === 'number' ? obj.volume : 0.6,
        } as any;
      }
    } catch {}
  }

  private applyOverlayPrefsToUi(): void {
    if (this.overlayPositionSelector) this.overlayPositionSelector.value = this.overlayPrefs.position;
    if (this.overlayScaleSlider) this.overlayScaleSlider.value = String(this.overlayPrefs.scale);
    if (this.overlayScaleValue) this.overlayScaleValue.textContent = `${Math.round(this.overlayPrefs.scale * 100)}%`;
    if (this.overlaySoundEnabledCheckbox) this.overlaySoundEnabledCheckbox.checked = !!this.overlayPrefs.sound;
  if (this.overlaySoundVolumeSlider) this.overlaySoundVolumeSlider.value = String(Math.round((this.overlayPrefs.volume || 0) * 100));
  if (this.overlaySoundVolumeValue) this.overlaySoundVolumeValue.textContent = `${Math.round((this.overlayPrefs.volume || 0) * 100)}%`;
  }

  private saveOverlayPrefsAndNotify(): void {
    try { localStorage.setItem(OVERLAY_PREFS_KEY, JSON.stringify(this.overlayPrefs)); } catch {}
    try {
      (window as any).ipcRenderer?.send('overlay:update-prefs', {
        position: this.overlayPrefs.position,
        scale: this.overlayPrefs.scale,
        sound: this.overlayPrefs.sound,
        volume: this.overlayPrefs.volume,
      });
    } catch {}
  }

  private maybeBeep(kind: 'start'|'end'): void {
    if (!this.overlayPrefs.sound) return;
    try {
      const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      const filter = ctx.createBiquadFilter();
      // Softer triangle tone with short envelope
      osc.type = 'triangle';
      // Two short, subtle blips for start; one softer for end
      const base = kind === 'start' ? 750 : 520;
      osc.frequency.value = base;
      filter.type = 'lowpass';
      filter.frequency.value = 2400;
      const v = Math.max(0.01, Math.min(0.5, (this.overlayPrefs.volume || 0.15)));
      gain.gain.setValueAtTime(0, ctx.currentTime);
      // Attack/decay envelope
      const now = ctx.currentTime;
      const dur = kind === 'start' ? 0.08 : 0.06;
      gain.gain.linearRampToValueAtTime(v, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);
      // Quick glide
      osc.frequency.setValueAtTime(base, now);
      osc.frequency.exponentialRampToValueAtTime(base * (kind === 'start' ? 1.08 : 0.96), now + dur);
      osc.connect(filter).connect(gain).connect(ctx.destination);
      osc.start(now);
      let stopAt = now + dur + 0.02;
      // For start, add a faint second blip
      if (kind === 'start') {
        const osc2 = ctx.createOscillator();
        const g2 = ctx.createGain();
        const f2 = ctx.createBiquadFilter();
        osc2.type = 'triangle';
        f2.type = 'lowpass'; f2.frequency.value = 2400;
        osc2.frequency.value = base * 1.12;
        const v2 = v * 0.7;
        g2.gain.setValueAtTime(0, now + 0.06);
        g2.gain.linearRampToValueAtTime(v2, now + 0.07);
        g2.gain.exponentialRampToValueAtTime(0.0001, now + 0.14);
        osc2.connect(f2).connect(g2).connect(ctx.destination);
        osc2.start(now + 0.06);
        osc2.stop(now + 0.16);
        stopAt = Math.max(stopAt, now + 0.16);
      }
      osc.stop(stopAt);
      setTimeout(() => { try { ctx.close(); } catch {} }, Math.ceil((stopAt - now) * 1000) + 10);
    } catch {}
  }

  private async getPolishedNote(
    level: 'standard' | 'x2',
    rawTextForPolishing: string,
  ): Promise<ApiResponse | null> {
    if (!rawTextForPolishing?.trim()) {
        return null;
    }
    
    try {
    const textToPolish = level === 'x2' ? `rewrite Variant 2 ${rawTextForPolishing}` : rawTextForPolishing;
        // Choose prompt based on level and saved per-variant settings
        const basePrompt = level === 'x2'
          ? (localStorage.getItem(PROMPT_STORAGE_KEY_V2) || DEFAULT_PROMPT_V2)
          : (localStorage.getItem(PROMPT_STORAGE_KEY_V1) || localStorage.getItem(PROMPT_STORAGE_KEY) || DEFAULT_PROMPT_V1);
        const prompt = basePrompt.replace(
          '${transcription}',
          textToPolish,
        );
        const modelIdentifier = this.modelSelector.value;
        logger.info(`[getPolishedNote] Polishing with model: "${modelIdentifier}"`);
        if (!modelIdentifier) {
            throw new Error('No polishing model selected.');
        }
        const result = await this.apiClient.generateText(
            modelIdentifier,
            prompt,
        );
        // Sanitize output to strip any model preambles and keep only the intended content
        const clean = this.sanitizeModelOutput(result.text || '');
        return { ...result, text: clean };
    } catch (error) {
        logger.error(`Error polishing note (level: ${level}):`, error);
        // Re-throw to be handled by the caller (`processAudio`)
        throw error;
    }
  }

  // Extract only the final text, tolerating small models that add prefaces
  private sanitizeModelOutput(text: string): string {
    if (!text) return '';
    try {
      // Remove problematic markers that Local LLMs often add
      let cleaned = text.trim();
      
      // Remove various marker patterns that Local LLMs add
      cleaned = cleaned.replace(/^<<>>\s*/g, ''); // Remove <<>> at start
      cleaned = cleaned.replace(/^<<<<>>>>\s*/g, ''); // Remove <<<<>>>> at start
      cleaned = cleaned.replace(/^<<<.*?>>>\s*/g, ''); // Remove any <<<...>>> at start
      cleaned = cleaned.replace(/^\*\*.*?\*\*\s*/g, ''); // Remove **text** at start
      cleaned = cleaned.replace(/^Variant\s+\d+\s*/i, ''); // Remove "Variant 2" prefix
      
      // Prefer explicit markers if present (legacy support)
      const begin = '<<<BEGIN>>>';
      const end = '<<<END>>>';
      const b = cleaned.indexOf(begin);
      const e = cleaned.indexOf(end);
      if (b !== -1 && e !== -1 && e > b) {
        return cleaned.substring(b + begin.length, e).trim();
      }

      // If model echoed our INPUT markers, try to strip them
      const inBegin = '<<<INPUT>>>';
      const inEnd = '<<<END_INPUT>>>';
      const ib = cleaned.indexOf(inBegin);
      const ie = cleaned.indexOf(inEnd);
      if (ib !== -1 && ie !== -1 && ie > ib) {
        // Remove the whole input block and anything outside
        const before = cleaned.substring(0, ib).trim();
        const after = cleaned.substring(ie + inEnd.length).trim();
        // Prefer whatever is after the input block
        const candidate = (after || before).trim();
        if (candidate) cleaned = candidate;
      }

      // Remove common Local LLM preambles and unwanted responses
      const preamblePatterns = [
        /^\s*(ok|okay|sure)[\.,!\s-]*\b/i,
        /^\s*i\s*(will|can|understand|understood|shall)\b[^\n]*\n*/i,
        /^\s*(here is|here's)\b[^\n]*\n*/i,
        /^\s*(processed|formatted)\s*text\s*[:\-]*\s*/i,
        /^\s*(as requested|as you requested)\b[^\n]*\n*/i,
        /^\s*let me\b[^\n]*\n*/i,
        /^\s*i'll\b[^\n]*\n*/i,
        /^\s*the\s+(cleaned|processed|enhanced)\s+text\s*[:\-]*\s*/i,
        /^\s*(хорошо|конечно|понятно)\b[^\n]*\n*/i, // Russian equivalents
      ];
      for (const rx of preamblePatterns) {
        cleaned = cleaned.replace(rx, '').trim();
      }

      // If the model wrapped in code fences, unwrap
      cleaned = cleaned.replace(/^```[a-zA-Z]*\n([\s\S]*?)\n```\s*$/m, '$1').trim();
      
      // Fix common language mixing issues in mixed responses
      // Replace English words that snuck into Russian text
      cleaned = cleaned.replace(/\bfinally\b/gi, 'наконец');
      cleaned = cleaned.replace(/\bhorizon\b/gi, 'горизонт');
      cleaned = cleaned.replace(/\bhorizont?е\b/gi, 'горизонте');
      cleaned = cleaned.replace(/\breally\b/gi, 'действительно');
      cleaned = cleaned.replace(/\bmoment\b/gi, 'момент');
      
      // For Local LLMs that tend to be chatty, try to extract just the first meaningful sentence/paragraph
      // If the response contains obvious analysis or questions, take only the part before that
      const chattyPatterns = [
        /^([^.!?]*[.!?])\s*(?:But |However |Also |Additionally |Furthermore |Moreover |I think |I believe |It's |This |After all |And who knows)/i,
        /^([^.!?]*[.!?])\s*(?:А |Но |Однако |Также |Кроме того |Я думаю |Я считаю |Это |После |И кто знает)/i,
      ];
      
      for (const rx of chattyPatterns) {
        const match = cleaned.match(rx);
        if (match && match[1].trim().length > 10) { // Only if we get a meaningful first part
          cleaned = match[1].trim();
          break;
        }
      }
      
      return cleaned;
    } catch {
      return text;
    }
  }

  // --- Prompt sub-tabs ---
  private setActivePromptSubTab(activeButton: HTMLButtonElement): void {
    const sub = activeButton.getAttribute('data-subtab');
    if (this.promptSubTabButtons) {
      this.promptSubTabButtons.forEach((b) => b.classList.toggle('active', b === activeButton));
    }
    if (this.promptSubTabContents) {
      this.promptSubTabContents.forEach((c) => {
        const shouldBeActive = c.id === (sub === 'raw' ? 'promptRawContent' : sub === 'v1' ? 'promptV1Content' : 'promptV2Content');
        c.classList.toggle('active', shouldBeActive);
      });
    }
  }

  private appendToContentArea(element: HTMLElement, newContent: string): void {
    if (!newContent?.trim()) return;
    const placeholder = element.getAttribute('placeholder') || '';
    const isCurrentlyEmpty =
      element.classList.contains('placeholder-active') ||
      element.innerHTML.trim() === '' ||
      element.innerHTML.trim() === placeholder;
  const copyBtn = `<button class=\"copy-bubble-btn left\" tabindex=\"-1\" title=\"${this.t('tooltip.copy')}\" onmousedown=\"return false\"><span class=\"icon icon-copy\" aria-hidden=\"true\"></span></button>`;
  const deleteBtn = `<button class=\"copy-bubble-btn delete\" tabindex=\"-1\" aria-hidden=\"true\" title=\"Delete note\" onmousedown=\"return false\"><i class=\"fas fa-trash\"></i></button>`;
  const block = `<div class=\"note-section\">${deleteBtn}${copyBtn}<div class=\"note-chunk\" contenteditable=\"true\">${newContent}</div></div>`;
    if (isCurrentlyEmpty) element.innerHTML = block;
    else element.innerHTML += '<hr>' + block;
    element.classList.remove('placeholder-active');
  // Scroll the note content wrapper (the actual scroll container)
  const scroller = document.querySelector('.note-content-wrapper') as HTMLElement | null;
    if (scroller) {
      requestAnimationFrame(() => (scroller.scrollTop = scroller.scrollHeight));
    } else {
      // Fallback to the immediate parent if main-content isn't found
      const wrapper = element.parentElement as HTMLElement | null;
      if (wrapper) requestAnimationFrame(() => (wrapper.scrollTop = wrapper.scrollHeight));
    }
  }

  private clearAllContent(): void {
    [this.rawTranscription, this.polishedNote, this.polishedNoteX2].forEach(
      (el) => {
        const placeholder = el.getAttribute('placeholder') || '';
        el.innerHTML = placeholder;
        el.classList.add('placeholder-active');
      },
    );
    this.checkApiConnectivity();
    this.updateLastTransactionDisplay(0, 0);
    if (this.isRecording) {
      this.mediaRecorder?.stop();
      this.isRecording = false;
      this.recordButton.classList.remove('recording');
    } else this.stopLiveDisplay();
  }

  private async copyPolishedNote(): Promise<void> {
    const activeTab = document
      .querySelector('.tab-button.active')
      ?.getAttribute('data-tab');
    let elementToCopy: HTMLElement | null = null;
    switch (activeTab) {
      case 'raw':
        elementToCopy = this.rawTranscription;
        break;
      case 'note':
        elementToCopy = this.polishedNote;
        break;
      case 'x2':
        elementToCopy = this.polishedNoteX2;
        break;
    }
    if (!elementToCopy || !elementToCopy.innerText || elementToCopy.classList.contains('placeholder-active')) return;
    try {
      await navigator.clipboard.writeText(elementToCopy.innerText);
    this.copyButton?.classList.add('copied');
    setTimeout(() => this.copyButton?.classList.remove('copied'), 2000);
    } catch (err) {
      logger.error('Failed to copy text: ', err);
    }
  }

  private handleCreateEmptyNote(): void {
  // Always create an empty note section in Raw with proper spacing
  const target: HTMLElement | null = this.rawTranscription;
  if (!target) return;
  // Ensure we're on Raw so typing/paste goes to the correct area
  const rawTabBtn = document.querySelector('.tab-button[data-tab="raw"]') as HTMLElement | null;
  if (rawTabBtn) this.setActiveTab(rawTabBtn);
  // Blur the launcher button so it doesn't keep focus
  (document.getElementById('createEmptyNoteButton') as HTMLButtonElement | null)?.blur();
    const placeholder = target.getAttribute('placeholder') || '';
    const isCurrentlyEmpty =
      target.classList.contains('placeholder-active') ||
      target.innerHTML.trim() === '' ||
      target.innerHTML.trim() === placeholder;

  const copyBtn = `<button class=\"copy-bubble-btn left\" tabindex=\"-1\" aria-hidden=\"true\" title=\"${this.t('tooltip.copy')}\" onmousedown=\"return false\"><span class=\"icon icon-copy\" aria-hidden=\"true\"></span></button>`;
  const deleteTitle = 'Delete note';
  const deleteBtn = `<button class=\"copy-bubble-btn delete\" tabindex=\"-1\" aria-hidden=\"true\" title=\"${deleteTitle}\" onmousedown=\"return false\"><i class=\"fas fa-trash\"></i></button>`;
  const polishTitle = (() => { const v = this.t('tooltip.polish'); return v && v !== 'tooltip.polish' ? v : 'Polish'; })();
  const polishBtn = `<button class=\"copy-bubble-btn polish left2\" tabindex=\"-1\" aria-hidden=\"true\" title=\"${polishTitle}\" onmousedown=\"return false\"><i class=\"fas fa-magic\"></i></button>`;
  // Create an empty editable chunk with a placeholder tip
  const tip = 'Type or Paste text here for polishing...';
  const block = `<div class=\"note-section\">${deleteBtn}${copyBtn}${polishBtn}<div class=\"note-chunk placeholder-active\" contenteditable=\"true\" placeholder=\"${tip}\">${tip}</div></div>`;
    if (isCurrentlyEmpty) target.innerHTML = block;
    else target.innerHTML += '<hr>' + block;
    target.classList.remove('placeholder-active');

  // Place the caret inside the new chunk so typing/paste goes here
  const lastSection = target.querySelector('.note-section:last-of-type .note-chunk') as HTMLElement | null;
    if (lastSection) {
      // Bind placeholder behavior for this dynamic element
      const placeholder = lastSection.getAttribute('placeholder') || tip;
    const clearPlaceholder = () => {
        if (lastSection.classList.contains('placeholder-active')) {
      lastSection.innerHTML = '';
          lastSection.classList.remove('placeholder-active');
      // Add a ZWSP to anchor caret when empty
      if (!lastSection.textContent) lastSection.textContent = '\u200B';
        }
      };
      const restorePlaceholderIfEmpty = () => {
        const txt = lastSection.innerText?.trim() || '';
        if (!txt) {
          lastSection.innerHTML = placeholder;
          lastSection.classList.add('placeholder-active');
        }
      };
      // On first input/paste/keydown, clear the tip
      const onFirstInput = () => { clearPlaceholder(); lastSection.removeEventListener('beforeinput', onFirstInput); lastSection.removeEventListener('keydown', onFirstInput); lastSection.removeEventListener('paste', onFirstInput); };
      lastSection.addEventListener('beforeinput', onFirstInput, { once: false });
      lastSection.addEventListener('keydown', onFirstInput, { once: false });
      lastSection.addEventListener('paste', onFirstInput, { once: false });
      // Maintain placeholder on blur if left empty
  lastSection.addEventListener('blur', restorePlaceholderIfEmpty);
      // Focus the chunk so paste goes here immediately (defer to end of frame)
      requestAnimationFrame(() => {
        lastSection.focus();
        const sel = window.getSelection();
        if (sel) {
          sel.selectAllChildren(lastSection);
          sel.collapseToEnd();
        }
      });
  // Remember this chunk as the current paste target
  this.lastFocusedChunk = lastSection;
  lastSection.addEventListener('focus', () => { this.lastFocusedChunk = lastSection; });
      // Ensure it becomes visible
      // Make sure it’s visible
      lastSection.scrollIntoView({ block: 'nearest' });
    }

    // Ensure scroller is at bottom
    const scroller = document.querySelector('.note-content-wrapper') as HTMLElement | null;
    if (scroller) requestAnimationFrame(() => (scroller.scrollTop = scroller.scrollHeight));
  }
private async handleTranscribeAudioFile(): Promise<void> {
  try {
    // 1) убедимся, что выбран локальный модельный id
    const activeModelId = this.apiSettings?.local?.activeModelId;
    if (!activeModelId) {
      alert('Select a Local model first: Settings → Local Models.');
      return;
    }

    // 2) попросим у main путь к wav/mp3/flac и т. п.
    const wavPath = await (window as any).ipcRenderer.invoke('pick-audio-file'); // main.js: ipcMain.handle('pick-audio-file', ...)
    if (!wavPath) return;

  // Indicate busy state in UI
  const prevStatus = this.recordingStatus?.textContent || '';
  if (this.recordingStatus) this.recordingStatus.textContent = 'Transcribing…';

    // 3) показываем, куда пишем (Raw)
    const rawTabBtn = document.querySelector('.tab-button[data-tab="raw"]') as HTMLElement | null;
    if (rawTabBtn) this.setActiveTab(rawTabBtn);

    // 4) пускаем транскрипцию через worker (без auto-download, только установленная модель)
    const modelMeta = getLocalModelMeta(activeModelId);
    const defaultLang = modelMeta?.language === 'English' ? 'en' : 'auto';
    const forcedLang = this.resolveForcedLocalLanguage(defaultLang);
    const result = await (window as any).ipcRenderer.invoke('whisper:transcribeFile', {
      modelId: activeModelId,
      fname_inp: wavPath,
      options: {
        language: forcedLang,
        forceCpu: false,
        threads: 0,
      },
    });

    // 5) приводим ответ к тексту и кладём в Raw
    const text =
      Array.isArray(result?.transcription)
        ? result.transcription.map((seg: any) => seg[2]).join(' ')
        : (result?.text || '');

    if (text?.trim()) {
      this.appendToContentArea(this.rawTranscription, text);
    } else {
      this.appendToContentArea(this.rawTranscription, '[Empty transcription]');
    }
  // Restore status
  if (this.recordingStatus) this.recordingStatus.textContent = prevStatus || 'Ready to record';
  } catch (err: any) {
    console.error(err);
    alert(`Transcription failed: ${err?.message || err}`);
  if (this.recordingStatus) this.recordingStatus.textContent = 'Ready to record';
  }
}

private async handleTranscribeDroppedFiles(paths: string[]): Promise<void> {
  try {
    const activeModelId = this.apiSettings?.local?.activeModelId;
    if (!activeModelId) {
      alert('Select a Local model first: Settings → Local Models.');
      return;
    }

    if (!paths || !paths.length) return;

  const prevStatus = this.recordingStatus?.textContent || '';
  if (this.recordingStatus) this.recordingStatus.textContent = 'Transcribing…';

    const rawTabBtn = document.querySelector('.tab-button[data-tab="raw"]') as HTMLElement | null;
    if (rawTabBtn) this.setActiveTab(rawTabBtn);

    for (const fname_inp of paths) {
      try {
        const modelMeta = getLocalModelMeta(activeModelId);
        const defaultLang = modelMeta?.language === 'English' ? 'en' : 'auto';
        const forcedLang = this.resolveForcedLocalLanguage(defaultLang);
        const result = await (window as any).ipcRenderer.invoke('whisper:transcribeFile', {
          modelId: activeModelId,
          fname_inp,
          options: {
            language: forcedLang,
            forceCpu: false,
            threads: 0,
          },
        });
        const text = Array.isArray(result?.transcription)
          ? result.transcription.map((seg: any) => seg[2]).join(' ')
          : (result?.text || '');
        if (text?.trim()) this.appendToContentArea(this.rawTranscription, text);
        else this.appendToContentArea(this.rawTranscription, '[Empty transcription]');
      } catch (err:any) {
        console.error('Dropped file transcription failed:', err);
        this.appendToContentArea(this.rawTranscription, `[Transcription failed: ${err?.message || err}]`);
      }
    }
  if (this.recordingStatus) this.recordingStatus.textContent = prevStatus || 'Ready to record';
  } catch (e) {
    console.error(e);
  if (this.recordingStatus) this.recordingStatus.textContent = 'Ready to record';
  }
}

  // --- Settings & Modal Methods ---
  private openPromptModal(): void {
    // Load per-variant custom prompts into textareas when opening
  // RAW prompt removed
    if (this.customPromptV1Textarea)
      this.customPromptV1Textarea.value = localStorage.getItem(PROMPT_STORAGE_KEY_V1) || (localStorage.getItem(PROMPT_STORAGE_KEY) || DEFAULT_PROMPT_V1);
    if (this.customPromptV2Textarea)
      this.customPromptV2Textarea.value = localStorage.getItem(PROMPT_STORAGE_KEY_V2) || DEFAULT_PROMPT_V2;
    
    // API provider settings
    this.apiSettingsInputs.forEach((input) => {
      const el = input as HTMLInputElement;
      const provider = el.dataset.provider as keyof ApiSettings;
      const field = el.dataset.field as keyof ApiProviderSettings;
      if (provider && field) {
        if (el.type === 'checkbox') {
            el.checked = (this.apiSettings[provider] as any)[field] || false;
        } else {
            el.value = (this.apiSettings[provider] as any)[field] || '';
        }
      }
    });

    // Staging for local model selection
    this.stagedActiveLocalModelId = this.apiSettings.local.activeModelId;
    this.renderLocalModelsList();

    // Translation settings (moved to Translation modal; ensure element exists if modal already mounted)
    if (this.targetLanguageSelector) {
      // If saved language isn't in options, set to custom and show input
      const saved = (this.translationSettings.targetLanguage || '').trim();
      const options = Array.from(this.targetLanguageSelector.options).map(o => o.value);
      const customInput = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
      if (saved && !options.includes(saved)) {
        this.targetLanguageSelector.value = 'custom';
        if (customInput) { customInput.style.display = 'block'; customInput.value = saved; }
      } else {
        this.targetLanguageSelector.value = saved || 'English';
        if (customInput) { customInput.style.display = 'none'; customInput.value = ''; }
      }
      this.targetLanguageSelector.dispatchEvent(new Event('change')); // Force custom select update
    }

    // Hotkey settings
    (document.getElementById('hotkeyEnabled') as HTMLInputElement).checked = this.hotkeySettings.enabled;
    const hotkeyTargetSelect = document.getElementById('hotkeyTarget') as HTMLSelectElement;
    hotkeyTargetSelect.value = this.hotkeySettings.target;
    hotkeyTargetSelect.dispatchEvent(new Event('change')); // Force custom select update
    const hotkeyModeSelect = document.getElementById('hotkeyMode') as HTMLSelectElement;
    hotkeyModeSelect.value = this.hotkeySettings.mode || 'typing'; // Default to typing if undefined
    hotkeyModeSelect.dispatchEvent(new Event('change')); // Force custom select update
    this.hotkeyInput.value = this.hotkeySettings.hotkey;
    this.hotkeyError.style.display = 'none';

    this.updateStatsDisplay();
    this.promptModal.classList.add('visible');
    this.promptModalOverlay.classList.add('visible');
    document.body.classList.add('modal-open');
    const defaultTab = this.settingsTabButtons[0];
    if (defaultTab) this.setActiveSettingsTab(defaultTab);
  }

  private closePromptModal(): void {
    if (this.isListeningForHotkey) {
        this.stopListeningForHotkey();
        this.hotkeyInput.value = this.hotkeySettings.hotkey; // Revert to saved value
    }
    this.promptModal.classList.remove('visible');
    this.promptModalOverlay.classList.remove('visible');
    if (!this.translationResultModal.classList.contains('visible')) {
      document.body.classList.remove('modal-open');
    }
    // Revert any non-saved changes by reloading from storage
    this.loadApiSettings();
    this.loadTranslationSettings();
    this.loadHotkeySettings();
    this.updateModelSelector();
    this.updateTranscriptionProviderSelector();
    this.updateStatsDisplay();
    this.checkApiConnectivity();
  }

  private saveSettings(): void {
    // Save per-variant prompts
  // RAW prompt removed
    const v1Prompt = this.customPromptV1Textarea?.value?.trim();
    if (v1Prompt) {
      localStorage.setItem(PROMPT_STORAGE_KEY_V1, v1Prompt);
      // Keep legacy key in sync for backward compatibility
      localStorage.setItem(PROMPT_STORAGE_KEY, v1Prompt);
      this.customPolishPrompt = v1Prompt;
    }
    const v2Prompt = this.customPromptV2Textarea?.value?.trim();
    if (v2Prompt) {
      localStorage.setItem(PROMPT_STORAGE_KEY_V2, v2Prompt);
    }
    
    // Commit staged local model change and save all API settings
    this.apiSettings.local.activeModelId = this.stagedActiveLocalModelId;
    this.saveApiSettings();

    // If a local model is now active, set it as the current transcription provider.
    if (this.apiSettings.local.activeModelId) {
        localStorage.setItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY, `local:${this.apiSettings.local.activeModelId}`);
    } else {
        // If a local model was DE-activated, check if it was the active provider.
        const currentProvider = localStorage.getItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY);
        // If the current provider is any local model, clear it to force a fallback.
        if (currentProvider && currentProvider.startsWith('local:')) {
            localStorage.removeItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY);
        }
    }
    
  // Save Hotkey settings (translation settings saved from modal now)
    this.saveHotkeySettings();

    if (ipcRenderer) {
        ipcRenderer.send('update-hotkey', this.hotkeySettings);
    }
    
    // Close modal *without* reverting changes
    this.promptModal.classList.remove('visible');
    this.promptModalOverlay.classList.remove('visible');
    if (!this.translationResultModal.classList.contains('visible')) {
      document.body.classList.remove('modal-open');
    }
    // Now update the UI with the saved settings
    this.updateModelSelector();
    this.updateTranscriptionProviderSelector();
    this.updateStatsDisplay();
    this.checkApiConnectivity();
  }

  private loadApiSettings(): void {
    const storedSettings = localStorage.getItem(API_SETTINGS_KEY);
    const defaultSettings: ApiSettings = {
      google: {apiKey: '', textModel: 'gemini-2.5-flash'},
      openai: {apiKey: '', textModel: 'gpt-4o-mini'},
      anthropic: {apiKey: '', textModel: 'claude-3-haiku-20240307'},
      custom: {name: '', baseUrl: '', apiKey: '', textModel: ''},
      local: {activeModelId: null},
    };
    const loadedSettings = storedSettings ? JSON.parse(storedSettings) : {};
    this.apiSettings = {
        google: {...defaultSettings.google, ...loadedSettings.google},
        openai: {...defaultSettings.openai, ...loadedSettings.openai},
        anthropic: {...defaultSettings.anthropic, ...loadedSettings.anthropic},
        custom: {...defaultSettings.custom, ...loadedSettings.custom},
        local: {...defaultSettings.local, ...loadedSettings.local},
    };
  }

  private saveApiSettings(): void {
    this.apiSettingsInputs.forEach((input) => {
      const el = input as HTMLInputElement;
      const provider = el.dataset.provider as keyof ApiSettings;
      const field = el.dataset.field as keyof ApiProviderSettings;
      if (provider && field) {
        (this.apiSettings[provider] as any)[field] = el.value.trim();
      }
    });
    // This now saves the entire settings object, including the 'local' part
    // which is modified in the UI before saving.
    localStorage.setItem(API_SETTINGS_KEY, JSON.stringify(this.apiSettings));
  }

  private updateModelSelector(): void {
    const savedModel = localStorage.getItem(SELECTED_POLISHING_MODEL_KEY);
    this.modelSelector.innerHTML = '';
    let hasModels = false;

    // Add the "Disabled" option first
    const disabledOption = document.createElement('option');
    disabledOption.value = '';
    disabledOption.textContent = 'Polishing Disabled';
    this.modelSelector.appendChild(disabledOption);

    const addOption = (label: string, value: string) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = label;
      this.modelSelector.appendChild(option);
      hasModels = true;
    };
    
  if (this.apiSettings.google.apiKey)
      addOption('Google Gemini 2.5 Flash', 'google:gemini-2.5-flash');
    if (this.apiSettings.openai.apiKey && this.apiSettings.openai.textModel)
      addOption(
        `OpenAI ${this.apiSettings.openai.textModel}`,
        `openai:${this.apiSettings.openai.textModel}`,
      );
    if (
      this.apiSettings.anthropic.apiKey &&
      this.apiSettings.anthropic.textModel
    )
      addOption(
        `Anthropic ${this.apiSettings.anthropic.textModel}`,
        `anthropic:${this.apiSettings.anthropic.textModel}`,
      );
    if (
      this.apiSettings.custom.apiKey &&
      this.apiSettings.custom.textModel &&
      this.apiSettings.custom.name
    )
      addOption(
        `${this.apiSettings.custom.name} ${this.apiSettings.custom.textModel}`,
        `custom:${this.apiSettings.custom.textModel}`,
      );

    // Add Ollama models if any are downloaded (both curated and discovered), excluding blocklisted
    Object.keys(this.ollamaModelsState).forEach(modelId => {
      if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) return;
      const state = this.ollamaModelsState[modelId];
      if (state?.status === 'downloaded') {
        const curatedModel = AVAILABLE_OLLAMA_MODELS.find(m => m.id === modelId);
        const displayName = curatedModel ? curatedModel.name : modelId;
        const badge = curatedModel?.badge ? ` • ${curatedModel.badge}` : '';
        addOption(`🏠 ${displayName}${badge}`, `ollama:${modelId}`);
      }
    });

    // Restore saved selection or set a sensible default
    const optionExists = savedModel !== null && Array.from(this.modelSelector.options).some(opt => opt.value === savedModel);

    if (optionExists) {
        this.modelSelector.value = savedModel!;
    } else if (hasModels && this.modelSelector.options[1]) {
        // If no valid model was saved but models exist, select the first one (after 'disabled')
        this.modelSelector.value = this.modelSelector.options[1].value;
    } else {
        // Default to disabled
        this.modelSelector.value = '';
    }
    
    // The selector should only be disabled if there are NO models available to choose from.
    // Since "Disabled" is always an option, we only disable if there are no OTHER models.
    this.modelSelector.disabled = !hasModels;

    // Save the current selection for persistence
    localStorage.setItem(SELECTED_POLISHING_MODEL_KEY, this.modelSelector.value);
    
    this.updateTranslateButtonState();
  }
  
  private updateTranscriptionProviderSelector(): void {
    const selector = this.transcriptionProviderSelector;
    if (!selector) return;

    const settings = this.apiSettings;
    const savedProviderValue = localStorage.getItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY);
    
    // On load, if saved provider is a local model, make sure it's set as active
    if (savedProviderValue && savedProviderValue.startsWith('local:')) {
        const modelId = savedProviderValue.substring(6);
        const state = this.localModelsState[modelId];
        // Only set if downloaded, otherwise it's invalid
        if (state?.status === 'downloaded') {
            this.apiSettings.local.activeModelId = modelId;
        }
    }

    selector.innerHTML = '';
    const availableOptions: { value: string; text: string }[] = [];

    // Add local models that are downloaded
    AVAILABLE_LOCAL_MODELS.forEach(model => {
        const state = this.localModelsState[model.id];
        if (state?.status === 'downloaded') {
            availableOptions.push({
                value: `local:${model.id}`,
                text: `Local: ${model.name.replace(/(Whisper |\(Quantized\))/g, '').trim()}`
            });
        }
    });

    // Add API-based providers
    if (settings.openai.apiKey) {
        availableOptions.push({ value: 'openai', text: 'OpenAI Whisper' });
    }
  if (settings.google.apiKey) {
        availableOptions.push({ value: 'google', text: 'Google Gemini' });
    }

    if (availableOptions.length > 0) {
        availableOptions.forEach(opt => {
            const optionEl = document.createElement('option');
            optionEl.value = opt.value;
            optionEl.textContent = opt.text;
            selector.appendChild(optionEl);
        });
        selector.disabled = false;
    } else {
        const optionEl = document.createElement('option');
        optionEl.textContent = 'No Transcriber';
        optionEl.disabled = true;
        selector.appendChild(optionEl);
        selector.disabled = true;
    }

    // Restore selection or pick first available
    if (savedProviderValue && availableOptions.some(o => o.value === savedProviderValue)) {
        selector.value = savedProviderValue;
    } else if (availableOptions.length > 0) {
        selector.value = availableOptions[0].value;
        // If we defaulted, update the local storage and active model if needed
        localStorage.setItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY, selector.value);
        if (selector.value.startsWith('local:')) {
            this.apiSettings.local.activeModelId = selector.value.substring(6);
        }
    }
    
    const setDefaultTab = () => {
        const isLocal = selector.value.startsWith('local:');
        const tabToActivate = isLocal ? 'raw' : 'note';
        const activeButton = document.querySelector(`.tab-button[data-tab="${tabToActivate}"]`) as HTMLElement;
        if (activeButton) {
            this.setActiveTab(activeButton, true);
        }
    };

    selector.onchange = () => {
        const selectedValue = selector.value;
        localStorage.setItem(SELECTED_TRANSCRIPTION_PROVIDER_KEY, selectedValue);

        let activeModelId: string | null = null;
        if (selectedValue.startsWith('local:')) {
            activeModelId = selectedValue.substring(6);
        }

        // Update both the main state and the modal's staged state simultaneously.
        this.apiSettings.local.activeModelId = activeModelId;
        this.stagedActiveLocalModelId = activeModelId;
        
        // Always save the updated settings object to keep it in sync.
        localStorage.setItem(API_SETTINGS_KEY, JSON.stringify(this.apiSettings));
        
        this.checkApiConnectivity();
        setDefaultTab();
    };

    // Initial calls
    this.checkApiConnectivity();
    setDefaultTab();
    selector.dispatchEvent(new Event('change')); // Ensure custom select UI updates
  }

  private handleModelSelectorChange(): void {
    const selectedValue = this.modelSelector.value;

    // If an Ollama model is selected, keep its ID; otherwise clear it
    if (selectedValue && selectedValue.startsWith('ollama:')) {
      const modelId = selectedValue.substring(7);
      this.selectedOllamaModelId = modelId;
      this.saveSelectedOllamaModel();
      this.renderOllamaModelsList();
    } else {
      this.selectedOllamaModelId = null;
      this.saveSelectedOllamaModel();
      this.renderOllamaModelsList();
    }
  }

  private updateLastTransactionDisplay(p = 0, c = 0): void {
    this.lastTxPromptTokensElement.textContent = p.toLocaleString();
    this.lastTxCompletionTokensElement.textContent = c.toLocaleString();
    this.lastTxTotalTokensElement.textContent = (p + c).toLocaleString();
  }
  
  private updateStatsDisplay(): void {
    const modelId = this.modelSelector.value;
    const modelName = this.modelSelector.options[this.modelSelector.selectedIndex]?.text || "N/A";
    
    const stats = this.usageStats[modelId] || { promptTokens: 0, completionTokens: 0 };

    if (this.statsModelNameElement) {
        this.statsModelNameElement.textContent = modelName;
    }
    this.totalPromptTokensElement.textContent =
      stats.promptTokens.toLocaleString();
    this.totalCompletionTokensElement.textContent =
      stats.completionTokens.toLocaleString();
    this.totalTotalTokensElement.textContent = (
      stats.promptTokens + stats.completionTokens
    ).toLocaleString();
  }

  private saveUsageStats(): void {
    localStorage.setItem(USAGE_STATS_BY_MODEL_KEY, JSON.stringify(this.usageStats));
  }

  private loadUsageStats(): void {
    const storedStats = localStorage.getItem(USAGE_STATS_BY_MODEL_KEY);
    this.usageStats = storedStats ? JSON.parse(storedStats) : {};
  }

  private resetModelUsage(): void {
    const modelId = this.modelSelector.value;
    const modelName = this.modelSelector.options[this.modelSelector.selectedIndex]?.text;
    
    if (!modelId || !modelName) {
        alert("No model selected to reset stats for.");
        return;
    }

    if (confirm(`Are you sure you want to reset the token usage stats for ${modelName}?`)) {
      this.usageStats[modelId] = { promptTokens: 0, completionTokens: 0 };
      this.saveUsageStats();
      this.updateStatsDisplay();
    }
  }

  // --- Hotkey Methods ---
  private loadHotkeySettings(): void {
    const storedSettings = localStorage.getItem(HOTKEY_SETTINGS_KEY);
    const defaultSettings: HotkeySettings = {
      enabled: false,
      target: 'note',
      mode: 'typing', // Default to typing mode for auto-paste
      hotkey: 'Alt+S' // Default hotkey
    };
    this.hotkeySettings = storedSettings ? JSON.parse(storedSettings) : defaultSettings;
  }

  private saveHotkeySettings(): void {
    const enabled = (document.getElementById('hotkeyEnabled') as HTMLInputElement).checked;
    const target = (document.getElementById('hotkeyTarget') as HTMLSelectElement).value as 'raw' | 'note' | 'x2';
    const mode = (document.getElementById('hotkeyMode') as HTMLSelectElement).value as 'clipboard' | 'typing';
    const hotkey = this.hotkeyInput.value;
    this.hotkeySettings = { enabled, target, mode, hotkey };
    localStorage.setItem(HOTKEY_SETTINGS_KEY, JSON.stringify(this.hotkeySettings));
  }


  
  private startListeningForHotkey(): void {
      this.isListeningForHotkey = true;
      this.recordedHotkey = null;
      this.hotkeyInput.value = 'Press a key combination...';
      this.hotkeyInput.classList.add('is-listening');
  }

  private stopListeningForHotkey(): void {
    if (!this.isListeningForHotkey) return;
    this.isListeningForHotkey = false;
    this.hotkeyInput.classList.remove('is-listening');
    // If listening stops and no valid hotkey was recorded, revert to saved value.
    if (!this.recordedHotkey || !this.recordedHotkey.key) {
        this.hotkeyInput.value = this.hotkeySettings.hotkey;
    }
    this.recordedHotkey = null;
  }
  
  private formatHotkey(modifiers: string[], key: string): string {
    const keyOrder = ['Control', 'Alt', 'Shift'];
    const sortedModifiers = modifiers.sort((a, b) => {
        const aIndex = keyOrder.indexOf(a);
        const bIndex = keyOrder.indexOf(b);
        if (aIndex === -1) return 1;
        if (bIndex === -1) return -1;
        return aIndex - bIndex;
    });

    // On Windows, use Control directly.
    return [...new Set(sortedModifiers), key].join('+');
  }

  private handleHotkeyKeyDown(event: KeyboardEvent): void {
      if (!this.isListeningForHotkey) return;
      event.preventDefault();
      event.stopPropagation();

      const key = event.key.trim();
      const isModifier = ['Control', 'Alt', 'Shift'].includes(key);

      const modifiers: string[] = [];
      if (event.ctrlKey) modifiers.push('Control');
      if (event.altKey) modifiers.push('Alt');
      if (event.shiftKey) modifiers.push('Shift');

      // If the key pressed is a modifier, just update the display and wait for the actual key.
      if (isModifier) {
          this.hotkeyInput.value = modifiers.join('+') + '+...';
          return;
      }
      
      // A non-modifier key has been pressed, this completes the hotkey.
      let keyCode = event.code;
      if (keyCode.startsWith('Key')) keyCode = keyCode.substring(3);
      if (keyCode.startsWith('Digit')) keyCode = keyCode.substring(5);

      this.recordedHotkey = { modifiers, key: keyCode };
      this.hotkeyInput.value = this.formatHotkey(modifiers, keyCode);
      
      // Finalize and stop listening.
      this.stopListeningForHotkey();
  }



  // --- Translation Methods ---
  private loadTranslationSettings(): void {
      const storedSettings = localStorage.getItem(TRANSLATION_SETTINGS_KEY);
      const defaultSettings: TranslationSettings = {
          targetLanguage: 'English',
          providerId: undefined,
      };
      this.translationSettings = storedSettings ? JSON.parse(storedSettings) : defaultSettings;
  }

  // --- Custom languages persistence helpers ---
  private loadCustomLanguages(): void {
    try {
      const raw = localStorage.getItem(CUSTOM_LANGUAGES_KEY);
      const arr = raw ? JSON.parse(raw) as string[] : [];
      this.customLanguagesSaved = new Set(arr.map(s => (s || '').trim().toLowerCase()).filter(Boolean));
    } catch {
      this.customLanguagesSaved = new Set();
    }
  }

  private saveCustomLanguages(): void {
    try {
      const arr = Array.from(this.customLanguagesSaved).map(k => ALL_LANGUAGES.find(l => l.toLowerCase() === k) || k);
      localStorage.setItem(CUSTOM_LANGUAGES_KEY, JSON.stringify(arr));
    } catch {}
  }

  private ensureCustomLanguagesInDropdown(): void {
    if (!this.targetLanguageSelector) return;
    const existing = new Set(Array.from(this.targetLanguageSelector.options).map(o => (o.value || '').toLowerCase()));
    const anchor = Array.from(this.targetLanguageSelector.options).find(o => o.value === 'custom') || null;
    for (const key of this.customLanguagesSaved) {
      if (!existing.has(key)) {
        const label = ALL_LANGUAGES.find(l => l.toLowerCase() === key) || key;
        const opt = document.createElement('option');
        opt.value = label;
        opt.textContent = label;
        if (anchor) this.targetLanguageSelector.insertBefore(opt, anchor);
        else this.targetLanguageSelector.appendChild(opt);
        existing.add(key);
      }
    }
    // No selection change here; selection is handled elsewhere.
  }

  private saveTranslationSettings(): void {
      if (this.targetLanguageSelector) {
        const sel = this.targetLanguageSelector.value;
        if (sel === 'custom') {
          const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
          const v = (input?.value || '').trim();
          this.translationSettings.targetLanguage = v || '';
        } else {
          this.translationSettings.targetLanguage = sel;
        }
      }
      if (this.translationProviderSelector) {
        const v = (this.translationProviderSelector.value || '').trim();
        // Only update providerId when non-empty; preserve prior saved selection otherwise
        if (v) {
          this.translationSettings.providerId = v;
        }
      }
      localStorage.setItem(TRANSLATION_SETTINGS_KEY, JSON.stringify(this.translationSettings));
  }
  // Show/hide custom language modal
  private showCustomLanguageModal(prefill?: string): void {
    if (!this.customLanguageModal || !this.customLanguageModalOverlay) return;
    // Build two-column card grid of remaining languages
    this.customLanguageSelected.clear();
    const grid = this.customLanguageGrid || (document.getElementById('customLanguageGrid') as HTMLDivElement | null);
    if (grid && this.targetLanguageSelector) {
      // Universe is "rest of languages": exclude built-ins only
      const remaining = ALL_LANGUAGES
        .filter(l => !BASE_LANG_SET.has(l.trim().toLowerCase()))
        .sort((a,b) => a.localeCompare(b));
      grid.innerHTML = '';
      for (const lang of remaining) {
        const card = document.createElement('div');
        card.className = 'language-card';
        card.dataset.value = lang;
        card.innerHTML = `<span class="tick"><i class="fas fa-check"></i></span><span class="label">${lang}</span>`;
        card.addEventListener('click', () => {
          const key = lang.toLowerCase();
          if (this.customLanguageSelected.has(key)) {
            this.customLanguageSelected.delete(key);
            card.classList.remove('selected');
          } else {
            this.customLanguageSelected.add(key);
            card.classList.add('selected');
          }
        });
        grid.appendChild(card);
      }
      // Preselect saved custom languages and optional prefill
      this.loadCustomLanguages();
      for (const child of Array.from(grid.children) as HTMLDivElement[]) {
        const key = (child.dataset.value || '').toLowerCase();
        if (this.customLanguagesSaved.has(key)) {
          child.classList.add('selected');
          this.customLanguageSelected.add(key);
        }
      }
      const want = (prefill || this.translationSettings?.targetLanguage || '').trim().toLowerCase();
      if (want) {
        const match = Array.from(grid.children).find((el:any) => (el.dataset?.value || '').toLowerCase() === want) as HTMLDivElement | undefined;
        if (match) { match.classList.add('selected'); this.customLanguageSelected.add(want); }
      }
    }
    this.customLanguageModal.classList.add('visible');
    this.customLanguageModalOverlay.classList.add('visible');
    document.body.classList.add('modal-open');
  }
  private hideCustomLanguageModal(): void {
    if (!this.customLanguageModal || !this.customLanguageModalOverlay) return;
    this.customLanguageModal.classList.remove('visible');
    this.customLanguageModalOverlay.classList.remove('visible');
    if (!this.promptModal.classList.contains('visible') && !this.translationResultModal.classList.contains('visible')) {
      document.body.classList.remove('modal-open');
    }
  }
  private applyCustomLanguage(): void {
    const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
    const typed = (input?.value || '').trim();
    const picks = new Set<string>(this.customLanguageSelected);
    if (typed) picks.add(typed.toLowerCase());

    if ((!picks || picks.size === 0)) { this.hideCustomLanguageModal(); return; }

    if (this.targetLanguageSelector) {
      // Determine adds and removals relative to saved set
      const saved = new Set(this.customLanguagesSaved);
      const toAdd = Array.from(picks).filter(k => !saved.has(k));
      const toRemove = Array.from(saved).filter(k => !picks.has(k));

      const existingValues = new Set<string>(Array.from(this.targetLanguageSelector.options).map(o => (o.value || '').toLowerCase()));
      const addBefore = Array.from(this.targetLanguageSelector.options).find(o => o.value === 'custom') || null;

      // Add new ones
      for (const key of toAdd) {
        const proper = ALL_LANGUAGES.find(l => l.toLowerCase() === key) || key;
        if (!existingValues.has(key)) {
          const opt = document.createElement('option');
          opt.value = proper as string;
          opt.textContent = proper as string;
          if (addBefore) this.targetLanguageSelector.insertBefore(opt, addBefore);
          else this.targetLanguageSelector.appendChild(opt);
          existingValues.add(key);
        }
        this.customLanguagesSaved.add(key);
      }

      // Remove deselected ones
      for (const key of toRemove) {
        const proper = ALL_LANGUAGES.find(l => l.toLowerCase() === key) || key;
        const opt = Array.from(this.targetLanguageSelector.options).find(o => (o.value || '').toLowerCase() === String(proper).toLowerCase());
        if (opt) opt.remove();
        this.customLanguagesSaved.delete(key);
      }

      // Update selection: pick last selected if any, else keep current if still present, else fallback to English
      const last = Array.from(picks).pop();
      const current = (this.targetLanguageSelector.value || '').toLowerCase();
      let nextValue: string | null = null;
      if (last) nextValue = ALL_LANGUAGES.find(l => l.toLowerCase() === last) || last;
      else if (Array.from(this.targetLanguageSelector.options).some(o => (o.value || '').toLowerCase() === current)) nextValue = this.targetLanguageSelector.value;
      else nextValue = 'English';

      this.targetLanguageSelector.value = nextValue as string;
      this.targetLanguageSelector.dispatchEvent(new Event('change'));
      this.translationSettings.targetLanguage = nextValue as string;
      this.saveTranslationSettings();

      // Persist the new saved set
      this.saveCustomLanguages();
    }
    this.hideCustomLanguageModal();
  }

  private updateTranslateButtonState(): void {
  const selection = window.getSelection();
  const selectedNow = selection && !selection.isCollapsed ? selection.toString() : '';
  const trimmed = (selectedNow || '').trim();
  // Cache last non-empty selection so we can translate even if click collapses it
  if (trimmed) this.lastSelectionText = trimmed;
  const isModelSelected = !!this.modelSelector.value;
  const hasLocalWhisper = Object.values(this.localModelsState).some((s: any) => s?.status === 'downloaded');
  const hasLocalLlm = Object.values(this.ollamaModelsState).some((s: any) => s?.status === 'downloaded');
  if (this.translateButton) {
    // Enable when any provider is available: API/Cloud model selected, a local LLM is installed, or a local Whisper is installed
    const enable = isModelSelected || hasLocalLlm || hasLocalWhisper;
    this.translateButton.disabled = !enable;
    this.translateButton.title = enable
      ? 'Translate selection or clipboard text'
      : 'Add a provider (API, Local LLM, or Local Whisper) in Settings to enable translation.';
  }
  }

  private async handleTranslation(): Promise<void> {
  // Try current selection first, then fall back to cached selection; if empty, attempt clipboard read on click
  const current = (window.getSelection()?.toString() || '').trim();
  let selectedText = current || this.lastSelectionText.trim();
  if (!selectedText) {
    try {
      const clip = await navigator.clipboard.readText();
      if (clip && clip.trim()) {
        this.clipboardText = clip.trim();
        selectedText = this.clipboardText;
        // Update button tooltip state post-read
        this.updateTranslateButtonState();
      }
    } catch {}
  }
  if (!selectedText) {
    // Open the modal with guidance even when no text is available, matching the previous UX expectation
    this.openTranslationModal('—', '<em>No text to translate. Copy some text to clipboard or select text in a note and try again.</em>');
    return;
  }
  // Show modal first so user can verify/change target language
  this.openTranslationModal(selectedText, '<em>Translating...</em>');
  // Read the latest selection from the dropdown (fallback to saved settings)
  const targetLanguage = (() => {
    const sel = this.targetLanguageSelector?.value;
    if (sel === 'custom') {
      const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
      return (input?.value || this.translationSettings.targetLanguage);
    }
    return sel || this.translationSettings.targetLanguage;
  })();

      try {
          await this.performTranslation(selectedText, targetLanguage);

      } catch (error) {
          logger.error('Error during translation:', error);
          const message = error instanceof Error ? error.message : String(error);
          if (this.translatedTextElement) {
              this.translatedTextElement.innerHTML = `<em>Error: ${message}</em>`;
          }
          if (error instanceof ApiError && error.isQuotaError) {
            this.showErrorDialog('API Quota Exceeded', 'You have exceeded your current API quota. Please check your plan, or switch providers in Settings.');
          } else {
            this.showErrorDialog('Translation Error', message);
          }
      }
  }

  // Re-run translation from the modal using possibly edited original text
  private async retranslateFromModal(): Promise<void> {
    const text = (this.originalTextElement?.innerText || '').trim();
    if (!text) return;
    const target = (() => {
      const sel = this.targetLanguageSelector?.value;
      if (sel === 'custom') {
        const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
        return (input?.value || this.translationSettings.targetLanguage);
      }
      return sel || this.translationSettings.targetLanguage;
    })();
    // Show pending state in-place
    if (this.translatedTextElement) {
      this.translatedTextElement.innerHTML = '<em>Translating...</em>';
    }
    try {
      await this.performTranslation(text, target);
    } catch (e) {
      // performTranslation handles UI + errors
    }
  }

  // Toggle modal recording using the same 16kHz AudioWorklet WAV pipeline as main UI
  private async toggleModalRecording(): Promise<void> {
    try {
      if (this.isRecording) {
        // Prevent conflicts with main UI recorder
        this.showErrorDialog('Recording In Progress', 'Please stop the main recording before using the modal recorder.');
        return;
      }
      if (!this.modalIsRecording) {
        await this.startModalRecording();
      } else {
        await this.stopModalRecording();
      }
    } catch (err) {
      logger.error('Modal toggle recording error:', err);
    }
  }

  private async startModalRecording(): Promise<void> {
    try {
      // Cleanup any previous modal stream/context
      if (this.modalStream) {
        try { this.modalStream.getTracks().forEach(t => t.stop()); } catch {}
        this.modalStream = null;
      }
      if (this.modalAudioContext) {
        try { if (this.modalAudioContext.state !== 'closed') await this.modalAudioContext.close(); } catch {}
        this.modalAudioContext = null;
      }

      // Request mic
      try {
        this.modalStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch {
        this.modalStream = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
        } as any);
      }

      // AudioContext @ 16kHz
      const AudioContextCtor = window.AudioContext || (window as any).webkitAudioContext;
      this.modalAudioContext = new AudioContextCtor({ sampleRate: 16000 });
      if (this.modalAudioContext.state === 'suspended') await this.modalAudioContext.resume();
      this.modalRecordingSampleRate = this.modalAudioContext.sampleRate || 16000;

      // Load the same worklet
  // Use absolute URL for cross-platform packaging (file:// in Electron)
  await this.modalAudioContext.audioWorklet.addModule(new URL('audio-recorder-worklet.js', window.location.href).toString());
      const source = this.modalAudioContext.createMediaStreamSource(this.modalStream);
      this.modalWorkletNode = new AudioWorkletNode(this.modalAudioContext, 'audio-recorder-processor');
      this.modalWorkletNode.port.onmessage = (event: MessageEvent) => {
        if (event.data?.command === 'audioData') {
          this.modalAudioBuffer = event.data.data as Float32Array;
          this.modalRecordingSampleRate = this.modalAudioContext?.sampleRate || 16000;
        }
      };
      source.connect(this.modalWorkletNode);
      this.modalWorkletNode.port.postMessage({ command: 'start' });

      this.modalIsRecording = true;
      this.modalRecordButton?.classList.add('recording');
    } catch (err: any) {
      logger.error('Failed to start modal recording:', err);
      this.modalIsRecording = false;
      this.modalRecordButton?.classList.remove('recording');
      throw err;
    }
  }

  private async stopModalRecording(): Promise<void> {
    if (!this.modalIsRecording) return;
    try {
      let wavBlob: Blob | null = null;
      if (this.modalWorkletNode) {
        const audioPromise = new Promise<Blob | null>((resolve) => {
          const timeout = setTimeout(() => resolve(null), 5000);
          const handler = (event: MessageEvent) => {
            if (event.data?.command === 'audioData') {
              clearTimeout(timeout);
              this.modalWorkletNode!.port.removeEventListener('message', handler as any);
              const buf = event.data.data as Float32Array;
              if (buf?.length) resolve(this.createWAVBlob(buf, this.modalRecordingSampleRate));
              else resolve(null);
            }
          };
          this.modalWorkletNode!.port.addEventListener('message', handler as any);
        });
        this.modalWorkletNode.port.postMessage({ command: 'stop' });
        wavBlob = await audioPromise;

        // Cleanup nodes and stream
        try { this.modalWorkletNode.disconnect(); } catch {}
        this.modalWorkletNode = null;
      }
      if (this.modalStream) {
        try { this.modalStream.getTracks().forEach(t => t.stop()); } catch {}
        this.modalStream = null;
      }
      if (this.modalAudioContext) {
        try { if (this.modalAudioContext.state !== 'closed') await this.modalAudioContext.close(); } catch {}
        this.modalAudioContext = null;
      }

      this.modalIsRecording = false;
      this.modalRecordButton?.classList.remove('recording');

      if (!wavBlob || wavBlob.size === 0) {
        if (this.translatedTextElement) this.translatedTextElement.innerHTML = '<em>No audio captured.</em>';
        return;
      }

      // Transcribe using the selected transcription provider (same as main UI)
      const selectedValue = this.transcriptionProviderSelector?.value || '';
      let provider: TranscriptionProvider = 'local';
      let localModelId: string | null = null;
      if (selectedValue.startsWith('local:')) {
        provider = 'local';
        localModelId = selectedValue.substring(6);
      } else if (selectedValue === 'openai') provider = 'openai';
      else if (selectedValue === 'google') provider = 'google';

      // If using Local Whisper in the modal, force translate=true and aim for Target Language where possible
      if (provider === 'local' && localModelId) {
        const w = window as any;
        const modelMeta = getLocalModelMeta(localModelId);
        const defaultLang = modelMeta?.language === 'English' ? 'en' : 'auto';
        const forcedLangOverall = this.resolveForcedLocalLanguage(defaultLang);
        const langPref = (() => {
          const sel = this.targetLanguageSelector?.value;
          if (sel === 'custom') {
            const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
            return (input?.value || this.translationSettings.targetLanguage || '').toLowerCase();
          }
          return (sel || this.translationSettings.targetLanguage || '').toLowerCase();
        })();
        const languageMap: Record<string,string> = {
          'english': 'en', 'en': 'en', 'русский': 'ru', 'russian': 'ru', 'ru': 'ru',
          'spanish': 'es', 'español': 'es', 'es': 'es', 'french': 'fr', 'français': 'fr', 'fr': 'fr',
          'german': 'de', 'deutsch': 'de', 'de': 'de', 'italian': 'it', 'italiano': 'it', 'it': 'it',
          'portuguese': 'pt', 'português': 'pt', 'pt': 'pt', 'hindi': 'hi', 'hi': 'hi', 'japanese': 'ja', '日本語': 'ja', 'ja': 'ja',
          'korean': 'ko', '한국어': 'ko', 'ko': 'ko', 'chinese': 'zh', '中文': 'zh', 'zh': 'zh'
        };
        const targetLang = languageMap[langPref] || 'en';
        const requestLanguage = forcedLangOverall === 'auto' ? targetLang : forcedLangOverall;
        const ab = await wavBlob.arrayBuffer();
        const res = await w?.ipcRenderer?.invoke('whisper:transcribeWavBytes', {
          wavBytes: new Uint8Array(ab),
          modelId: localModelId,
          options: { language: requestLanguage, translate: true, threads: 0, forceCpu: false }
        });
        const text = (res?.text || '').trim();
        if (!text) {
          if (this.translatedTextElement) this.translatedTextElement.innerHTML = '<em>Transcription returned empty.</em>';
          return;
        }
        if (this.originalTextElement) this.originalTextElement.textContent = text;
        if (this.translatedTextElement) this.translatedTextElement.innerHTML = '<em>Translating...</em>';
        const target = (() => {
          const sel = this.targetLanguageSelector?.value;
          if (sel === 'custom') {
            const input = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
            return (input?.value || this.translationSettings.targetLanguage);
          }
          return sel || this.translationSettings.targetLanguage;
        })();
        await this.performTranslation(text, target);
        return;
      }

      let forcedLangForCall: string | undefined;
      if (provider === 'local' && localModelId) {
        const meta = getLocalModelMeta(localModelId);
        const defaultLang = meta?.language === 'English' ? 'en' : 'auto';
        forcedLangForCall = this.resolveForcedLocalLanguage(defaultLang);
      }
      const tx = await this.apiClient.transcribeAudio(wavBlob, provider, localModelId, forcedLangForCall);
      const text = (tx?.text || '').trim();
      if (!text) {
        if (this.translatedTextElement) this.translatedTextElement.innerHTML = '<em>Transcription returned empty.</em>';
        return;
      }
      if (this.originalTextElement) this.originalTextElement.textContent = text;
      if (this.translatedTextElement) this.translatedTextElement.innerHTML = '<em>Translating...</em>';

      // Prefer Local LLM for translation if user hasn’t chosen a provider yet
      if (this.translationProviderSelector && !this.translationProviderSelector.value) {
        const localLlm = Object.entries(this.ollamaModelsState).find(([_, s]) => (s as any)?.status === 'downloaded');
        if (localLlm) {
          this.translationProviderSelector.value = `ollama:${localLlm[0]}`;
          this.translationProviderSelector.dispatchEvent(new Event('change'));
        }
      }

      const target = (this.targetLanguageSelector?.value || this.translationSettings.targetLanguage);
      await this.performTranslation(text, target);
    } catch (err: any) {
      logger.error('Failed to stop modal recording / process audio:', err);
      if (this.translatedTextElement) this.translatedTextElement.innerHTML = `<em>${(err?.message || 'Recording failed')}</em>`;
    }
  }

  // Shared translation worker
  private async performTranslation(text: string, targetLanguage: string): Promise<void> {
    // Choose translation provider: modal selection wins, fallback to polishing model
    const selectedProviderId = (this.translationProviderSelector?.value || '').trim();
    const modelIdentifier = selectedProviderId || this.modelSelector.value;
    if (!modelIdentifier) throw new Error('No translation provider selected.');
    // Local speech models (Whisper/Parakeet) are audio-only; show hint in text translation modal
    if (modelIdentifier.startsWith('local:')) {
      if (this.translatedTextElement) {
        this.translatedTextElement.innerHTML = '<em>Local speech models translate audio only. Choose a Local LLM (Ollama) or an API provider for text translation.</em>';
      }
      // Persist choice so user sees it next time
      this.saveTranslationSettings();
      return;
    }
    const prompt = `TASK: Translate the provided text to ${targetLanguage}. You must output ONLY the translated text - nothing else.

RULES:
- Output ONLY the translation
- Do NOT include explanations, comments, or notes
- Do NOT acknowledge this instruction
- Do NOT use quotation marks around your output
- Do NOT add any formatting markers or symbols
- Preserve the original meaning and tone

TEXT TO TRANSLATE:
${text}`;
    const result = await this.apiClient.generateText(modelIdentifier, prompt);
    if (this.translatedTextElement) {
      this.translatedTextElement.innerHTML = result.text || '<em>Translation failed or returned empty.</em>';
    }
    if (modelIdentifier) {
      if (!this.usageStats[modelIdentifier]) {
        this.usageStats[modelIdentifier] = { promptTokens: 0, completionTokens: 0 };
      }
      this.usageStats[modelIdentifier].promptTokens += result.promptTokens;
      this.usageStats[modelIdentifier].completionTokens += result.completionTokens;
    }
    this.updateLastTransactionDisplay(result.promptTokens, result.completionTokens);
    this.updateStatsDisplay();
    this.saveUsageStats();
    this.saveTranslationSettings();
  }

  // Ensure a Provider selector exists in the Translation modal and wire it up
  private ensureTranslationProviderSelector(): void {
    if (!this.translationResultModal) return;
    const existing = this.translationResultModal.querySelector('#translationProviderSelector') as HTMLSelectElement | null;
    if (existing) {
      this.translationProviderSelector = existing;
      return;
    }
    const body = this.translationResultModal.querySelector('.prompt-modal-body');
    if (!body) return;
    const providerGroup = document.createElement('div');
    providerGroup.className = 'form-group';
    providerGroup.style.marginBottom = '12px';
    const label = document.createElement('label');
    label.setAttribute('for', 'translationProviderSelector');
    label.textContent = 'Provider';
    const select = document.createElement('select');
    select.id = 'translationProviderSelector';
    select.className = 'model-selector';
    select.style.width = '100%';
    providerGroup.appendChild(label);
    providerGroup.appendChild(select);

    // Insert above target language selector if present
    const targetSel = this.translationResultModal.querySelector('#targetLanguageSelector');
    const targetGroup = targetSel ? (targetSel.closest('.form-group') as HTMLElement | null) : null;
    if (targetGroup && targetGroup.parentElement) {
      targetGroup.parentElement.insertBefore(providerGroup, targetGroup);
    } else {
      body.prepend(providerGroup);
    }

        this.translationProviderSelector = select;
    new CustomSelect(this.translationProviderSelector);
    this.translationProviderSelector.addEventListener('change', () => this.saveTranslationSettings());
        // Handle Custom language via modal
        const sel = this.targetLanguageSelector;
        if (sel) {
          sel.addEventListener('change', () => {
            if (sel.value === 'custom') {
              const saved = (this.translationSettings.targetLanguage || '').trim();
              this.showCustomLanguageModal(saved);
            }
            this.saveTranslationSettings();
          });
        }
  }

  // Fill provider options from API models, Ollama, and Local Whisper
  private populateTranslationProviderOptions(): void {
    if (!this.translationProviderSelector) return;
    const sel = this.translationProviderSelector;
    sel.innerHTML = '';

    const addGroup = (groupLabel: string, opts: Array<{ value: string; text: string }>) => {
      if (!opts.length) return;
      const group = document.createElement('optgroup');
      group.label = groupLabel;
      for (const o of opts) {
        const opt = document.createElement('option');
        opt.value = o.value;
        opt.textContent = o.text;
        group.appendChild(opt);
      }
      sel.appendChild(group);
    };

    // API and Cloud models come from the main model selector (excluding ollama which we separate)
    const apiOptions: Array<{ value: string; text: string }> = [];
    const ollamaOptions: Array<{ value: string; text: string }> = [];
    Array.from(this.modelSelector.options).forEach((opt) => {
      const val = opt.value || '';
      if (!val) return;
      if (val.startsWith('ollama:')) {
        ollamaOptions.push({ value: val, text: opt.textContent || val });
      } else {
        apiOptions.push({ value: val, text: opt.textContent || val });
      }
    });

    // Local Whisper models (exclude English-only models from Translation modal per request)
    const localSpeechOptions: Array<{ value: string; text: string }> = [];
    Object.entries(this.localModelsState).forEach(([id, state]) => {
      if ((state as any)?.status === 'downloaded') {
        const meta = AVAILABLE_LOCAL_MODELS.find(m => m.id === id);
        if (!meta) return;
        if (meta.language !== 'English') {
          const friendly = meta.name || id;
          localSpeechOptions.push({ value: `local:${id}`, text: `Local model - ${friendly}` });
        }
      }
    });

    addGroup('API Providers & Cloud Models', apiOptions);
    addGroup('Local LLMs (Ollama)', ollamaOptions);
    addGroup('Local Speech Models (audio only)', localSpeechOptions);

    // Trigger CustomSelect sync
    sel.dispatchEvent(new Event('change'));
  }

  // Clipboard watcher to mirror previous behavior: enable translate when text is copied
  private startClipboardWatcher(): void {
    // Use periodic polling; Electron clipboard API would be better but may not be available in this context
    let last = '';
    const poll = async () => {
      try {
        const text = await navigator.clipboard.readText();
        if (typeof text === 'string') {
          const t = text.trim();
          if (t && t !== last) {
            last = t;
            this.clipboardText = t;
            this.updateTranslateButtonState();
          }
        }
      } catch {
        // Ignore clipboard read failures (permissions, etc.)
      } finally {
        window.setTimeout(poll, 1200); // gentle polling
      }
    };
    poll();
  }

  private openTranslationModal(originalText: string, translatedText: string): void {
      if (!this.translationResultModal || !this.translationResultOverlay || !this.originalTextElement || !this.translatedTextElement) return;
  this.originalTextElement.textContent = originalText; // stays editable
      this.translatedTextElement.innerHTML = translatedText;
      this.translationTargetLanguageElement.textContent = this.translationSettings.targetLanguage;
      // Ensure provider selector exists and populate
      this.ensureTranslationProviderSelector();
      this.populateTranslationProviderOptions();
      // Default provider: saved provider, else auto-select available provider
      // Priority: saved provider > Ollama models > Whisper models > configured API models
      let defaultProvider = this.translationSettings.providerId || '';
      // If a saved provider exists but isn't configured in Settings, ignore it
      if (defaultProvider) {
        const isConfigured = (() => {
          if (defaultProvider.startsWith('google:')) return !!this.apiSettings.google.apiKey;
          if (defaultProvider.startsWith('openai:')) return !!this.apiSettings.openai.apiKey;
          if (defaultProvider.startsWith('anthropic:')) return !!this.apiSettings.anthropic.apiKey;
          if (defaultProvider.startsWith('custom:')) return !!(this.apiSettings.custom.apiKey && this.apiSettings.custom.baseUrl);
          // Local providers are validated later against available options
          return true;
        })();
        if (!isConfigured) defaultProvider = '';
      }
      if (this.translationProviderSelector && (!defaultProvider || !Array.from(this.translationProviderSelector.options).some(o => o.value === defaultProvider))) {
        // Auto-select fallback provider
        const options = Array.from(this.translationProviderSelector.options);
        
        // Check for available Ollama models
        const ollamaOption = options.find(o => o.value.startsWith('ollama:'));
        if (ollamaOption) {
          defaultProvider = ollamaOption.value;
        } else {
          // Check for available local speech models
          const localOption = options.find(o => o.value.startsWith('local:'));
          if (localOption) {
            defaultProvider = localOption.value;
          } else {
            // Check for configured API providers only
            const configuredApiOptions = options.filter(o => {
              const val = o.value;
              if (val.startsWith('local:') || val.startsWith('ollama:')) return false;
              
              // Check if this API provider is configured
              if (val.startsWith('google:')) {
                // Only treat Google as configured if set in app settings, not via environment
                return !!this.apiSettings.google.apiKey;
              } else if (val.startsWith('openai:')) {
                return !!this.apiSettings.openai.apiKey;
              } else if (val.startsWith('anthropic:')) {
                return !!this.apiSettings.anthropic.apiKey;
              } else if (val.startsWith('custom:')) {
                return !!(this.apiSettings.custom.apiKey && this.apiSettings.custom.baseUrl);
              }
              return false;
            });
            
            // Fall back to first configured API option
            if (configuredApiOptions.length > 0) {
              defaultProvider = configuredApiOptions[0].value;
            } else {
              // No configured providers available - leave empty
              defaultProvider = '';
            }
          }
        }
      }
      
      if (this.translationProviderSelector) {
        this.translationProviderSelector.value = defaultProvider;
        // Persist immediately so it's remembered across sessions even if no user change occurs
        this.saveTranslationSettings();
        // Sync any custom select UI
        this.translationProviderSelector.dispatchEvent(new Event('input'));
        this.translationProviderSelector.dispatchEvent(new Event('change'));
      }
      if (this.targetLanguageSelector) {
        // If saved value isn't among options, switch to custom and prefill input
        const options = Array.from(this.targetLanguageSelector.options).map(o => o.value);
        const saved = (this.translationSettings.targetLanguage || '').trim();
        const hasOption = saved && options.includes(saved);
        const customInput = document.getElementById('customTargetLanguage') as HTMLInputElement | null;
        if (saved && !hasOption) {
          this.targetLanguageSelector.value = 'custom';
          if (customInput) { customInput.style.display = 'block'; customInput.value = saved; }
        } else {
          this.targetLanguageSelector.value = saved || 'English';
          if (customInput) { customInput.style.display = 'none'; customInput.value = ''; }
        }
        this.targetLanguageSelector.dispatchEvent(new Event('change'));
      }
      this.translationResultModal.classList.add('visible');
      this.translationResultOverlay.classList.add('visible');
      document.body.classList.add('modal-open');
  }

  private closeTranslationModal(): void {
  if (!this.translationResultModal || !this.translationResultOverlay) return;
  // Persist current translation provider and target language when closing the modal
  try { this.saveTranslationSettings(); } catch {}
      this.translationResultModal.classList.remove('visible');
      this.translationResultOverlay.classList.remove('visible');
  const customLangVisible = (this.customLanguageModal && this.customLanguageModal.classList.contains('visible'));
  if (!this.promptModal.classList.contains('visible') && !this.translationResultModal.classList.contains('visible') && !customLangVisible) {
          document.body.classList.remove('modal-open');
      }
  }

  private showConfirmationDialog(message: string, onConfirm: () => void): void {
      if (!this.confirmationModal || !this.confirmationModalOverlay || !this.confirmationMessage) return;
      
      this.confirmationMessage.textContent = message;
      this.confirmationModal.classList.add('visible');
      this.confirmationModalOverlay.classList.add('visible');
      document.body.classList.add('modal-open');
      
      // Store the confirmation callback
      (this as any).pendingConfirmation = onConfirm;
  }

  private closeConfirmationModal(): void {
      if (!this.confirmationModal || !this.confirmationModalOverlay) return;
      this.confirmationModal.classList.remove('visible');
      this.confirmationModalOverlay.classList.remove('visible');
      if (!this.promptModal.classList.contains('visible') && !this.translationResultModal.classList.contains('visible') && !this.errorModal.classList.contains('visible') && !this.setupWizardOverlay.style.display.includes('flex')) {
          document.body.classList.remove('modal-open');
      }
      // Clear the pending confirmation
      (this as any).pendingConfirmation = null;
  }

  private showErrorDialog(title: string, message: string): void {
      if (!this.errorModal || !this.errorModalOverlay || !this.errorModalTitle || !this.errorModalMessage) return;
      
      this.errorModalTitle.textContent = title;
      this.errorModalMessage.textContent = message;
      this.errorModal.classList.add('visible');
      this.errorModalOverlay.classList.add('visible');
      document.body.classList.add('modal-open');
  }

  private closeErrorDialog(): void {
      if (!this.errorModal || !this.errorModalOverlay) return;
      this.errorModal.classList.remove('visible');
      this.errorModalOverlay.classList.remove('visible');
  const customLangVisible = (this.customLanguageModal && this.customLanguageModal.classList.contains('visible'));
  if (!this.promptModal.classList.contains('visible') && !this.translationResultModal.classList.contains('visible') && !this.confirmationModal.classList.contains('visible') && !this.setupWizardOverlay.style.display.includes('flex') && !customLangVisible) {
          document.body.classList.remove('modal-open');
      }
  }

  private handleConfirmDelete(): void {
      const pendingConfirmation = (this as any).pendingConfirmation;
      if (pendingConfirmation) {
          pendingConfirmation();
      }
      this.closeConfirmationModal();
  }

  private async copyTranslatedText(): Promise<void> {
      if (!this.translatedTextElement || !this.copyTranslationButton) return;
      const textToCopy = this.translatedTextElement.innerText;
      if (!textToCopy || this.translatedTextElement.querySelector('em')) return;

      try {
          await navigator.clipboard.writeText(textToCopy);
          const originalHTML = this.copyTranslationButton.innerHTML;
          this.copyTranslationButton.innerHTML = `<i class="fas fa-check" style="margin-right: 8px;"></i>Copied!`;
          this.copyTranslationButton.disabled = true;
          setTimeout(() => {
              this.copyTranslationButton.innerHTML = originalHTML;
              this.copyTranslationButton.disabled = false;
          }, 2000);
      } catch (err) {
          logger.error('Failed to copy translated text: ', err);
      }
  }

  private openApiKeyUrl(provider: string): void {
    const urls = {
      google: 'https://aistudio.google.com/app/apikey',
      openai: 'https://platform.openai.com/api-keys',
      anthropic: 'https://console.anthropic.com/settings/keys'
    };

    const url = urls[provider as keyof typeof urls];
    if (url && window.require) {
      const { shell } = window.require('electron');
      shell.openExternal(url);
    } else if (url) {
      window.open(url, '_blank');
    }
  }

  private simulateCtrlV(): void {
    // Use IPC to send Ctrl+V simulation to main process
    if (ipcRenderer) {
      ipcRenderer.send('simulate-ctrl-v');
    }
  }

  // --- Ollama Methods ---
  private getOllamaServerUrl(): string {
    // Prefer persisted value; fallback to input; then default
    let customUrl = '';
    try { customUrl = localStorage.getItem(this.OLLAMA_SERVER_URL_KEY) || ''; } catch {}
    if (!customUrl) customUrl = this.ollamaServerUrlInput?.value?.trim() || '';
    return this.normalizeOllamaUrl(customUrl || 'http://localhost:11434');
  }

  private normalizeOllamaUrl(url: string): string {
    try {
      let u = (url || '').trim();
      if (!u) return 'http://localhost:11434';
      if (!/^https?:\/\//i.test(u)) u = 'http://' + u;
      u = u.replace(/\/+$/g, '');
      return u;
    } catch {
      return 'http://localhost:11434';
    }
  }

  private saveOllamaModelsState(): void {
    try {
      localStorage.setItem(this.OLLAMA_MODELS_STATE_KEY, JSON.stringify(this.ollamaModelsState));
    } catch (error) {
      logger.error('Failed to save Ollama models state:', error);
    }
  }

  private loadOllamaModelsState(): void {
    try {
      const stored = localStorage.getItem(this.OLLAMA_MODELS_STATE_KEY);
      if (stored) {
        this.ollamaModelsState = JSON.parse(stored);
        
        // Clean up any old 'downloading' states on app restart
        Object.keys(this.ollamaModelsState).forEach(modelId => {
          // Drop any blocklisted models from persisted state
          if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) {
            delete this.ollamaModelsState[modelId];
            return;
          }
          if (this.ollamaModelsState[modelId]?.status === 'downloading') {
            // Reset downloading states to not_downloaded on app restart
            // We'll check actual status from server
            this.ollamaModelsState[modelId] = { status: 'not_downloaded' };
          }
        });
      }
    } catch (error) {
      logger.error('Failed to load Ollama models state:', error);
      this.ollamaModelsState = {};
    }
  }

  private saveSelectedOllamaModel(): void {
    try {
      if (this.selectedOllamaModelId) {
        localStorage.setItem('selected_ollama_model', this.selectedOllamaModelId);
      } else {
        localStorage.removeItem('selected_ollama_model');
      }
    } catch (error) {
      logger.error('Failed to save selected Ollama model:', error);
    }
  }

  private loadSelectedOllamaModel(): void {
    try {
      const saved = localStorage.getItem('selected_ollama_model');
      if (saved) {
        // Ignore blocklisted models if previously saved
        if (OLLAMA_MODEL_BLOCKLIST.has(saved)) {
          this.selectedOllamaModelId = null;
          localStorage.removeItem('selected_ollama_model');
        } else {
          this.selectedOllamaModelId = saved;
        }
      }
    } catch (error) {
      logger.error('Failed to load selected Ollama model:', error);
      this.selectedOllamaModelId = null;
    }
  }

  private async checkOllamaStatusSilently(): Promise<void> {
    // Silently check for Ollama models at startup without showing UI changes
    try {
      const serverUrl = this.getOllamaServerUrl();
      const response = await fetch(`${serverUrl}/api/version`, {
        method: 'GET',
        signal: AbortSignal.timeout(2000) // Shorter timeout for startup
      });

      if (response.ok) {
        // Ollama is running, load models but don't show install section
        await this.loadOllamaModels();
        // Update main model selector to include Ollama models
        this.updateModelSelector();
      }
    } catch (error) {
      // Silently fail - no need to log errors for background check
    }
  }

  private async checkOllamaStatus(): Promise<void> {
    logger.info('Checking Ollama status...');
    const serverUrl = this.getOllamaServerUrl();
    logger.info(`Checking Ollama at: ${serverUrl}`);
    
    try {
      // First check if Ollama is running
      const response = await fetch(`${serverUrl}/api/version`, {
        method: 'GET',
        signal: AbortSignal.timeout(3000) // 3 second timeout
      });

      if (response.ok) {
        // Ollama is running
        logger.info('Ollama is running, showing models section');
        this.updateOllamaButton('running', 'Running', 'fas fa-check-circle');
        this.showOllamaStatusMessage('Already installed');
        this.showOllamaModelsSection();
        this.loadOllamaModels();
        // Check for any models that were marked as downloading and verify their status
        await this.verifyDownloadingModels();
        return;
      }
    } catch (error) {
      logger.info('Ollama API not accessible, checking installation status');
    }

    // Ollama API not accessible, check if it's installed but not running
    if (ipcRenderer) {
      try {
        const installationResult = await ipcRenderer.invoke('check-ollama-installation');
        logger.info('Ollama installation check result:', installationResult);

        if (installationResult.installed) {
          // Ollama is installed but not running
          logger.info('Ollama is installed but not running');
          this.updateOllamaButton('run', 'Run', 'fas fa-play');
          this.showOllamaStatusMessage('Already installed');
          this.hideOllamaModelsSection();
        } else {
          // Ollama is not installed
          logger.info('Ollama is not installed');
          this.updateOllamaButton('install', 'Install', 'fas fa-download');
          this.hideOllamaStatusMessage();
          this.hideOllamaModelsSection();
        }
      } catch (error) {
        logger.error('Failed to check Ollama installation:', error);
        // Fallback to install state
        this.updateOllamaButton('install', 'Install', 'fas fa-download');
        this.hideOllamaStatusMessage();
        this.hideOllamaModelsSection();
      }
    } else {
      // No IPC available (web mode), assume not installed
      logger.info('No IPC available, defaulting to install state');
      this.updateOllamaButton('install', 'Install', 'fas fa-download');
      this.hideOllamaStatusMessage();
      this.hideOllamaModelsSection();
    }
  }

  private async verifyDownloadingModels(): Promise<void> {
    // Check if any models marked as downloading are actually completed
    let stateChanged = false;
    
    for (const modelId of Object.keys(this.ollamaModelsState)) {
      if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) continue;
      const state = this.ollamaModelsState[modelId];
      if (state?.status === 'downloading') {
        // Check if the model is actually downloaded now
        try {
          const serverUrl = this.getOllamaServerUrl();
          const response = await fetch(`${serverUrl}/api/tags`, {
            method: 'GET',
            signal: AbortSignal.timeout(3000)
          });
          
          if (response.ok) {
            const data = await response.json();
            const downloadedModels = data.models || [];
            const isDownloaded = downloadedModels.some((downloaded: any) => downloaded.name === modelId);
            
            if (isDownloaded) {
              this.ollamaModelsState[modelId] = { status: 'downloaded' };
              stateChanged = true;
              logger.info(`Model ${modelId} download completed`);
            }
          }
        } catch (error) {
          logger.error(`Failed to verify model ${modelId} status:`, error);
        }
      }
    }
    
    if (stateChanged) {
      this.saveOllamaModelsState();
      this.renderOllamaModelsList();
      this.updateModelSelector();
    }
  }

  private updateOllamaButton(state: 'install' | 'run' | 'running', text: string, icon: string): void {
    const buttonText = this.installOllamaButton.querySelector('.download-button-text') as HTMLSpanElement;
    const buttonIcon = this.installOllamaButton.querySelector('i') as HTMLElement;
    
    if (buttonText) buttonText.textContent = text;
    if (buttonIcon) buttonIcon.className = icon;
    
    // Remove all state classes
    this.installOllamaButton.classList.remove('running');
    this.installOllamaButton.disabled = false;
    
    // Add state-specific styling
    if (state === 'running') {
      this.installOllamaButton.classList.add('running');
      this.installOllamaButton.disabled = true;
    }
  }

  private showOllamaStatusMessage(message: string): void {
    this.ollamaStatusMessage.textContent = message;
    this.ollamaStatusMessage.style.display = 'block';
  }

  private hideOllamaStatusMessage(): void {
    this.ollamaStatusMessage.style.display = 'none';
  }

  private async handleOllamaInstallClick(): Promise<void> {
    const buttonText = this.installOllamaButton.querySelector('.download-button-text') as HTMLSpanElement;
    const currentText = buttonText?.textContent || '';

    if (currentText === 'Install') {
      // Open Ollama download page
      if (window.require) {
        const { shell } = window.require('electron');
        shell.openExternal('https://ollama.com/download');
      } else {
        window.open('https://ollama.com/download', '_blank');
      }
    } else if (currentText === 'Run') {
      // Try to start Ollama
      logger.info('Starting Ollama server...');
      
      if (ipcRenderer) {
        try {
          // Update button to show starting state
          this.updateOllamaButton('run', 'Starting...', 'fas fa-spinner fa-spin');
          
          const result = await ipcRenderer.invoke('start-ollama');
          logger.info('Ollama start result:', result);
          
          if (result.success) {
            // Wait a moment for Ollama to start, then check status
            setTimeout(() => {
              this.checkOllamaStatus();
            }, 2000);
          } else {
            logger.error('Failed to start Ollama:', result.error);
            // Reset button state
            this.updateOllamaButton('run', 'Run', 'fas fa-play');
            // Could show an error message to user here
          }
        } catch (error) {
          logger.error('Error starting Ollama:', error);
          // Reset button state
          this.updateOllamaButton('run', 'Run', 'fas fa-play');
        }
      } else {
        logger.warn('Cannot start Ollama: IPC not available');
      }
    }
  }

  private showOllamaModelsSection(): void {
    logger.info('Showing Ollama models section');
    this.ollamaModelsSection.style.display = 'block';
  }

  private hideOllamaModelsSection(): void {
    logger.info('Hiding Ollama models section');
    this.ollamaModelsSection.style.display = 'none';
  }

  private async loadOllamaModels(): Promise<void> {
    const serverUrl = this.getOllamaServerUrl();
    try {
      // Get list of downloaded models from Ollama
      const response = await fetch(`${serverUrl}/api/tags`, {
        method: 'GET',
        signal: AbortSignal.timeout(5000)
      });

      if (response.ok) {
        const data = await response.json();
        const downloadedModels = data.models || [];
        
        // Clear existing state
        this.ollamaModelsState = {};
        
        // First, mark our curated models as downloaded/not_downloaded
        AVAILABLE_OLLAMA_MODELS.forEach(model => {
          const isDownloaded = downloadedModels.some((downloaded: any) => downloaded.name === model.id);
          this.ollamaModelsState[model.id] = {
            status: isDownloaded ? 'downloaded' : 'not_downloaded'
          };
        });
        
        // Then, add any additional models found on the server that aren't in our curated list
        downloadedModels.forEach((serverModel: any) => {
          const modelId = serverModel.name;
          if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) return; // never include blocklisted models
          const isInCuratedList = AVAILABLE_OLLAMA_MODELS.some(model => model.id === modelId);
          
          if (!isInCuratedList) {
            // Add discovered model to state
            this.ollamaModelsState[modelId] = { status: 'downloaded' };
          }
        });
        
        this.saveOllamaModelsState();
        this.renderOllamaModelsList();
      }
    } catch (error) {
      logger.error('Failed to load Ollama models:', error);
      // Render with default state
      this.renderOllamaModelsList();
    }
  }

  private renderOllamaModelsList(): void {
    if (!this.ollamaModelsList) return;

    // Clear previous list
    this.ollamaModelsList.innerHTML = '';

    // Combine curated models and discovered models
    const allModelIds = new Set<string>();
    AVAILABLE_OLLAMA_MODELS.forEach(m => {
      if (!OLLAMA_MODEL_BLOCKLIST.has(m.id)) allModelIds.add(m.id);
    });
    Object.keys(this.ollamaModelsState).forEach(id => {
      if (!OLLAMA_MODEL_BLOCKLIST.has(id)) allModelIds.add(id);
    });

    // Build a sortable list with parsed sizes (MB)
    const parseSizeMB = (s: string): number => {
      if (!s) return Number.POSITIVE_INFINITY;
      const m = s.trim().toUpperCase().match(/([0-9]+(?:\.[0-9]+)?)\s*(MB|GB|KB)/);
      if (!m) return Number.POSITIVE_INFINITY;
      const val = parseFloat(m[1]);
      const unit = m[2];
      if (unit === 'GB') return val * 1024;
      if (unit === 'KB') return val / 1024;
      return val; // MB
    };

    const entries = Array.from(allModelIds).map(modelId => {
      const curatedModel = AVAILABLE_OLLAMA_MODELS.find(m => m.id === modelId);
      // If size is unknown (discovered model), leave undefined to push to end (Infinity)
      return { id: modelId, sizeMB: parseSizeMB(curatedModel?.size || '') };
    }).sort((a, b) => a.sizeMB - b.sizeMB);

    entries.forEach(({ id: modelId }) => {
      if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) return; // redundant guard
      const curatedModel = AVAILABLE_OLLAMA_MODELS.find(m => m.id === modelId);
      const state: OllamaModelState = this.ollamaModelsState[modelId] || { status: 'not_downloaded' };
      
      // Create model info (use curated info if available, otherwise create generic info)
      const modelInfo = curatedModel || {
        id: modelId,
        name: modelId,
        description: 'Model discovered on Ollama server',
        size: 'Unknown',
        parameters: 'Unknown'
      };
      
      const item = document.createElement('div');
      item.className = 'ollama-model-item';
      if (state.status === 'downloaded') {
        item.classList.add('can-select');
      }
      
      let actionHtml = '';
      switch (state.status) {
        case 'not_downloaded':
          actionHtml = `<button class="download-button" data-model-id="${modelInfo.id}">
                         <div class="download-button-content-wrapper">
                           <i class="fas fa-download"></i>
                           <span class="download-button-text">Download</span>
                         </div>
                       </button>`;
          break;
        case 'downloading':
          const progress = Math.max(0, Math.min(100, Math.round(state.progress || 0)));
          const completeClass = progress >= 100 ? ' complete' : '';
          actionHtml = `<button class="download-button downloading${completeClass}" data-model-id="${modelInfo.id}">
                         <div class="progress-bar-fill" style="width: ${progress}%"></div>
                         <div class="download-button-content-wrapper">
                           <span class="download-button-text">Downloading... ${progress}%</span>
                         </div>
                       </button>`;
          break;
        case 'downloaded':
          const isSelected = this.selectedOllamaModelId === modelInfo.id;
          const buttonClass = isSelected ? 'download-button use-button selected' : 'download-button use-button not-selected';
          actionHtml = `<button class="${buttonClass}" data-model-id="${modelInfo.id}">
                         <div class="download-button-content-wrapper">
                           <i class="fas fa-check"></i>
                           <span class="download-button-text">Use</span>
                         </div>
                       </button>`;
          break;
        case 'failed':
          actionHtml = `<button class="download-button retry" data-model-id="${modelInfo.id}">
                         <div class="download-button-content-wrapper">
                           <i class="fas fa-sync-alt"></i>
                           <span class="download-button-text">Retry</span>
                         </div>
                       </button>`;
          break;
      }

      const badge = curatedModel?.badge ? `<span class="model-badge">${curatedModel.badge}</span>` : '';
      const discoveredBadge = !curatedModel ? '<span class="model-badge" style="background-color: #6c757d;">Discovered</span>' : '';

      item.innerHTML = `
        <div class="ollama-model-details">
          <div class="ollama-model-name">
            ${modelInfo.name}
            ${badge}
            ${discoveredBadge}
          </div>
          <p class="ollama-model-description">${modelInfo.description}</p>
          <div class="ollama-model-meta">
            <div class="meta-tag"><i class="fas fa-microchip"></i> ${modelInfo.parameters}</div>
            <div class="meta-tag"><i class="fas fa-hdd"></i> ${modelInfo.size}</div>
            <div class="meta-tag"><i class="fas fa-server"></i> Local</div>
          </div>
        </div>
        <div class="ollama-model-action">
          ${actionHtml}
        </div>
        ${state.status === 'downloaded' ? `<button class="download-button delete-button corner-delete" data-model-id="${modelInfo.id}">
          <div class="download-button-content-wrapper">
            <i class="fas fa-trash"></i>
            <span class="download-button-text">Delete</span>
          </div>
        </button>` : ''}
      `;

  this.ollamaModelsList.appendChild(item);

      // Add event listeners to all action buttons
      const actionButtons = item.querySelectorAll('.download-button') as NodeListOf<HTMLButtonElement>;
      actionButtons.forEach(button => {
        button.addEventListener('click', (e) => this.handleOllamaModelAction(e, modelInfo, state));
      });
  });
  }

  private async handleOllamaModelAction(event: Event, model: OllamaModel, state: OllamaModelState): Promise<void> {
    event.stopPropagation();
    
    const button = event.currentTarget as HTMLButtonElement;
    const buttonText = button.querySelector('.download-button-text') as HTMLSpanElement;
    const currentText = buttonText?.textContent || '';

    if (currentText === 'Download' || currentText === 'Retry') {
      await this.downloadOllamaModel(model);
    } else if (currentText === 'Use') {
      this.useOllamaModel(model);
    } else if (currentText === 'Delete') {
      this.showConfirmationDialog(
        `Are you sure you want to delete the model "${model.name}"? This will remove it from your Ollama server.`,
        () => this.deleteOllamaModel(model)
      );
    }
  }

  private async downloadOllamaModel(model: OllamaModel): Promise<void> {
    const serverUrl = this.getOllamaServerUrl();
    try {
      logger.info(`Starting download of Ollama model: ${model.id} from ${serverUrl}`);
      
      // Update state to downloading
      this.ollamaModelsState[model.id] = { status: 'downloading', progress: 0 };
      this.saveOllamaModelsState();
      this.renderOllamaModelsList();

      // Call Ollama pull API with streaming to capture progress
      const response = await fetch(`${serverUrl}/api/pull`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: model.id, stream: true })
      });

      if (!response.ok || !response.body) {
        throw new Error(`Download failed with status: ${response.status}`);
      }

      // Stream NDJSON lines like {status:"downloading", completed:123, total:456}
      const reader = response.body.getReader();
      const decoder = new TextDecoder('utf-8');
      let buffer = '';
  let lastShown = -1;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let idx;
        while ((idx = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, idx).trim();
          buffer = buffer.slice(idx + 1);
          if (!line) continue;
          try {
            const obj = JSON.parse(line);
            // Prefer direct percent if provided; else compute from completed/total
            let pct = 0;
            if (typeof obj.percent === 'number') pct = obj.percent;
            else if (typeof obj.completed === 'number' && typeof obj.total === 'number' && obj.total > 0) {
              pct = (obj.completed / obj.total) * 100;
            }
            pct = Math.max(0, Math.min(100, Math.round(pct)));
            if (Math.round(pct) !== Math.round(lastShown) || pct === 100) {
              lastShown = pct;
              const cur = this.ollamaModelsState[model.id] || { status: 'downloading', progress: 0 };
              cur.status = 'downloading';
              cur.progress = pct;
              this.ollamaModelsState[model.id] = cur;
              this.saveOllamaModelsState();
              this.renderOllamaModelsList();
            }
          } catch {}
        }
      }

      // Mark complete
  this.ollamaModelsState[model.id] = { status: 'downloaded' };
      this.saveOllamaModelsState();
      this.renderOllamaModelsList();
      this.updateModelSelector();
      logger.info(`Successfully downloaded Ollama model: ${model.id}`);
    } catch (error) {
      logger.error(`Failed to download Ollama model ${model.id}:`, error);
      this.ollamaModelsState[model.id] = { status: 'failed' };
      this.saveOllamaModelsState();
      this.renderOllamaModelsList();
    }
  }

  private useOllamaModel(model: OllamaModel): void {
    logger.info(`Using Ollama model: ${model.id}`);
    
    // Update selected model
    this.selectedOllamaModelId = model.id;
    this.saveSelectedOllamaModel();
    
    // First ensure the model selector includes this model
    this.updateModelSelector();
    
    // Set the model selector to use this Ollama model
    const modelIdentifier = `ollama:${model.id}`;
    this.modelSelector.value = modelIdentifier;
    
    // Trigger change event to update UI
    this.modelSelector.dispatchEvent(new Event('change'));
    
    // Re-render the models list to update button colors
    this.renderOllamaModelsList();
    
    // Update stats display to show the new model
    this.updateStatsDisplay();
    
    // Auto-close settings modal to show the selection in main UI
    setTimeout(() => {
      this.closePromptModal();
    }, 500); // Small delay to let user see the selection change
    
    // Log for debugging
    logger.info(`Set active polishing model to: ${modelIdentifier}`);
  }

  private async deleteOllamaModel(model: OllamaModel): Promise<void> {
    const serverUrl = this.getOllamaServerUrl();
    try {
      logger.info(`Starting deletion of Ollama model: ${model.id} from ${serverUrl}`);
      
      // Use fetch to call ollama rm API
      const response = await fetch(`${serverUrl}/api/delete`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: model.id
        })
      });

      if (response.ok) {
        // Update state to not_downloaded
        this.ollamaModelsState[model.id] = { status: 'not_downloaded' };
        this.saveOllamaModelsState();
        this.renderOllamaModelsList();
        
        // Update model selector to remove the deleted Ollama model
        this.updateModelSelector();
        
        // If this was the selected model, clear the selection
        if (this.selectedOllamaModelId === model.id) {
          this.selectedOllamaModelId = null;
          this.saveSelectedOllamaModel();
        }
        
        logger.info(`Successfully deleted Ollama model: ${model.id}`);
      } else {
        throw new Error(`Deletion failed with status: ${response.status}`);
      }
    } catch (error) {
      logger.error(`Failed to delete Ollama model ${model.id}:`, error);
      // Don't update state on failure - keep it as downloaded
    }
  }

  private async checkOllamaModelUpdates(): Promise<void> {
    const serverUrl = this.getOllamaServerUrl();
    try {
      // Get list of downloaded models from Ollama
      const response = await fetch(`${serverUrl}/api/tags`, {
        method: 'GET',
        signal: AbortSignal.timeout(5000)
      });

      if (response.ok) {
        const data = await response.json();
        const downloadedModels = data.models || [];
        
        // Check each downloaded model for updates
        for (const modelId of Object.keys(this.ollamaModelsState)) {
          if (OLLAMA_MODEL_BLOCKLIST.has(modelId)) continue;
          const state = this.ollamaModelsState[modelId];
          if (state?.status === 'downloaded') {
            const isDownloaded = downloadedModels.some((downloaded: any) => downloaded.name === modelId);
            if (!isDownloaded) {
              // Model is no longer downloaded, update state
              this.ollamaModelsState[modelId] = { status: 'not_downloaded' };
              logger.info(`Model ${modelId} is no longer downloaded`);
            }
          }
        }
        
        this.saveOllamaModelsState();
        this.renderOllamaModelsList();
      }
    } catch (error) {
      logger.error('Failed to check Ollama model updates:', error);
    }
  }

  private setupTabs(): void {
    this.tabButtons.forEach((button) =>
      button.addEventListener('click', (e) =>
        this.setActiveTab(e.currentTarget as HTMLElement),
      ),
    );
    const initiallyActiveButton = document.querySelector(
      '.tab-button.active',
    ) as HTMLElement;
    if (initiallyActiveButton)
      requestAnimationFrame(() => this.setActiveTab(initiallyActiveButton, true));
  }

  private setActiveTab(activeButton: HTMLElement, skipAnimation = false): void {
    if (!activeButton || !this.activeTabIndicator) return;
    this.tabButtons.forEach((btn) => btn.classList.remove('active'));
    activeButton.classList.add('active');
    const tabName = activeButton.getAttribute('data-tab');
    this.noteContents.forEach((content) => content.classList.remove('active'));
    switch (tabName) {
      case 'raw':
        document.getElementById('rawTranscription')?.classList.add('active');
        this.copyButton.title = 'Copy All Notes';
        break;
      case 'x2':
        document.getElementById('polishedNoteX2')?.classList.add('active');
        this.copyButton.title = 'Copy Polished X2 Note';
        break;
      default:
        document.getElementById('polishedNote')?.classList.add('active');
        this.copyButton.title = 'Copy Note';
        break;
    }
    const originalTransition = this.activeTabIndicator.style.transition;
    if (skipAnimation) this.activeTabIndicator.style.transition = 'none';
    else this.activeTabIndicator.style.transition = '';
    this.activeTabIndicator.style.left = `${activeButton.offsetLeft}px`;
    this.activeTabIndicator.style.width = `${activeButton.offsetWidth}px`;
    if (skipAnimation) {
      // It's important to force a reflow for the 'none' transition to take effect
      // before it's restored, preventing a "snap-back" animation.
      this.activeTabIndicator.offsetHeight; 
      this.activeTabIndicator.style.transition = originalTransition;
    }
  }

  private setupSettingsTabs(): void {
    this.settingsTabButtons.forEach((button) => {
      button.addEventListener('click', () => this.setActiveSettingsTab(button));
    });
    // Ensure equal widths initially when modal is opened
    this.equalizeSettingsTabWidths();
    window.addEventListener('resize', () => this.equalizeSettingsTabWidths());
  }

  private equalizeSettingsTabWidths(): void {
    const buttons = Array.from(this.settingsTabButtons || []) as HTMLButtonElement[];
    if (!buttons.length) return;

    // If the nav is using two-row layout, let CSS handle widths
    const nav = document.querySelector('.modal-tab-nav') as HTMLElement | null;
  if (nav && nav.classList.contains('two-row-tabs')) {
      buttons.forEach((b) => (b.style.width = ''));
      return;
    }

    // For small screens, let CSS handle responsive behavior
    if (window.innerWidth <= 768) {
      buttons.forEach((b) => (b.style.width = ''));
      return;
    }

    // Reset widths to natural content size to measure
    buttons.forEach((b) => (b.style.width = 'auto'));

    // Measure the widest button
    let max = 0;
    buttons.forEach((b) => {
      const w = b.scrollWidth; // includes padding
      if (w > max) max = w;
    });

    // Apply the widest width to all buttons for uniform sizing
    // Add 2px for potential sub-pixel rounding differences
    const finalWidth = Math.ceil(max + 2);
    buttons.forEach((b) => (b.style.width = `${finalWidth}px`));
  }

  private setActiveSettingsTab(activeButton: HTMLButtonElement): void {
    const tabName = activeButton.getAttribute('data-tab');
    this.settingsTabButtons.forEach((button) =>
      button.classList.toggle('active', button === activeButton),
    );
    this.settingsTabContents.forEach((content) =>
      content.classList.toggle('active', content.id === `${tabName}TabContent`),
    );

    const isPromptTab = tabName === 'prompt';
    const isProvidersTab = tabName === 'providers';
  const isStatsTab = tabName === 'stats';
    const isHotkeyTab = tabName === 'hotkey';
    const isLocalModelsTab = tabName === 'localModels';
    const isLocalLlmTab = tabName === 'localLlm';

    const footerRight = this.promptModal.querySelector('.footer-right') as HTMLElement;
    if (footerRight)
      footerRight.style.display = isPromptTab || isProvidersTab || isHotkeyTab || isLocalModelsTab || isLocalLlmTab || isStatsTab ? 'flex' : 'none';
    if (this.resetUsageButton)
      this.resetUsageButton.style.display = isStatsTab ? 'inline-flex' : 'none';

    // Re-check Ollama status when Local LLM tab is selected
    if (isLocalLlmTab) {
      this.checkOllamaStatus();
    }

    // Always refresh Local Models list when switching into that tab
    if (isLocalModelsTab) {
      this.renderLocalModelsList();
    }

    // After DOM changes, re-equalize widths in case scrollbar shifts layout
    this.equalizeSettingsTabWidths();
  }

  // --- Local Model Methods ---
  private loadLocalModelsState(): void {
    const storedState = localStorage.getItem(LOCAL_MODELS_STATE_KEY);
    this.localModelsState = storedState ? JSON.parse(storedState) : {};
  }

  private saveLocalModelsState(): void {
    localStorage.setItem(LOCAL_MODELS_STATE_KEY, JSON.stringify(this.localModelsState));
  }

  private loadLocalModelProviders(): void {
    const storedProviders = localStorage.getItem(LOCAL_MODEL_PROVIDERS_KEY);
    this.localModelProviders = storedProviders ? JSON.parse(storedProviders) : {};
  }

  private saveLocalModelProviders(): void {
      localStorage.setItem(LOCAL_MODEL_PROVIDERS_KEY, JSON.stringify(this.localModelProviders));
  }

  private loadLocalModelFallbackReasons(): void {
    const storedReasons = localStorage.getItem(LOCAL_MODEL_FALLBACK_REASONS_KEY);
    this.localModelFallbackReasons = storedReasons ? JSON.parse(storedReasons) : {};
  }

  private saveLocalModelFallbackReasons(): void {
    localStorage.setItem(LOCAL_MODEL_FALLBACK_REASONS_KEY, JSON.stringify(this.localModelFallbackReasons));
  }

  private loadLocalTranscriptionLanguage(): void {
    try {
      const stored = (localStorage.getItem(LOCAL_TRANSCRIPTION_LANGUAGE_KEY) || 'auto').trim().toLowerCase();
      this.localTranscriptionLanguage = stored || 'auto';
      const custom = (localStorage.getItem(LOCAL_TRANSCRIPTION_LANGUAGE_CUSTOM_KEY) || '').trim();
      this.localTranscriptionLanguageCustom = custom;
    } catch {
      this.localTranscriptionLanguage = 'auto';
      this.localTranscriptionLanguageCustom = '';
    }
  }

  private saveLocalTranscriptionLanguage(): void {
    try {
      localStorage.setItem(LOCAL_TRANSCRIPTION_LANGUAGE_KEY, this.localTranscriptionLanguage);
      localStorage.setItem(LOCAL_TRANSCRIPTION_LANGUAGE_CUSTOM_KEY, this.localTranscriptionLanguageCustom);
    } catch {}
  }

  private initLocalLanguageControl(): void {
    const select = this.localLanguageSelect;
    const customInput = this.localLanguageCustomInput;
    if (!select) return;

    const applyCustomVisibility = () => {
      if (!customInput) return;
      const show = select.value === 'custom';
      customInput.style.display = show ? 'inline-block' : 'none';
      if (show) {
        customInput.value = this.localTranscriptionLanguageCustom;
        customInput.focus();
      }
    };

    const current = (this.localTranscriptionLanguage || 'auto').toLowerCase();
    const known = Array.from(select.options).map((o) => (o.value || '').toLowerCase());
    if (current && known.includes(current)) {
      select.value = current;
    } else if (this.localTranscriptionLanguageCustom) {
      select.value = 'custom';
    } else {
      select.value = 'auto';
    }

    try { new CustomSelect(select); } catch {}

    applyCustomVisibility();

    select.addEventListener('change', () => {
      const val = (select.value || 'auto').toLowerCase();
      this.localTranscriptionLanguage = val;
      if (val !== 'custom') {
        this.localTranscriptionLanguageCustom = '';
        if (customInput) customInput.value = '';
      }
      applyCustomVisibility();
      this.saveLocalTranscriptionLanguage();
    });

    select.dispatchEvent(new Event('change'));

    if (customInput) {
      customInput.addEventListener('input', () => {
        const value = customInput.value.trim().toLowerCase();
        this.localTranscriptionLanguageCustom = value;
        if (!value) {
          // keep select on custom but makes transcription fall back to auto
        }
        this.saveLocalTranscriptionLanguage();
      });
    }
  }

  private resolveForcedLocalLanguage(defaultLanguage: string): string {
    const forced = (this.localTranscriptionLanguage || 'auto').toLowerCase();
    if (forced === 'auto') return defaultLanguage;
    if (forced === 'custom') {
      const custom = (this.localTranscriptionLanguageCustom || '').trim();
      return custom ? custom : defaultLanguage;
    }
    return forced;
  }

  private handleLocalModelClick(model: LocalModel, state: LocalModelState): void {
    if (state.status === 'downloaded') {
      // Toggle activation: if it's already active, deactivate it by setting to null.
      if (this.stagedActiveLocalModelId === model.id) {
        this.stagedActiveLocalModelId = null;
      } else {
        this.stagedActiveLocalModelId = model.id;
      }
      
      // Re-render the list to show the change in the "Active" badge.
      // This change is only in the modal's state until "Save" is clicked.
      this.renderLocalModelsList();
    }
  }

  private async handleDownloadClick(e: Event, model: LocalModel): Promise<void> {
  e.preventDefault();
  e.stopPropagation();

  const w = (window as any);
  const isWebPreview = !w.__ELECTRON__ || !w.ipcRenderer;
  if (isWebPreview) {
    alert('This feature is not available in the web environment.');
    return;
  }

  // Optimistic "downloading" state
  this.localModelsState[model.id] = { status: 'downloading', progress: 0, path: null };
  this.saveLocalModelsState?.();
  this.renderLocalModelsList();

  try {
    if (w.whisper?.installModel) {
      await w.whisper.installModel(model.id);
    } else {
      await w.ipcRenderer.invoke('whisper:installModel', model.id);
    }

    this.localModelsState[model.id] = { status: 'downloaded', progress: 100, path: this.localModelsState[model.id]?.path ?? null };
    this.saveLocalModelsState?.();
    this.renderLocalModelsList();
  } catch (err: any) {
    this.localModelsState[model.id] = { status: 'failed', progress: 0, path: null, error: err?.message || 'Download failed' };
    this.saveLocalModelsState?.();
    this.renderLocalModelsList();
    console.error('Model install failed:', err);
  }
}


  private handleRemoveClick(e: Event, model: LocalModel): void {
    e.stopPropagation();
    this.showConfirmationDialog(
      `${this.t('localModels.deleteConfirm').replace('{name}', model.name)}`,
      async () => {
        try {
          const hasInvoke = typeof (window as any).whisper?.removeModel === 'function';
          if (hasInvoke) {
            const res = await (window as any).whisper.removeModel(model.id);
            if (res?.ok) {
              // proactively update UI state
              if (this.localModelsState[model.id]) {
                this.localModelsState[model.id].status = 'not_downloaded';
                this.localModelsState[model.id].progress = 0;
                this.localModelsState[model.id].path = null;
              }
              if (this.localModelProviders[model.id]) delete this.localModelProviders[model.id];
              if (this.localModelFallbackReasons[model.id]) delete this.localModelFallbackReasons[model.id];
              if (this.apiSettings.local.activeModelId === model.id) this.apiSettings.local.activeModelId = null;
              if (this.stagedActiveLocalModelId === model.id) this.stagedActiveLocalModelId = null;
              this.saveLocalModelsState();
              this.saveLocalModelProviders();
              this.saveLocalModelFallbackReasons();
              this.renderLocalModelsList();
              return;
            }
            // fallthrough to error if not ok
            this.showErrorDialog(this.t('localModels.deleteFailedTitle'), res?.error || this.t('localModels.deleteFailedBody'));
          } else if (ipcRenderer) {
            ipcRenderer.send('remove-local-model', { id: model.id });
          }
        } catch (err:any) {
          this.showErrorDialog(this.t('localModels.deleteFailedTitle'), err?.message || String(err));
        }
      }
    );
  }

  private getComputeTagHtml(modelId: string): string {
    const provider = this.localModelProviders[modelId];
    const fallbackReason = this.localModelFallbackReasons[modelId];

  if (provider === 'cpu') {
    return `<div class="meta-tag compute-cpu"><i class="fas fa-microchip"></i> CPU</div>`;
    }
    
  // Generic GPU marker support (in case older main/worker emit a generic value)
  if (provider === 'gpu') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU</div>`; }
  if (provider === 'vulkan') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i>GPU</div>`; }
  if (provider === 'metal') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU: Metal</div>`; }
  if (provider === 'cuda') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU: CUDA</div>`; }
  if (provider === 'rocm') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU: ROCm</div>`; }
  if (provider === 'openvino') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU: OpenVINO</div>`; }
  if (provider === 'directml') { return `<div class="meta-tag compute-gpu"><i class="fas fa-microchip"></i> GPU: DirectML</div>`; }
    if (provider === 'failed') {
        const sanitizedReason = fallbackReason?.replace(/"/g, '&quot;').replace(/>/g, '&gt;').replace(/</g, '&lt;') || 'Unknown error';
    const tooltipText = `${this.t('localModels.modelLoadFailedReason')} ${sanitizedReason}`;
    return `<div class="meta-tag compute-failed"><i class="fas fa-exclamation-triangle"></i> ${this.t('localModels.failed')} <i class="fas fa-info-circle" title="${tooltipText}"></i></div>`;
    }
    
  // Default state before model is confirmed: show neutral gray CPU (unknown)
  return `<div class="meta-tag compute-unknown"><i class="fas fa-microchip"></i> CPU</div>`;
  }

  private renderLocalModelsList(): void {
    if (!this.localModelsListContainer) return;

    this.localModelsListContainer.innerHTML = ''; // Clear previous list

    AVAILABLE_LOCAL_MODELS.forEach(model => {
        const state: LocalModelState = this.localModelsState[model.id] || { status: 'not_downloaded', progress: 0, path: null };
        const isActive = this.stagedActiveLocalModelId === model.id;
        const isWebPreview =
        !(window as any).__ELECTRON__ ||
        !(window as any).ipcRenderer; 
        const item = document.createElement('div');
        item.className = 'local-model-item';
        item.dataset.modelId = model.id;
        if (state.status === 'downloaded') {
          item.classList.add('can-select');
        }
        if (isActive) {
          item.classList.add('active');
        }

        const ratingDots = (rating: number) => {
          let dots = '';
          for (let i = 0; i < 5; i++) {
            dots += `<div class="rating-dot ${i < rating ? 'filled' : ''}"></div>`;
          }
          return `<div class="rating-dots">${dots}</div>`;
        };

        let actionHtml = '';
        switch (state.status) {
            case 'not_downloaded':
  actionHtml = isWebPreview
    ? `<button class="download-button" disabled title="${this.t('localModels.unavailableWeb')}">
         <div class="download-button-content-wrapper">
           <i class="fas fa-download"></i>
      <span class="download-button-text">${this.t('localModels.download')}</span>
         </div>
       </button>`
    : `<button class="download-button">
         <div class="download-button-content-wrapper">
           <i class="fas fa-download"></i>
      <span class="download-button-text">${this.t('localModels.download')}</span>
         </div>
       </button>`;
  break;

      case 'downloading':
        const pct = Math.max(0, Math.min(100, Math.round(state.progress || 0)));
        const completeClass = pct >= 100 ? ' complete' : '';
        actionHtml = `<button class="download-button downloading${completeClass}" disabled>
                <div class="progress-bar-fill" style="width: ${pct}%"></div>
                <div class="download-button-content-wrapper">
                  <span class="download-button-text">${this.t('localModels.downloading')} ${pct}%</span>
                </div>
                </button>`;
        break;
            case 'downloaded':
                const isSelected = isActive;
                const useBtnClass = isSelected ? 'download-button use-button selected' : 'download-button use-button not-selected';
                const useBtnHtml = `<button class="${useBtnClass}">
                                <div class="download-button-content-wrapper">
                                  <i class="fas fa-check"></i>
                                  <span class="download-button-text">${this.t('localModels.use')}</span>
                                </div>
                              </button>`;
                actionHtml = useBtnHtml;
                break;
            case 'failed':
  actionHtml = isWebPreview
    ? `<button class="download-button retry" disabled title="${this.t('localModels.unavailableWeb')}">
         <div class="download-button-content-wrapper">
           <i class="fas fa-sync-alt"></i>
      <span class="download-button-text">${this.t('localModels.retry')}</span>
         </div>
       </button>`
    : `<button class="download-button retry">
         <div class="download-button-content-wrapper">
           <i class="fas fa-sync-alt"></i>
      <span class="download-button-text">${this.t('localModels.retry')}</span>
         </div>
       </button>`;
  break;

        }

        item.innerHTML = `
            <div class="model-left">
              <div class="model-icon"><i class="fas fa-microchip"></i></div>
              <div class="compute-badge">${this.getComputeTagHtml(model.id)}</div>
            </div>
            <div class="model-details">
                <div class="model-title-row">
                    <h5 class="model-name">${model.name}</h5>
                    ${model.badge ? `<span class="model-badge">${model.badge}</span>` : ''}
                    ${isActive ? `<span class="model-badge active-indicator">${this.t('localModels.active')}</span>` : ''}
                </div>
                <p class="model-description">${model.description}</p>
        <div class="model-meta">
          <div class="meta-tag"><i class="fas fa-crosshairs"></i> ${this.t('localModels.accuracy')} ${ratingDots(model.accuracy)}</div>
          <div class="meta-tag"><i class="fas fa-bolt"></i> ${this.t('localModels.speed')} ${ratingDots(model.speed)}</div>
          <div class="meta-tag"><i class="fas fa-hdd"></i> ${model.size}</div>
          <div class="meta-tag"><i class="fas fa-globe"></i> ${model.language}</div>
        </div>
            </div>
            <div class="model-action">
                ${actionHtml}
            </div>
            ${state.status === 'downloaded' ? `<button class="download-button delete-button corner-delete">
              <div class="download-button-content-wrapper">
                <i class="fas fa-trash"></i>
        <span class="download-button-text">${this.t('localModels.delete')}</span>
              </div>
            </button>` : ''}
        `;

        this.localModelsListContainer.appendChild(item);

        // Do not toggle activation on whole-card click; only explicit buttons act
        item.addEventListener('click', (e) => {
          const isButton = (e.target as Element).closest('.download-button');
          if (isButton) return; // handled below
          // No-op otherwise to match Local LLMs behavior
        });

        // Wire buttons - handle web preview separately
        const downloadBtn = item.querySelector('.download-button:not(.use-button):not(.delete-button)');
        const useBtn = item.querySelector('.download-button.use-button');
        const deleteBtn = item.querySelector('.download-button.delete-button');
        
        if (isWebPreview) {
          // Disable all buttons in web preview
          item.querySelectorAll('.download-button').forEach(btnEl => {
            const btn = btnEl as HTMLButtonElement;
            btn.disabled = true;
            btn.classList.add('disabled');
            btn.onclick = (e) => { e.preventDefault(); e.stopPropagation(); };
          });
        } else {
          // Wire button handlers for Electron
          if (downloadBtn && (state.status === 'not_downloaded' || state.status === 'failed')) {
            downloadBtn.addEventListener('click', (e) => this.handleDownloadClick(e, model));
          }
          if (useBtn && state.status === 'downloaded') {
            useBtn.addEventListener('click', (e) => {
              e.stopPropagation();
              this.stagedActiveLocalModelId = model.id;
              this.renderLocalModelsList();
            });
          }
          if (deleteBtn && state.status === 'downloaded') {
            deleteBtn.addEventListener('click', (e) => {
              e.preventDefault();
              e.stopPropagation();
              this.handleRemoveClick(e, model);
            });
          }
        }
        // Disable buttons in web preview
    });
  }

  // --- Setup Wizard Methods ---
  private bindWizardEventListeners(): void {
    if (!this.wizardMicButton || !this.wizardFinishButton) return;

    this.wizardMicButton.addEventListener('click', () => this.checkWizardMicStatus(true));
    this.wizardFinishButton.addEventListener('click', () => this.finishSetup());
  }

  private startSetupWizard(): void {
    if (!this.setupWizardOverlay) return;
    this.setupWizardOverlay.style.display = 'flex';
    document.body.classList.add('modal-open');
    this.checkWizardApiKeyStatus();
    this.checkWizardMicStatus(false); // Initial check without prompt
  }

  private finishSetup(): void {
    if (!this.setupWizardOverlay) return;
    this.setupWizardOverlay.style.opacity = '0';
    this.setupWizardOverlay.addEventListener('transitionend', () => {
        this.setupWizardOverlay.style.display = 'none';
        if (!this.promptModal.classList.contains('visible') && !this.translationResultModal.classList.contains('visible')) {
            document.body.classList.remove('modal-open');
        }
    }, { once: true });
    localStorage.setItem(SETUP_WIZARD_COMPLETED_KEY, 'true');
  }

  private checkWizardApiKeyStatus(): void {
      if (!this.wizardApiKeyStatus) return;
  const isApiConfigured = (this.apiSettings.google.apiKey) ||
                           this.apiSettings.openai.apiKey ||
                           this.apiSettings.anthropic.apiKey ||
                           (this.apiSettings.custom.apiKey && this.apiSettings.custom.baseUrl);
      
      const isLocalConfigured = !!this.apiSettings.local.activeModelId;

      if (isApiConfigured || isLocalConfigured) {
          this.wizardApiKeyStatus.innerHTML = `<i class="fas fa-check-circle success"></i><span>Provider Configured</span>`;
          this.wizardApiKeyStatus.classList.add('success');
      } else {
          this.wizardApiKeyStatus.innerHTML = `<i class="fas fa-exclamation-triangle warning"></i><span>No provider found. Please configure in Settings.</span>`;
          this.wizardApiKeyStatus.classList.add('warning');
      }
  }

  private async checkWizardMicStatus(promptUser: boolean): Promise<void> {
      if (!this.wizardMicStatus || !this.wizardMicButton) return;

      const updateUi = (state: 'granted' | 'denied' | 'prompt') => {
          if (state === 'granted') {
              this.wizardMicStatus.innerHTML = `<i class="fas fa-check-circle success"></i><span>Microphone Access Granted</span>`;
              this.wizardMicStatus.classList.add('success');
              this.wizardMicStatus.classList.remove('warning');
              this.wizardMicButton.style.display = 'none';
          } else if (state === 'denied') {
              this.wizardMicStatus.innerHTML = `<i class="fas fa-exclamation-triangle warning"></i><span>Mic Access Denied. Check system settings.</span>`;
              this.wizardMicStatus.classList.remove('success');
              this.wizardMicStatus.classList.add('warning');
              this.wizardMicButton.textContent = 'Try Again';
              this.wizardMicButton.style.display = 'inline-flex';
          } else { // prompt
              this.wizardMicStatus.innerHTML = `<i class="fas fa-question-circle"></i><span>Microphone Permission Needed</span>`;
              this.wizardMicStatus.classList.remove('success', 'warning');
              this.wizardMicButton.textContent = 'Grant Access';
              this.wizardMicButton.style.display = 'inline-flex';
          }
      };

      if (promptUser) {
          try {
              const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
              stream.getTracks().forEach(track => track.stop());
              updateUi('granted');
          } catch (error) {
              logger.error("Mic permission error:", error);
              updateUi('denied');
          }
          return;
      }
      
      try {
          const permissions = await navigator.permissions.query({ name: 'microphone' as PermissionName });
          updateUi(permissions.state);
          permissions.onchange = () => updateUi(permissions.state);
      } catch (e) {
          updateUi('prompt'); // Fallback for environments without permissions.query
      }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  try {
    logger.info('DOMContentLoaded event fired.');
    new VoiceNotesApp();
    document
      .querySelectorAll<HTMLElement>('[contenteditable][placeholder]')
      .forEach((el) => {
        const placeholder = el.getAttribute('placeholder')!;
        function updatePlaceholderState() {
          if (!el.innerText?.trim() || el.innerText.trim() === placeholder) {
            if (!el.innerText?.trim()) el.innerHTML = placeholder;
            el.classList.add('placeholder-active');
          } else el.classList.remove('placeholder-active');
        }
        updatePlaceholderState();
        el.addEventListener('focus', function () {
          if (this.innerText?.trim() === placeholder) {
            this.innerHTML = '';
            this.classList.remove('placeholder-active');
          }
        });
        el.addEventListener('blur', updatePlaceholderState);
      });
    logger.info('Renderer process initialized successfully.');
    ipcRenderer?.send('renderer-is-ready');
  } catch (error) {
    logger.error('Fatal error during renderer initialization:', error);
    alert('A critical error occurred while starting the application. The application may not function correctly. Please check the logs.');
  }
});

export {};
