import Darwin
import Dispatch
import Foundation

@_silgen_name("notify_post")
func cavokNotifyPost(_ name: UnsafePointer<CChar>)

@_silgen_name("notify_register_dispatch")
func cavokNotifyListen(
    _ name: UnsafePointer<CChar>,
    _ token: UnsafeMutablePointer<Int32>,
    _ queue: DispatchQueue,
    _ handler: @escaping @convention(block) (Int32) -> Void
) -> UInt32

@_silgen_name("notify_cancel")
func cavokNotifyCancel(_ token: Int32) -> UInt32

public enum CavokNotify {
    static let ok: UInt32 = 0

    public static func post(_ name: String) {
        name.withCString { cavokNotifyPost($0) }
    }

    public static func listen(_ name: String, handler: @escaping @Sendable (Int32) -> Void) -> Int32 {
        var token: Int32 = 0
        let status = name.withCString { pointer in
            cavokNotifyListen(pointer, &token, .main) { value in
                handler(value)
            }
        }
        return status == ok ? token : 0
    }

    public static func cancel(_ token: Int32) {
        guard token != 0 else { return }
        _ = cavokNotifyCancel(token)
    }
}
