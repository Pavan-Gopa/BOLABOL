import Foundation
import NativeBolabolCore
import Testing

// Exhaustive coverage of domain models, status machines, and pure value types
// that power notes, HUD, transcription, and polishing surfaces.

// MARK: - ProcessingVariant / statuses

@Test
func processingVariantTitlesAndSystemImagesAreStable() {
  #expect(ProcessingVariant.allCases.map(\.id) == ["raw", "variantOne", "variantTwo"])
  #expect(ProcessingVariant.raw.title == "Raw")
  #expect(ProcessingVariant.variantOne.title == "Variant 1")
  #expect(ProcessingVariant.variantTwo.title == "Variant 2")
  #expect(ProcessingVariant.raw.systemImage == "waveform")
  #expect(ProcessingVariant.variantOne.systemImage == "text.alignleft")
  #expect(ProcessingVariant.variantTwo.systemImage == "sparkles")
}

@Test
func processingVariantCodableRoundTrip() throws {
  for variant in ProcessingVariant.allCases {
    let data = try JSONEncoder().encode(variant)
    let decoded = try JSONDecoder().decode(ProcessingVariant.self, from: data)
    #expect(decoded == variant)
  }
}

@Test
func transcriptionStatusFactoriesCoverAllPhases() throws {
  #expect(TranscriptionStatus.idle.phase == .idle)
  #expect(TranscriptionStatus.pending.phase == .pending)
  #expect(TranscriptionStatus.transcribing(backendName: "W").phase == .transcribing)
  #expect(TranscriptionStatus.transcribing(backendName: "W").backendName == "W")
  #expect(TranscriptionStatus.completed(backendName: "G").phase == .completed)
  let failed = TranscriptionStatus.failed(message: "boom", backendName: "X")
  #expect(failed.phase == .failed)
  #expect(failed.message == "boom")

  let data = try JSONEncoder().encode(failed)
  let decoded = try JSONDecoder().decode(TranscriptionStatus.self, from: data)
  #expect(decoded == failed)
}

@Test
func polishingStatusFactoriesCoverAllPhases() throws {
  #expect(PolishingStatus.idle.phase == .idle)
  #expect(PolishingStatus.pending.phase == .pending)
  #expect(PolishingStatus.polishing(backendName: "MLX").backendName == "MLX")
  #expect(PolishingStatus.completed().phase == .completed)
  let failed = PolishingStatus.failed(message: "timeout")
  #expect(failed.phase == .failed && failed.message == "timeout")

  let data = try JSONEncoder().encode(failed)
  #expect(try JSONDecoder().decode(PolishingStatus.self, from: data) == failed)
}

// MARK: - BolabolNote

@Test
func bolabolNotePolishingStatusDefaultsToIdle() {
  let note = BolabolNote(title: "T", rawText: "r")
  #expect(note.polishingStatus(for: .variantOne) == .idle)
  #expect(note.polishingStatus(for: .variantTwo).phase == .idle)
}

@Test
func bolabolNoteBestDisplayTextPrefersRawThenVariants() {
  #expect(BolabolNote(title: "t", rawText: " raw ").bestDisplayText() == "raw")
  #expect(
    BolabolNote(title: "t", rawText: "", polishedVariantOne: " v1 ").bestDisplayText() == "v1"
  )
  #expect(
    BolabolNote(title: "t", rawText: "  ", polishedVariantOne: "", polishedVariantTwo: "v2")
      .bestDisplayText() == "v2"
  )
  #expect(BolabolNote(title: "t", rawText: "").bestDisplayText().isEmpty)
}

@Test
func bolabolNotePreviewTextTruncatesAndFallsBackToTitle() {
  let long = String(repeating: "word ", count: 40)
  let note = BolabolNote(title: "Title", rawText: long)
  let preview = note.previewText(maxLength: 20)
  #expect(preview.hasSuffix("..."))
  #expect(preview.count <= 20)

  let empty = BolabolNote(title: "  My Title  ", rawText: "")
  // previewText returns the original title when body is empty (trim only for emptiness check).
  #expect(empty.previewText() == "  My Title  ")

  let blank = BolabolNote(title: "   ", rawText: "")
  #expect(blank.previewText() == AppText.localized(.blankNoteFallback, language: .english))
}

