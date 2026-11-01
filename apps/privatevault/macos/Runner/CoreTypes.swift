import Foundation

enum CorePhase: String, Codable { case stopped, starting, ready, stopping, failed }

struct FixtureResult: Codable {
    let name: String
    let byteLength: Int
    let sha256: String
    let bytesBase64: String
}

struct CoreSnapshot: Codable {
    let phase: CorePhase
    let message: String
    var revision: Int = 0
    var version: String? = nil
    var errorCode: String? = nil
    var fixture: FixtureResult? = nil

    func dictionary() -> [String: Any] {
        // Snapshots contain display data only, never connections or credentials.
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }
}

struct CoreFailure: Error {
    let code: String
    let message: String

    static let cancelled = Self(code: "cancelled", message: "启动已取消，可以重新启动。")
    static let missingCore = Self(code: "missing_core", message: "缺少本机服务文件，请重新准备开发版。")
    static let integrity = Self(code: "integrity_mismatch", message: "服务文件校验不通过，已阻止启动。")
    static let incompatible = Self(code: "incompatible_core", message: "本机服务版本或接口不符合本开发版要求。")
    static let foreign = Self(code: "ownership_unverified", message: "无法确认已有服务属于本应用，未接管或关闭它。")
    static let busy = Self(code: "instance_busy", message: "另一窗口正在使用本机服务，请先关闭它。")
    static let timeout = Self(code: "start_timeout", message: "本机服务未能及时就绪，请重试。")
    static let auth = Self(code: "authentication_failed", message: "本机服务认证未通过，未开放文件读取。")
    static let fixture = Self(code: "fixture_mismatch", message: "测试图片读取校验未通过，请重新准备开发版。")
    static let storage = Self(code: "private_storage_failed", message: "无法使用本应用的私有工作区。")
    static let launch = Self(code: "launch_failed", message: "本机服务未能启动，请检查开发环境与应用签名。")
    static let stopped = Self(code: "not_ready", message: "请先启动本机服务。")
    static let stopFailed = Self(code: "stop_failed", message: "尚未确认本机服务退出，已保留恢复信息。")
}
