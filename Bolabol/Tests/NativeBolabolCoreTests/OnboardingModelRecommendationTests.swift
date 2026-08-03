import NativeBolabolCore
import Testing

private enum RecommendationTestModelID {
    static let gigaAM = "gigaam-v3-rnnt-coreml"
    static let canaryFlash = "canary-180m-flash-coreml"
    static let canary1B = "canary-1b-v2-coreml"
    static let largeV3 = "whisperkit-large-v3-full"
    static let turbo = "whisperkit-large-v3-turbo"
    static let parakeet = "parakeet-tdt-06b-v3"
}

@Test
func onboardingModelRecommendationMatchesLanguageMatrix() {
    let cases: [(primary: String, additional: String, expected: [String])] = [
        ("ru", "en", [
            RecommendationTestModelID.gigaAM,
            RecommendationTestModelID.canaryFlash,
            RecommendationTestModelID.largeV3
        ]),
        ("ru", "ru", [
            RecommendationTestModelID.gigaAM,
            RecommendationTestModelID.largeV3,
            RecommendationTestModelID.turbo
        ]),
        ("en", "es", [
            RecommendationTestModelID.canaryFlash,
            RecommendationTestModelID.largeV3,
            RecommendationTestModelID.turbo
        ]),
        ("en", "en", [
            RecommendationTestModelID.canaryFlash,
            RecommendationTestModelID.largeV3,
            RecommendationTestModelID.turbo
        ]),
        ("hi", "en", [
            RecommendationTestModelID.largeV3,
            RecommendationTestModelID.turbo,
            RecommendationTestModelID.canary1B
        ]),
        ("de", "fr", [
            RecommendationTestModelID.canaryFlash,
            RecommendationTestModelID.largeV3,
            RecommendationTestModelID.turbo
        ])
    ]

    for testCase in cases {
        let result = OnboardingModelRecommendation.topThree(
            primary: testCase.primary,
            additional: testCase.additional,
            available: allRecommendationModels()
        )

        #expect(result.map(\.id) == testCase.expected)
    }
}

@Test
func onboardingModelRecommendationUsesCanaryFlashForEveryCompactLanguagePair() {
    let compactLanguages = ["en", "de", "fr", "es"]
    let expected = [
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ]

    for primary in compactLanguages {
        for additional in compactLanguages {
            let result = OnboardingModelRecommendation.topThree(
                primary: primary,
                additional: additional,
                available: allRecommendationModels()
            )

            #expect(result.map(\.id) == expected, "Unexpected compact ranking for \(primary)+\(additional)")
        }
    }
}

@Test
func onboardingModelRecommendationUsesR3OrderForOtherLanguagePairs() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "zh",
        additional: "en",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.canary1B
    ])
}

@Test
func onboardingModelRecommendationAppliesRussianRuleWhenAdditionalIsRussian() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "ru",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ])
}

@Test
func onboardingModelRecommendationNormalizesSpeechLanguageCodes() {
    let result = OnboardingModelRecommendation.topThree(
        primary: " RU ",
        additional: " EN ",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.largeV3
    ])
}

@Test
func onboardingModelRecommendationNormalizesRussianAdditionalLanguageCode() {
    let result = OnboardingModelRecommendation.topThree(
        primary: " EN ",
        additional: " Ru ",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ])
}

@Test
func onboardingModelRecommendationCollapsesMissingGigaAM() {
    let available = allRecommendationModels().filter { $0.id != RecommendationTestModelID.gigaAM }

    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: available
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.largeV3
    ])
}

@Test
func onboardingModelRecommendationUsesParakeetWhenCanary1BIsUnavailable() {
    let available = allRecommendationModels().filter { $0.id != RecommendationTestModelID.canary1B }

    let result = OnboardingModelRecommendation.topThree(
        primary: "hi",
        additional: "en",
        available: available
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.parakeet
    ])
}

@Test
func onboardingModelRecommendationUsesFlashAsFinalR3Fallback() {
    let available = allRecommendationModels().filter {
        $0.id != RecommendationTestModelID.canary1B && $0.id != RecommendationTestModelID.parakeet
    }

    let result = OnboardingModelRecommendation.topThree(
        primary: "hi",
        additional: "en",
        available: available
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.canaryFlash
    ])
}

@Test
func onboardingModelRecommendationReturnsEmptyForEmptyCatalog() {
    #expect(OnboardingModelRecommendation.topThree(primary: "ru", additional: "en", available: []).isEmpty)
}

@Test
func onboardingModelRecommendationDoesNotReturnDuplicateModels() {
    let models = allRecommendationModels()
    let available = models + [models[0]]

    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: available
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.largeV3
    ])
    #expect(result.map(\.id).count == Set(result.map(\.id)).count)
}

@Test
func onboardingModelRecommendationCapsResultAtThreeModels() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "hi",
        additional: "en",
        available: allRecommendationModels()
    )

    #expect(result.count == 3)
    #expect(result.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.canary1B
    ])
}

@Test
func onboardingModelRecommendationAcceptsOnlySpeechLanguageInputs() {
    // The explicit function type has no UI-language input, keeping ranking pure.
    let ranking: (String, String, [TranscriptionModelDescriptor]) -> [TranscriptionModelDescriptor] =
        OnboardingModelRecommendation.topThree

    let result = ranking("en", "es", allRecommendationModels())

    #expect(result.map(\.id) == [
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ])
}

private func allRecommendationModels() -> [TranscriptionModelDescriptor] {
    [
        makeRecommendationModel(id: RecommendationTestModelID.gigaAM),
        makeRecommendationModel(id: RecommendationTestModelID.canaryFlash),
        makeRecommendationModel(id: RecommendationTestModelID.canary1B),
        makeRecommendationModel(id: RecommendationTestModelID.largeV3),
        makeRecommendationModel(id: RecommendationTestModelID.turbo),
        makeRecommendationModel(id: RecommendationTestModelID.parakeet)
    ]
}

private func makeRecommendationModel(id: String) -> TranscriptionModelDescriptor {
    TranscriptionModelDescriptor(
        id: id,
        displayName: id,
        modelName: id,
        backend: .fluidAudioCoreML,
        languageSupport: .multilingual,
        downloadSize: "1 MB",
        description: "Test model",
        accuracy: 3,
        speed: 3
    )
}
