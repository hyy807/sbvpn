import Foundation
import SwiftUI
import UIKit

// ─── 卡密验证管理器 ───
// 负责设备码生成、卡密注册、验证、本地存储、自动校验

@MainActor
class LicenseManager: ObservableObject {
    public static let shared = LicenseManager()

    // 后端地址
    private let baseURL = "http://67.215.246.69:8443"

    // 本地存储 key
    private let deviceIDKey = "lx_device_id"
    private let cardKeyKey = "lx_card_key"
    private let registeredKey = "lx_registered"

    @Published public var deviceID: String = ""
    @Published public var cardKey: String = ""
    @Published public var isRegistered: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String = ""
    @Published public var showError: Bool = false
    @Published public var needReLogin: Bool = false  // 卡密失效需要重新输入

    private init() {
        loadSaved()
    }

    // ─── 设备码生成 ───
    private func generateDeviceID() -> String {
        // iOS: identifierForVendor + device model + system version → SHA256
        var raw = ""
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            raw += vendorID
        }
        raw += UIDevice.current.model
        raw += UIDevice.current.systemVersion
        raw += UIDevice.current.name

        // SHA256 hash → 取前 32 字符
        let hashed = sha256(raw)
        let deviceCode = String(hashed.prefix(32)).uppercased()
        // 格式化: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
        var formatted = ""
        for (i, ch) in deviceCode.enumerated() {
            if i > 0 && i % 4 == 0 { formatted += "-" }
            formatted += String(ch)
        }
        return formatted
    }

    private func sha256(_ string: String) -> String {
        let data = Array(string.utf8)
        var hash = [UInt32](repeating: 0, count: 8)
        let h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        hash = h
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        var msg = data
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in stride(from: 7, through: 0, by: -1) {
            msg.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xFF))
        }
        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = (UInt32(msg[chunkStart + i*4]) << 24) |
                       (UInt32(msg[chunkStart + i*4 + 1]) << 16) |
                       (UInt32(msg[chunkStart + i*4 + 2]) << 8) |
                       UInt32(msg[chunkStart + i*4 + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i-15], 7) ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3)
                let s1 = rotr(w[i-2], 17) ^ rotr(w[i-2], 19) ^ (w[i-2] >> 10)
                w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            hash[0] &+= a; hash[1] &+= b; hash[2] &+= c; hash[3] &+= d
            hash[4] &+= e; hash[5] &+= f; hash[6] &+= g; hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        return (x >> n) | (x << (32 - n))
    }

    // ─── 本地存储 ───
    private func loadSaved() {
        let savedDevice = UserDefaults.standard.string(forKey: deviceIDKey) ?? generateDeviceID()
        let savedCard = UserDefaults.standard.string(forKey: cardKeyKey) ?? ""
        let savedRegistered = UserDefaults.standard.bool(forKey: registeredKey)

        deviceID = savedDevice
        cardKey = savedCard
        isRegistered = savedRegistered && !savedCard.isEmpty

        // 首次生成就保存
        if UserDefaults.standard.string(forKey: deviceIDKey) == nil {
            UserDefaults.standard.set(savedDevice, forKey: deviceIDKey)
        }
    }

    private func saveLocally() {
        UserDefaults.standard.set(deviceID, forKey: deviceIDKey)
        UserDefaults.standard.set(cardKey, forKey: cardKeyKey)
        UserDefaults.standard.set(true, forKey: registeredKey)
    }

    private func clearLocally() {
        UserDefaults.standard.removeObject(forKey: cardKeyKey)
        UserDefaults.standard.removeObject(forKey: registeredKey)
        cardKey = ""
        isRegistered = false
    }

    // ─── 清除 app 所有数据（拉黑后调用）───
    func clearAllAppData() {
        clearLocally()
        // 清除所有 UserDefaults
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        // 清除 Documents / Library 缓存
        let dirs = [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask),
                    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)]
        for dir in dirs {
            if let url = dir.first {
                if let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    for item in items {
                        try? FileManager.default.removeItem(at: item)
                    }
                }
            }
        }
    }

    // ─── 启动时检查黑名单 ───
    // 返回: true=正常, false=被拉黑(闪退)
    // 网络失败时返回 nil → 调用方走登录流程（不放行）
    func checkBlacklist() async -> Bool {
        var req = URLRequest(url: URL(string: "\(baseURL)/api/check/\(deviceID)")!)
        req.timeoutInterval = 5  // 5 秒超时，不卡 UI
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return true // 服务器返回非200 → 放行（后续 verify 拦截）
            }
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let blacklisted = result["blacklisted"] as? Bool, blacklisted {
                clearAllAppData()
                return false
            }
            return true
        } catch {
            // 网络失败 → 放行（ATS/超时/无网）→ 后续 verify 会拦截
            return true
        }
    }

    // ─── 注册卡密 ───
    func register() async -> Bool {
        guard !cardKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            await MainActor.run {
                errorMessage = "请输入卡密"
                showError = true
            }
            return false
        }

        await MainActor.run { isLoading = true }

        let cardKeyTrimmed = cardKey.trimmingCharacters(in: .whitespaces)
        let body: [String: String] = ["device_id": deviceID, "card_key": cardKeyTrimmed]
        let url = URL(string: "\(baseURL)/api/register")!

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: req)
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            await MainActor.run { isLoading = false }

            if let ok = result["ok"] as? Bool, ok {
                // 注册成功 → 保存
                cardKey = cardKeyTrimmed
                saveLocally()
                isRegistered = true
                needReLogin = false
                return true
            } else {
                let msg = result["msg"] as? String ?? result["error"] as? String ?? "注册失败"
                let action = result["action"] as? String
                if action == "kill" {
                    // 设备被拉黑
                    clearAllAppData()
                    exit(0)
                }
                await MainActor.run {
                    errorMessage = msg
                    showError = true
                }
                return false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "网络错误: \(error.localizedDescription)"
                showError = true
            }
            return false
        }
    }

    // ─── 验证卡密（后台自动调用）───
    // 返回: .ok / .invalid / .killed
    enum VerifyResult {
        case ok
        case invalid(String)   // 卡密失效/吊销 → 需要重新输入
        case killed             // 被拉黑 → 杀app
        case networkError       // 网络问题
    }

    func verify() async -> VerifyResult {
        guard isRegistered, !cardKey.isEmpty else {
            return .invalid("未注册")
        }

        let body: [String: String] = ["device_id": deviceID, "card_key": cardKey]
        let url = URL(string: "\(baseURL)/api/verify")!

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .networkError
            }
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let ok = result["ok"] as? Bool, ok {
                return .ok
            }

            let action = result["action"] as? String
            let error = result["error"] as? String ?? ""

            if action == "kill" {
                // 被拉黑 → 清数据 + 杀app
                clearAllAppData()
                return .killed
            }

            // 卡密失效/吊销/过期 → 需要重新输入
            let msg: String
            switch error {
            case "card_invalid", "card_revoked": msg = "卡密已被吊销"
            case "expired": msg = "卡密已过期"
            case "device_not_registered": msg = "设备未注册"
            default: msg = "卡密已失效"
            }
            // 清除本地卡密（但不清设备码）
            clearLocally()
            return .invalid(msg)

        } catch {
            return .networkError
        }
    }

    // ─── 强制退出 app ───
    func killApp() {
        clearAllAppData()
        exit(0)
    }
}
import SwiftUI
import UIKit