@Test
func bolabolNoteCopyAllTextJoinsChronologicallyAndSkipsEmpty() {
  let older = BolabolNote(
    title: "a",
    createdAt: Date(timeIntervalSince1970: 100),
    rawText: "first"
  )
  let newer = BolabolNote(
    title: "b",
    createdAt: Date(timeIntervalSince1970: 200),
    rawText: "",
    polishedVariantOne: "second"
  )
  let empty = BolabolNote(
    title: "c",
    createdAt: Date(timeIntervalSince1970: 150),
    rawText: "  "
  )
  #expect([newer, empty, older].copyAllText() == "first\n\nsecond")
}

@Test
func bolabolNoteCodableRoundTripPreservesStatuses() throws {
  var note = BolabolNote(title: "n", rawText: "raw")
  note.transcriptionStatus = .completed(backendName: "Whisper")
  note.polishingStatuses[.variantOne] = .failed(message: "err")
  let data = try JSONEncoder().encode(note)
  let decoded = try JSONDecoder().decode(BolabolNote.self, from: data)
  #expect(decoded.title == "n")
  #expect(decoded.transcriptionStatus.backendName == "Whisper")
  #expect(decoded.polishingStatuses[.variantOne]?.message == "err")
}

@Test
func bolabolNotePreviewArrayIsNonEmpty() {
  #expect(!Array<BolabolNote>.preview.isEmpty)
  #expect(Array<BolabolNote>.preview.allSatisfy { !$0.rawText.isEmpty })
}

// MARK: - AudioRecording

@Test
func audioRecordingDefaultsAndLegacyDecode() throws {
  let url = URL(fileURLWithPath: "/tmp/bolabol-test.wav")
  let recording = AudioRecording(
    fileURL: url,
    duration: 3.5,
    sampleRate: 16_000,
    channelCount: 1
  )
  #expect(recording.source == .microphone)
  #expect(recording.suggestedTitle == AppText.localized(.voiceNote, language: .english))

  let encoder = JSONEncoder()
  var obj = try JSONSerialization.jsonObject(with: encoder.encode(recording)) as! [String: Any]
  obj.removeValue(forKey: "source")
  let stripped = try JSONSerialization.data(withJSONObject: obj)
  let decoded = try JSONDecoder().decode(AudioRecording.self, from: stripped)
  #expect(decoded.source == .microphone)
}

@Test
func audioRecordingImportedFileSourceRoundTrips() throws {
  let recording = AudioRecording(
    fileURL: URL(fileURLWithPath: "/tmp/import.m4a"),
    duration: 1,
    sampleRate: 44_100,
    channelCount: 2,
    fileSizeBytes: 99,
    suggestedTitle: "Import",
    source: .importedFile
  )
  let data = try JSONEncoder().encode(recording)
  let decoded = try JSONDecoder().decode(AudioRecording.self, from: data)
  #expect(decoded.source == .importedFile)
  #expect(decoded.fileSizeBytes == 99)
  #expect(decoded.channelCount == 2)
}

// MARK: - Language modes / options

@Test
func transcriptionLanguageModeFullToggleCycleIsIdempotent() {
  #expect(TranscriptionLanguageMode.auto.toggled().toggled() == .auto)
  #expect(TranscriptionLanguageMode.target.toggled().toggled() == .target)
}

@Test
func transcriptionLanguagePreferenceResolvedCodeNormalizes() {
  #expect(TranscriptionLanguagePreference.auto.resolvedCode(defaultCode: "EN") == "en")
  #expect(TranscriptionLanguagePreference.language(" RU ").resolvedCode(defaultCode: "en") == "ru")
  #expect(TranscriptionLanguagePreference.custom("").resolvedCode(defaultCode: "es") == "es")
  #expect(TranscriptionLanguagePreference.custom("  ").resolvedCode(defaultCode: "pt") == "pt")
  #expect(TranscriptionLanguagePreference.language("De").resolvedCode(defaultCode: "en") == "de")
}

@Test
func transcriptionLanguageOptionBuiltInCoversMajorLanguages() {
  let codes = Set(TranscriptionLanguageOption.builtIn.map(\.code))
  for code in ["en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko", "ar", "hi"] {
    #expect(codes.contains(code), "Missing built-in language \(code)")
  }
  #expect(TranscriptionLanguageOption.displayName(for: "en") == "English")
  #expect(TranscriptionLanguageOption.displayName(for: "english") == "English")
  #expect(TranscriptionLanguageOption.displayName(for: "xx") == "xx")
}

