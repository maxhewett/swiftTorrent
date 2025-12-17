//
//  LocalWebServer.swift
//  swiftTorrent
//
//  Created by Max Hewett on 16/12/2025.
//

import Foundation
import Swifter

@MainActor
final class LocalWebServer {
    static let shared = LocalWebServer()

    private let server = HttpServer()
    private var isConfigured = false
    private var currentPort: in_port_t?

    // IMPORTANT: attach the *existing* engine (don’t create a second one)
    private weak var engine: TorrentEngine?

    // Transmission-compatible RPC
    private let rpc = TransmissionRPC()

    func attach(engine: TorrentEngine) {
        self.engine = engine
        rpc.attach(engine: engine)

        // If the server is already running, routes are already installed.
        // Just log; the handler will now succeed because engine is attached.
        if currentPort != nil {
            print("TorrentEngine attached; Transmission RPC is now live at /transmission/rpc")
        }
    }

    func start(port: Int) {
        let p = in_port_t(clamping: port)

        // If already running on the same port, do nothing
        if currentPort == p { return }

        // Restart cleanly
        stop()

        configureRoutesIfNeeded()
        configureStaticWebUI()

        do {
            try server.start(p, forceIPv4: true)
            currentPort = p
            print("WebUI running at http://127.0.0.1:\(p)")
            print("Transmission RPC available at http://127.0.0.1:\(p)/transmission/rpc")
        } catch {
            currentPort = nil
            print("Failed to start web server:", error)
        }
    }

    func stop() {
        server.stop()
        currentPort = nil
    }

    // MARK: - Routes

    private func configureRoutesIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        // Static "app ping"
        server["/api/ping"] = { _ in
            .ok(.json([
                "status": "ok",
                "version": "0.0.3"
            ]))
        }

        // ✅ Install Transmission RPC routes ONCE.
        // If engine isn't attached yet, the handler returns 503 until attach() is called.
        rpc.install(on: server)
    }

    // MARK: - Static Web UI

    private func configureStaticWebUI() {
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("WebUI") else {
            print("WebUI folder not found in bundle resources")
            return
        }

        let indexPath = webRoot.appendingPathComponent("index.html").path

        // Serve "/" as index.html
        server["/"] = { _ in
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
                return .ok(.data(data, contentType: "text/html; charset=utf-8"))
            } catch {
                return .notFound
            }
        }

        // Serve static assets (js/css/images/etc)
        server["/:path"] = shareFilesFromDirectory(webRoot.path)
    }
}
