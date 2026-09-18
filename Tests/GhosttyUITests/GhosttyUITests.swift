import AppKit
import Testing
@testable import GhosttyUI

struct GhosttyURLPolicyTests {
    @Test func allowsHTTPS() {
        switch GhosttyURLPolicy.decide("https://example.com/docs") {
        case .allow(let url):
            #expect(url.host == "example.com")
        case .deny:
            Issue.record("https should be allowed")
        }
    }

    @Test func deniesFileURLs() {
        switch GhosttyURLPolicy.decide("file:///etc/passwd") {
        case .allow:
            Issue.record("file URLs must not be opened from terminal output")
        case .deny(let reason):
            #expect(reason.contains("file"))
        }
    }

    @Test func deniesJavascript() {
        switch GhosttyURLPolicy.decide("javascript:alert(1)") {
        case .allow:
            Issue.record("javascript URLs must be blocked")
        case .deny:
            break
        }
    }

    @Test func rejectsGarbage() {
        switch GhosttyURLPolicy.decide("not a url") {
        case .allow:
            Issue.record("garbage should be denied")
        case .deny:
            break
        }
    }
}

struct GhosttyInputTests {
    @Test func scrollModsPackPrecisionAndMomentum() {
        let packed = GhosttyInput.scrollMods(precision: true, momentumPhase: .began)
        #expect(packed & 0b1 == 1)
        #expect((packed >> 1) & 0b111 == 1)
    }

    @Test func mouseButtonsMatchGhosttyEnum() {
        #expect(GhosttyInput.mouseButton(fromNSEventButtonNumber: 0) == 1)
        #expect(GhosttyInput.mouseButton(fromNSEventButtonNumber: 1) == 2)
        #expect(GhosttyInput.mouseButton(fromNSEventButtonNumber: 2) == 3)
        #expect(GhosttyInput.mouseButton(fromNSEventButtonNumber: 99) == 0)
    }
}

struct GhosttySurfaceConfigurationTests {
    @Test func defaultsAreSafe() {
        let config = GhosttySurfaceConfiguration()
        #expect(config.command == nil)
        #expect(config.allowsUnconfirmedClipboardWrites == false)
        #expect(config.waitAfterCommand == false)
        #expect(config.fontSize == 0)
    }
}

struct GhosttyRuntimeAvailabilityTests {
    @Test func availabilityMatchesCompileFlag() {
        #if GHOSTTYUI_HAS_KIT
        #expect(GhosttyRuntime.isAvailable)
        #else
        #expect(!GhosttyRuntime.isAvailable)
        #endif
    }
}