@Test
func transcriptionLanguageHUDLabelsUseFirstLetterOfEnglishName() {
  #expect(TranscriptionLanguageOption.hudLabel(for: "en") == "E")
  #expect(TranscriptionLanguageOption.hudLabel(for: "Spanish") == "S")
  #expect(TranscriptionLanguageOption.hudLabel(for: "ru") == "R")
  #expect(TranscriptionLanguageOption.hudLabel(for: "zh") == "C")
  #expect(TranscriptionLanguageOption.hudLabel(for: "") == "E")
  #expect(TranscriptionLanguageOption.hudLabel(for: "   ") == "E")
  #expect(TranscriptionLanguageOption.hudLabel(for: "123") == "E")
}

// MARK: - Transcription backend

@Test
func transcriptionBackendsBothSupportRawHotkeyTarget() {
  for backend in TranscriptionBackend.allCases {
    #expect(backend.supportsRawHotkeyTarget)
    #expect(!backend.displayName.isEmpty)
    #expect(!backend.shortDescription.isEmpty)
    #expect(backend.id == backend.rawValue)
  }
  #expect(TranscriptionBackend.localWhisper.displayName == "Local")
  #expect(TranscriptionBackend.geminiCloud.displayName.contains("Google"))
}

// MARK: - Engine protocols value types

@Test
func engineDiagnosticsAndRequestResultDefaults() {
  let diag = EngineDiagnostics(backendName: "test", promptTokens: 10, completionTokens: 5)
  #expect(diag.backendName == "test")
  #expect(diag.promptTokens == 10)

  let polishReq = PolishingRequest(
    rawText: "hi",
    variant: .variantOne,
    template: PromptTemplate(id: "t", title: "T", body: "Body ${transcription}")
  )
  #expect(polishReq.variant == .variantOne)

  let polishRes = PolishingResult(text: "out", diagnostics: diag)
  #expect(polishRes.text == "out")

  let trReq = TranscriptionRequest(forcedLanguageCode: "ru", translateToEnglish: true)
  #expect(trReq.translateToEnglish)
  #expect(trReq.forcedLanguageCode == "ru")
  #expect(trReq.audioFileURL == nil)

  let trRes = TranscriptionResult(text: "said", diagnostics: diag)
  #expect(trRes.text == "said")
}

// MARK: - Installation / preparation states

@Test
func polishingModelInstallationStateProgressClampsAndFlags() {
  let downloading = PolishingModelInstallationState.downloading(progressFraction: 1.5)
  #expect(downloading.progressFraction == 1)
  #expect(!downloading.isDownloaded)

  let negative = PolishingModelInstallationState.downloading(progressFraction: -0.2)
  #expect(negative.progressFraction == 0)

  let done = PolishingModelInstallationState.downloaded(
    localURL: URL(fileURLWithPath: "/tmp/model")
  )
  #expect(done.isDownloaded)
  #expect(done.progressFraction == 1)

  let failed = PolishingModelInstallationState.failed("disk full")
  #expect(failed.status == .failed)
  #expect(failed.errorMessage == "disk full")
  #expect(PolishingModelInstallationState.notDownloaded().status == .notDownloaded)
}

@Test
func modelPreparationSnapshotPhasesAndClamp() {
  #expect(ModelPreparationSnapshot.notReady().phase == .notReady)
  #expect(
    ModelPreparationSnapshot.downloading(progressFraction: 2).progressFraction == 1
  )
  #expect(ModelPreparationSnapshot.loading().phase == .loading)
  #expect(ModelPreparationSnapshot.ready().phase == .ready)
  #expect(ModelPreparationSnapshot.failed(message: "x").message == "x")
}

// MARK: - Local model descriptor

@Test
func localModelDescriptorRolesAndBackendsRoundTrip() throws {
  let model = LocalModelDescriptor(
    id: "parakeet",
    displayName: "Parakeet",
    role: .transcription,
    backend: .parakeet,
    minimumMemoryGB: 4
  )
  let data = try JSONEncoder().encode(model)
  let decoded = try JSONDecoder().decode(LocalModelDescriptor.self, from: data)
  #expect(decoded.role == .transcription)
  #expect(decoded.backend == .parakeet)
  #expect(decoded.minimumMemoryGB == 4)
}

