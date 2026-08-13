import AppKit
import SwiftUI

@MainActor
struct LicensingSettingsView: View {
    @State private var isShowingLegalText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                fivePersonCard
                freedomClockCard
                commercialCard
                legalCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.trailing, 4)
        }
        .overlayScrollbar()
        .sheet(isPresented: $isShowingLegalText) {
            legalTextSheet
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BOLABOL Licensing")
                        .font(.title2.weight(.semibold))
                    Text("Business Source License 1.1")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Free for people. Sustainable for builders. Open with time.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.14), Color.purple.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.purple.opacity(0.24), lineWidth: 1)
        }
    }

    private var fivePersonCard: some View {
        licenseCard(icon: "person.3.fill", title: "The Five-Person Grant", tint: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Up to five active human users in one organization may use BOLABOL in production for free.")
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("5")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("humans free")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text("6th = commercial")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("The limit is based on people actually using BOLABOL — not company revenue, valuation, device count, or total headcount.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("AI agents, bots, automated workflows, models, and devices do not count as separate users when they act solely on behalf of a human Active User.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var freedomClockCard: some View {
        licenseCard(icon: "clock.arrow.circlepath", title: "The Freedom Clock", tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Every specific BOLABOL release automatically becomes Open Source three years after its first public distribution.")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("Release")
                    Image(systemName: "arrow.right")
                    Text("3 years under BSL 1.1")
                    Image(systemName: "arrow.right")
                    Text("GPL v3+")
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("Before its Freedom Date, a release is source-available rather than OSI Open Source. When the clock runs out, that specific release transitions to GNU GPL v3 or later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commercialCard: some View {
        licenseCard(icon: "building.2.fill", title: "When a commercial license is required", tint: .orange) {
            VStack(alignment: .leading, spacing: 9) {
                bullet("Six or more Active Users use BOLABOL in production for the same organization.")
                bullet("BOLABOL or a derivative is resold, white-labeled, sublicensed, rented, or commercially redistributed.")
                bullet("BOLABOL is offered as a hosted or managed service, or embedded as a material part of a commercial product or service for third parties.")

                Text("A company does not need a commercial license merely because it makes money. Five or fewer active human users remain within the Five-Person Grant, subject to the legal terms.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var legalCard: some View {
        licenseCard(icon: "doc.text.fill", title: "Legal text & details", tint: .gray) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This screen is a plain-language summary. The bundled LICENSE is the controlling legal text.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        isShowingLegalText = true
                    } label: {
                        Label("Read LICENSE", systemImage: "doc.plaintext")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        openRepositoryDocument("LICENSING.md")
                    } label: {
                        Label("Licensing guide", systemImage: "book.closed")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openRepositoryDocument("COMMERCIAL.md")
                    } label: {
                        Label("Commercial", systemImage: "building.2")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
    }

    private var legalTextSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOLABOL — Business Source License 1.1")
                        .font(.headline)
                    Text("Five-Person Grant · Three-year Freedom Clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    isShowingLegalText = false
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                Text(bundledLicenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
            }
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 620)
    }

    private var bundledLicenseText: String {
        let releaseURL = Bundle.main.url(forResource: "BOLABOL_LICENSE", withExtension: "txt")
        let developmentURL = Bundle.module.url(forResource: "BOLABOL_LICENSE", withExtension: "txt")

        for url in [releaseURL, developmentURL].compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        return "The bundled license could not be loaded. The canonical license is available in the BOLABOL GitHub repository."
    }

    @ViewBuilder
    private func licenseCard<Content: View>(
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(title)
                    .font(.headline)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openRepositoryDocument(_ document: String) {
        guard let url = URL(string: "https://github.com/Pavan-Gopa/BOLABOL/blob/main/\(document)") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    LicensingSettingsView()
        .frame(width: 720, height: 640)
}