// ─── 登录页：设备码 + 卡密输入框 ───

struct LicenseLoginView: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var copied = false

    init() {}

    public var body: some View {
        ZStack {
            // 深色背景
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)
                        Text("VPN")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 40)

                    // 设备码
                    VStack(alignment: .leading, spacing: 8) {
                        Text("设备码")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(license.deviceID)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = license.deviceID
                                withAnimation { copied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { copied = false }
                                }
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.body)
                                    .foregroundStyle(copied ? .green : .blue)
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // 卡密输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("卡密")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $license.cardKey)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // 登录按钮
                    Button {
                        Task {
                            let ok = await license.register()
                            if !ok {
                                license.needReLogin = true
                            }
                        }
                    } label: {
                        HStack {
                            if license.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("激活")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(license.isLoading)
                    .padding(.top, 8)

                    // 错误提示
                    if license.showError {
                        Text(license.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("提示", isPresented: $license.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(license.errorMessage)
        }
    }
}

// ─── 卡密失效重新登录页 ───

struct LicenseReLoginView: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var copied = false

    init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 40)

                Text(license.errorMessage.isEmpty ? "卡密已失效" : license.errorMessage)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("请输入新的卡密")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // 设备码
                HStack {
                    Text(license.deviceID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = license.deviceID
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? .green : .blue)
                    }
                }
                .padding(12)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $license.cardKey)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        let ok = await license.register()
                        if ok {
                            license.needReLogin = false
                        }
                    }
                } label: {
                    HStack {
                        if license.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("重新激活")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(license.isLoading)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// ─── 闪退屏（黑名单设备）───

struct LicenseKillView: View {
    init() {}
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("设备已被禁用")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            // 0.5 秒后强制退出
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }
}
import ApplicationLibrary
import Foundation
import Library
import SwiftUI

@main
struct Application: App {
    @UIApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate
    @StateObject private var environments = ExtensionEnvironments()
    @StateObject private var peerStore = TailscaleSSHPeerStore()
    @StateObject private var tailscaleViewModel = TailscaleStatusViewModel()
    @StateObject private var taildropSendManager = TaildropSendManager()
    @StateObject private var taildropInbox = TaildropInboxViewModel()
    @StateObject private var license = LicenseManager.shared

    // 0=checking, 1=blacklisted(kill), 2=need login, 3=need relogin, 4=ok
    @State private var licenseState: Int = 0

    init() {
        Task { @MainActor in
            await ImportedFontStore.shared.bootstrap()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch licenseState {
            case 0:
                // 启动检查中
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
                    ProgressView("正在验证...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
                .task {
                    // 1. 黑名单检查
                    let notBlacklisted = await license.checkBlacklist()
                    if !notBlacklisted {
                        licenseState = 1
                        return
                    }
                    // 2. 已注册 → 后台验证
                    if license.isRegistered {
                        let result = await license.verify()
                        switch result {
                        case .ok:
                            licenseState = 4
                        case .invalid(let msg):
                            license.errorMessage = msg
                            license.needReLogin = true
                            licenseState = 3
                        case .killed:
                            licenseState = 1
                        case .networkError:
                            // 网络问题 → 允许进入（后续 verify 会拦截）
                            licenseState = 4
                        }
                    } else {
                        // 3. 未注册 → 登录页
                        licenseState = 2
                    }
                }

            case 1:
                // 被拉黑 → 闪退屏
                LicenseKillView()

            case 2:
                // 首次登录
                LicenseLoginView()
                    .environmentObject(environments)
                    .onChange(of: license.isRegistered) { registered in
                        if registered { licenseState = 4 }
                    }

            case 3:
                // 卡密失效 → 重新登录
                LicenseReLoginView()
                    .environmentObject(environments)
                    .onChange(of: license.isRegistered) { registered in
                        if registered {
                            license.needReLogin = false
                            licenseState = 4
                        }
                    }

            default:
                // 正常进入主界面 + VPN连接后自动校验
                MainView()
                    .tailscaleStatusSubscription(tailscaleViewModel, environments: environments, peerStore: peerStore)
                    .environmentObject(environments)
                    .environmentObject(peerStore)
                    .environmentObject(tailscaleViewModel)
                    .environmentObject(taildropSendManager)
                    .environmentObject(taildropInbox)
                    .onReceive(environments.$extensionProfile) { profile in
                        guard let profile = profile else { return }
                        // 监听 VPN 连接状态
                        if profile.status == .connected {
                            // 连接后 10 秒自动校验
                            Task {
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                let result = await license.verify()
                                await MainActor.run {
                                    switch result {
                                    case .killed:
                                        licenseState = 1
                                    case .invalid(let msg):
                                        license.errorMessage = msg
                                        license.needReLogin = true
                                        licenseState = 3
                                    default:
                                        break // ok 或网络错误 → 继续
                                    }
                                }
                            }
                        }
                    }
            }
        }
    }
}