// MARK: - Polishing model descriptor

@Test
func polishingModelDescriptorClampsRatingsAndBuildsCacheFolder() {
  let model = PolishingModelDescriptor(
    id: "q",
    displayName: "Qwen",
    repositoryID: "mlx-community/Qwen3.5-4B-4bit",
    backend: .mlxSwiftLLM,
    downloadSize: "2 GB",
    description: "test",
    quality: 99,
    speed: 0
  )
  #expect(model.quality == 5)
  #expect(model.speed == 1)
  #expect(
    model.huggingFaceCacheFolderName
      == "models--mlx-community--Qwen3.5-4B-4bit"
  )
}

// MARK: - Glossary language catalog

@Test
func glossaryLanguageCatalogDefaultsAndNormalization() {
  #expect(GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage == "English")
  #expect(GlossaryLanguageCatalog.defaultAutoTranslationLanguage == "Russian")
  #expect(GlossaryLanguageCatalog.normalizedName(" russian ", fallback: "English") == "Russian")
  #expect(GlossaryLanguageCatalog.normalizedName("Klingon", fallback: "English") == "Klingon")
  #expect(GlossaryLanguageCatalog.normalizedName("", fallback: "") == "English")
  #expect(
    GlossaryLanguageCatalog.defaultAutoTranslationLanguage(for: "English") == "Russian"
  )
  #expect(
    GlossaryLanguageCatalog.defaultAutoTranslationLanguage(for: "Russian") == "English"
  )
  #expect(GlossaryLanguageCatalog.builtIn.count >= 12)
}

// MARK: - General settings enums

@Test
func generalSettingsPreferenceEnumsExposeDisplayNames() {
  for theme in ThemePreference.allCases {
    #expect(!theme.displayName.isEmpty)
  }
  for font in TextFontPreference.allCases {
    #expect(!font.displayName.isEmpty)
  }
  for pos in OverlayPosition.allCases {
    #expect(!pos.displayName.isEmpty)
  }
  for level in AppLogLevel.allCases {
    #expect(!level.displayName.isEmpty)
  }
  #expect(OverlayHUDStyle.allCases.map(\.rawValue).contains("capsule"))
  #expect(OverlayHUDStyle.allCases.map(\.rawValue).contains("tech"))
  #expect(OverlayHUDStyle.allCases.map(\.rawValue).contains("vertical"))
}

@Test
func generalSettingsClampsMaxSavedAudioRecordings() {
  var settings = GeneralSettings(maxSavedAudioRecordings: 1)
  #expect(settings.maxSavedAudioRecordings == 2)
  settings.maxSavedAudioRecordings = 9999
  settings.normalize()
  #expect(settings.maxSavedAudioRecordings == 500)
  settings.maxSavedAudioRecordings = 50
  settings.normalize()
  #expect(settings.maxSavedAudioRecordings == 50)
}

@Test
func generalSettingsClampsTextScale() {
  var settings = GeneralSettings(textScale: 0.1)
  #expect(settings.textScale == 1.0)
  settings.textScale = 9
  settings.normalize()
  #expect(settings.textScale == 2.0)
}

// MARK: - Sidebar metrics

@Test
func sidebarLayoutMetricsConstants() {
  #expect(SidebarLayoutMetrics.minimumWidth == 220)
  #expect(SidebarLayoutMetrics.idealWidth == 280)
  #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 900) == 300)
  #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 100) == 220)
}

// MARK: - Log subsystem identity

@Test
func nativeBolabolLogSubsystemIsStable() {
  #expect(NativeBolabolLog.subsystem == "com.pavan.NativeBolabol")
}

// MARK: - Hotkey output modes

@Test
func hotkeyOutputModesHaveDisplayNames() {
  #expect(HotkeyOutputMode.clipboard.displayName == "Copy to Clipboard")
  #expect(HotkeyOutputMode.typing.displayName == "Type into Active App")
  #expect(HotkeyTarget.raw.displayName == "Raw transcription")
  #expect(HotkeyTarget.note.displayName == "Variant 1")
  #expect(HotkeyTarget.x2.displayName == "Variant 2")
}
