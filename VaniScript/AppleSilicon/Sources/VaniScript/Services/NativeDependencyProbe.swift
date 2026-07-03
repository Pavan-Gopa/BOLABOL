import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import VaniScriptCore
import WhisperKit

struct NativeDependencyProbe {
    let transcriptionBackend = NativeEngineCatalog.transcriptionBackend
    let polishingBackend = NativeEngineCatalog.polishingBackend
    let dependencySet = "MLX Swift + WhisperKit"
}
