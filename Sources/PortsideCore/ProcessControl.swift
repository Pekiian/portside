import Foundation

public enum KillOutcome: Equatable {
    case terminated   // died after SIGTERM
    case forced       // needed SIGKILL
    case failed(String)
}

public enum ProcessControl {
    /// SIGTERM, wait up to 3s for the process to exit, then SIGKILL if it's
    /// still alive. `force` skips straight to SIGKILL.
    // ponytail: liveness via kill(pid,0) is the proxy for "port still bound";
    // upgrade to a targeted lsof re-check if a fork-and-rebind ever matters.
    public static func kill(pid: Int, force: Bool = false) async -> KillOutcome {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        guard Foundation.kill(pid_t(pid), signal) == 0 else {
            return .failed(String(cString: strerror(errno)))
        }
        if force { return .forced }

        for _ in 0..<30 {                       // 30 * 100ms = 3s
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !isAlive(pid) { return .terminated }
        }
        guard isAlive(pid) else { return .terminated }

        guard Foundation.kill(pid_t(pid), SIGKILL) == 0 else {
            return .failed(String(cString: strerror(errno)))
        }
        return .forced
    }

    public static func isAlive(_ pid: Int) -> Bool {
        // kill(pid, 0): 0 = alive, ESRCH = gone, EPERM = alive but not ours
        if Foundation.kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}
