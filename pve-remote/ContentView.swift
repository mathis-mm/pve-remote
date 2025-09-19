//
//  ContentView.swift
//  pve-remote
//
//  Created by Mat on 19/09/2025.
//

import SwiftUI
import Foundation

final class PVEClient: NSObject, URLSessionDelegate {
    let host: String
    var allowUntrusted: Bool
    private(set) var ticket: String?
    private(set) var csrfToken: String?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    init(host: String, allowUntrusted: Bool) {
        self.host = host
        self.allowUntrusted = allowUntrusted
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowUntrusted,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
    
    private func apiURL(_ path: String) -> URL { URL(string: "https://\(host):8006/api2/json\(path)")! }
    
    private func buildRequest(path: String, method: String = "GET", body: Data? = nil, isForm: Bool = false) -> URLRequest {
        var req = URLRequest(url: apiURL(path))
        req.httpMethod = method
        if let body = body { req.httpBody = body }
        if isForm { req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        if let ticket = ticket { req.setValue("PVEAuthCookie=\(ticket)", forHTTPHeaderField: "Cookie") }
        if method != "GET", let csrf = csrfToken { req.setValue(csrf, forHTTPHeaderField: "CSRFPreventionToken") }
        req.timeoutInterval = 10
        return req
    }
    
    private struct APIResponse<T: Decodable>: Decodable { let data: T }
    private struct LoginData: Decodable {
        let ticket: String
        let CSRFPreventionToken: String
        let username: String
    }
    struct NodeInfo: Decodable, Identifiable { let node: String; let status: String?; var id: String { node } }
    
    func login(username: String, password: String, realm: String) async throws {
        let form = "username=\(urlEncode(username))&password=\(urlEncode(password))&realm=\(urlEncode(realm))"
        let req = buildRequest(path: "/access/ticket", method: "POST", body: form.data(using: .utf8), isForm: true)
        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(APIResponse<LoginData>.self, from: data)
        self.ticket = decoded.data.ticket
        self.csrfToken = decoded.data.CSRFPreventionToken
    }
    
    func fetchNodes() async throws -> [NodeInfo] {
        let req = buildRequest(path: "/nodes")
        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)
        let decoded = try JSONDecoder().decode(APIResponse<[NodeInfo]>.self, from: data)
        return decoded.data
    }
    
    func rebootNode(_ node: String) async throws {
        let body = "command=reboot".data(using: .utf8)
        let req = buildRequest(path: "/nodes/\(node)/status", method: "POST", body: body, isForm: true)
        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)
    }
    
    func shutdownNode(_ node: String) async throws {
        let body = "command=shutdown".data(using: .utf8)
        let req = buildRequest(path: "/nodes/\(node)/status", method: "POST", body: body, isForm: true)
        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)
    }
    
    func checkVersion() async throws -> String {
        let req = buildRequest(path: "/version")
        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)
        struct Version: Decodable { let version: String }
        let decoded = try JSONDecoder().decode(APIResponse<Version>.self, from: data)
        return decoded.data.version
    }
    
    private func validate(resp: URLResponse, data: Data) throws {
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PVEClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
    }
    
    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

struct ContentView: View {
    @State private var host: String = ""
    @State private var username: String = "root"
    @State private var password: String = ""
    @State private var realm: String = "pam"
    @State private var allowUntrusted: Bool = true
    
    @State private var client: PVEClient?
    @State private var connected: Bool = false
    @State private var statusMessage: String = ""
    @State private var isBusy: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    @State private var nodes: [PVEClient.NodeInfo] = []
    @State private var selectedNode: String = ""
    
