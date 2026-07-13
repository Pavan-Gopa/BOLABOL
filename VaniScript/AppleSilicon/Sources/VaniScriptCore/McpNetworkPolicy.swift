import Foundation

public enum McpNetworkPolicy {
    public static func validatedPublicMediaURL(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !isBlockedHost(host),
              let url = components.url
        else {
            return nil
        }
        return url
    }

    public static func isBlockedHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        if host == "::1" || host == "0:0:0:0:0:0:0:1" || host == "::" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        let first = octets[0]
        let second = octets[1]
        return first == 0
            || first == 10
            || first == 127
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 100 && (64...127).contains(second))
            || first >= 224
    }
}
