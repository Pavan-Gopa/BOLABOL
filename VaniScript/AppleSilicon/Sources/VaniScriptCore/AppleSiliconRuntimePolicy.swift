public enum AppleSiliconRuntimePolicy {
    public static let requiredArchitecture = "arm64"

    public static func isSupported(machineArchitecture: String) -> Bool {
        machineArchitecture == requiredArchitecture
    }
}