    private var selectedNodeIsOnline: Bool? {
        guard let status = nodes.first(where: { $0.node == selectedNode })?.status?.lowercased() else { return nil }
        return status == "online"
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                if connected {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .padding(.bottom, 2)
                        Text("Proxmox Dashboard")
                            .font(.title).fontWeight(.semibold)
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    
                    VStack(spacing: 16) {
                        if nodes.isEmpty {
                            Text("No nodes found").foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            VStack(alignment: .center, spacing: 8) {
                                Text("Node")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Picker("Node", selection: $selectedNode) {
                                    ForEach(nodes) { item in
                                        Text(item.node).tag(item.node)
                                    }
                                }
                                .pickerStyle(.segmented)
                                
                                StatusBadge(isOnline: selectedNodeIsOnline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        
                        VStack(spacing: 12) {
                            Button(action: reboot) {
                                Label("Reboot Node", systemImage: "arrow.clockwise.circle.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(DashboardButton(color: .orange))
                            
                            Button(action: shutdown) {
                                Label("Shutdown Node", systemImage: "power.circle.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(DashboardButton(color: .red))
                            
                            Button(action: logout) {
                                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(DashboardButton(color: .gray))
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 520)
                    
                    Spacer(minLength: 32)
                } else {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .padding(.bottom, 2)
                        Text("Proxmox Remote")
                            .font(.title).fontWeight(.semibold)
                        Text("Connect to your Proxmox VE server")
                            .foregroundColor(.secondary).font(.subheadline)
                    }
                    .padding(.top, 8)
                    
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            TextField("Host (e.g. 192.168.1.10)", text: $host)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            SecureField("Password", text: $password)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            TextField("Realm (pam, pve, ldap)", text: $realm)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        
                        Toggle("Allow self-signed certificate", isOn: $allowUntrusted)
                            .tint(.blue)
                        
                        Button(action: connect) {
                            Label(isBusy ? "Connecting…" : "Connect", systemImage: isBusy ? "hourglass" : "paperplane.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(DashboardButton(color: .blue))
                        .disabled(isBusy)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 520)
                    
                    Spacer(minLength: 32)
                }
            }
            .padding(.vertical)
            .overlay(alignment: .top) {
                if isBusy { ProgressView().progressViewStyle(.circular).padding(.top, 8) }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        .animation(.easeInOut, value: connected)
    }
    
    private func connect() {
        guard !host.isEmpty, !username.isEmpty, !password.isEmpty, !realm.isEmpty else {
            show("Please fill all fields")
            return
        }
        isBusy = true
        statusMessage = ""
        let client = PVEClient(host: host, allowUntrusted: allowUntrusted)
        self.client = client
        Task {
            do {
                try await client.login(username: username, password: password, realm: realm)
                let version = try? await client.checkVersion()
                let list = try await client.fetchNodes()
                await MainActor.run {
                    nodes = list
                    selectedNode = list.first?.node ?? ""
                    connected = true
                    statusMessage = "Connected • Proxmox \(version ?? "")"
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    show(error.localizedDescription)
                }
            }
        }
    }
    
    private func reboot() {
        guard let client, !selectedNode.isEmpty else { return }
        isBusy = true
        statusMessage = "Rebooting \(selectedNode)…"
        Task {
            do {
                try await client.rebootNode(selectedNode)
                await MainActor.run { statusMessage = "Reboot requested"; isBusy = false }
            } catch {
                await MainActor.run { isBusy = false; show(error.localizedDescription) }
            }
        }
    }
    
    private func shutdown() {
        guard let client, !selectedNode.isEmpty else { return }
        isBusy = true
        statusMessage = "Shutting down \(selectedNode)…"
        Task {
            do {
                try await client.shutdownNode(selectedNode)
                await MainActor.run { statusMessage = "Shutdown requested"; isBusy = false }
            } catch {
                await MainActor.run { isBusy = false; show(error.localizedDescription) }
            }
        }
    }
    
    private func logout() {
        client = nil
        connected = false
        statusMessage = ""
        nodes = []
        selectedNode = ""
    }
    
    private func show(_ message: String) {
        errorMessage = message
        showError = true
    }
}

struct DashboardButton: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [color, color.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
            )
            .cornerRadius(14)
            .shadow(color: color.opacity(0.25), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}

struct PulsatingDot: View {
    var color: Color
    @State private var animate = false
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 18, height: 18)
                .scaleEffect(animate ? 1.6 : 1.0)
                .opacity(animate ? 0.0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

struct StatusBadge: View {
    var isOnline: Bool?
    var body: some View {
        let color: Color = {
            guard let isOnline else { return .gray }
            return isOnline ? .green : .red
        }()
        let label: String = {
            guard let isOnline else { return "Unknown" }
            return isOnline ? "Online" : "Offline"
        }()
        HStack(spacing: 8) {
            PulsatingDot(color: color)
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(color.opacity(0.12))
        .cornerRadius(20)
    }
}
