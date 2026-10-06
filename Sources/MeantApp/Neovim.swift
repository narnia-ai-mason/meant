import Darwin
import Foundation
import MeantCore

enum NeovimApplyResult {
  case replaced
  case unavailable
  case skipped
}

/// The nvim the person is typing in, found the way emote finds it: the socket under
/// `$TMPDIR/nvim.<user>/`, limited to processes under the frontmost terminal.
enum Neovim {
  static func mode(appPID: pid_t, bundlePath: String?) -> String? {
    target(appPID: appPID, bundlePath: bundlePath, screen: nil, timeout: 0.08, distinct: true)?.state.mode
  }

  static func apply(
    typed: String,
    replacement: String,
    trigger: String?,
    screen: String?,
    appPID: pid_t,
    bundlePath: String?
  ) -> NeovimApplyResult {
    guard var found = target(appPID: appPID, bundlePath: bundlePath, screen: screen, timeout: 0.4, distinct: false) else {
      return .unavailable
    }
    if !NeovimMode.isTyping(found.state.mode) {
      return found.state.mode.first == "t" ? .unavailable : .skipped
    }
    if found.state.blocking || !found.state.editable {
      return .skipped
    }
    // Commit or cancel a Hangul composition so the first jamo is in the buffer.
    if !InputSource.isASCIILayout {
      InputSource.select(.koreanToEnglish)
      RunLoop.current.run(until: Date().addingTimeInterval(0.08))
      guard let refreshed = target(appPID: appPID, bundlePath: bundlePath, screen: screen, timeout: 0.4, distinct: false) else {
        return .unavailable
      }
      found = refreshed
      if !NeovimMode.isTyping(found.state.mode) || found.state.blocking || !found.state.editable {
        return .skipped
      }
    }
    guard
      let edit = NeovimEditPlan.plan(
        line: found.state.line,
        cursorByte: found.state.col,
        typed: typed,
        replacement: replacement,
        trigger: trigger
      )
    else { return .unavailable }
    return write(edit, to: found) ? .replaced : .unavailable
  }

  private struct Instance {
    var socket: String
    var pid: pid_t
  }

  private struct Target {
    var socket: String
    var state: State
  }

  struct State: Decodable {
    var mode: String
    var blocking: Bool
    var buffer: Int
    var tick: Int
    var editable: Bool
    var line: String
    var row: Int
    var col: Int
    var seen: Double?
    var focused: Bool?
  }

  private static func target(
    appPID: pid_t,
    bundlePath: String?,
    screen: String?,
    timeout: TimeInterval,
    distinct: Bool
  ) -> Target? {
    let all = instances()
    var candidates = all.filter { runs(under: appPID, bundlePath: bundlePath, pid: $0.pid) }
    if candidates.isEmpty {
      candidates = all.filter { ancestors(of: $0.pid).contains { executableName($0) == "tmux" } }
    }
    guard !candidates.isEmpty else { return nil }
    let sockets = candidates.map(\.socket)
    let states = LockedValues(count: sockets.count)
    DispatchQueue.concurrentPerform(iterations: sockets.count) { index in
      states.set(index, readState(sockets[index], timeout: timeout))
    }
    var targets = zip(candidates, states.values).compactMap { instance, state in
      state.map { Target(socket: instance.socket, state: $0) }
    }
    targets.removeAll { $0.state.focused == false }
    if targets.contains(where: { $0.state.focused == true }) {
      targets.removeAll { $0.state.focused != true }
    }
    if let screen, !screen.isEmpty {
      let shown = targets.filter { isShown($0.state.line, on: screen) }
      if !shown.isEmpty { targets = shown }
    }
    let focused = targets.filter { $0.state.focused == true }
    if focused.count == 1 { return focused[0] }
    let pool = focused.isEmpty ? targets : focused
    if distinct, pool.count > 1, Set(pool.map { $0.state.seen ?? 0 }).count < 2 {
      return nil
    }
    return pool.max { ($0.state.seen ?? 0) < ($1.state.seen ?? 0) }
  }

  private static func readState(_ socket: String, timeout: TimeInterval) -> State? {
    guard let connection = RPCConnection(path: socket, timeout: timeout),
      let json = connection.call("nvim_exec_lua", [.string(stateScript), .array([])])?.string,
      let data = json.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(State.self, from: data)
  }

  private static func write(_ edit: NeovimEdit, to target: Target) -> Bool {
    guard let connection = RPCConnection(path: target.socket, timeout: 0.4) else { return false }
    let state = target.state
    let arguments: [MessagePack] = [
      .int(Int64(state.buffer)), .int(Int64(state.tick)), .int(Int64(state.row)),
      .int(Int64(edit.startByte)), .int(Int64(edit.endByte)), .string(edit.text),
    ]
    return connection.call("nvim_exec_lua", [.string(replaceScript), .array(arguments)])?.bool == true
  }

  private static func isShown(_ line: String, on screen: String) -> Bool {
    let sample = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    guard sample.count >= 4 else { return true }
    return screen.contains(sample)
  }

  private static func instances() -> [Instance] {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nvim.\(NSUserName())")
    guard let sessions = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
    return sessions.flatMap { session -> [Instance] in
      let folder = root.appendingPathComponent(session)
      let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      return names.compactMap { name in
        let parts = name.split(separator: ".")
        guard parts.count >= 2, parts[0] == "nvim", let pid = pid_t(parts[1]), kill(pid, 0) == 0 else {
          return nil
        }
        return Instance(socket: folder.appendingPathComponent(name).path, pid: pid)
      }
    }
  }

  private static func runs(under appPID: pid_t, bundlePath: String?, pid: pid_t) -> Bool {
    ancestors(of: pid).contains { ancestor in
      ancestor == appPID || (bundlePath.map { executablePath(ancestor)?.hasPrefix($0 + "/") ?? false } ?? false)
    }
  }

  private static func ancestors(of pid: pid_t) -> [pid_t] {
    var chain: [pid_t] = []
    var current = pid
    for _ in 0..<32 {
      guard let parent = parentPID(current), parent > 1 else { break }
      chain.append(parent)
      current = parent
    }
    return chain
  }

  private static func parentPID(_ pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
  }

  private static func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func executableName(_ pid: pid_t) -> String? {
    executablePath(pid).map { URL(fileURLWithPath: $0).lastPathComponent }
  }

  private static let stateScript = """
    if not vim.g.meant_hooked then
      vim.g.meant_hooked = true
      local group = vim.api.nvim_create_augroup('meant_input', { clear = true })
      local clock = vim.uv or vim.loop
      local function now()
        local s, us = clock.gettimeofday()
        return s + us / 1e6
      end
      vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = function()
        vim.g.meant_focused = true
        vim.g.meant_seen = now()
      end })
      vim.api.nvim_create_autocmd('FocusLost', { group = group, callback = function()
        vim.g.meant_focused = false
      end })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'ModeChanged' }, {
        group = group, callback = function() vim.g.meant_seen = now() end,
      })
    end
    local api = vim.api
    local cursor = api.nvim_win_get_cursor(0)
    local mode = api.nvim_get_mode()
    return vim.json.encode({
      mode = mode.mode, blocking = mode.blocking,
      buffer = api.nvim_get_current_buf(), tick = api.nvim_buf_get_changedtick(0),
      editable = vim.bo.modifiable and vim.bo.buftype == '',
      line = api.nvim_get_current_line(), row = cursor[1], col = cursor[2],
      seen = vim.g.meant_seen, focused = vim.g.meant_focused,
    })
    """

  private static let replaceScript = """
    local buffer, tick, row, start_byte, end_byte, text = ...
    local api = vim.api
    if api.nvim_get_current_buf() ~= buffer or api.nvim_buf_get_changedtick(buffer) ~= tick then
      return false
    end
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    if mode ~= 'i' and mode ~= 'R' then return false end
    if api.nvim_win_get_cursor(0)[1] ~= row then return false end
    api.nvim_buf_set_text(buffer, row - 1, start_byte, row - 1, end_byte, { text })
    api.nvim_win_set_cursor(0, { row, start_byte + #text })
    return true
    """
}

private final class LockedValues: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Neovim.State?]

  init(count: Int) { storage = Array(repeating: nil, count: count) }

  func set(_ index: Int, _ state: Neovim.State?) {
    lock.lock()
    storage[index] = state
    lock.unlock()
  }

  var values: [Neovim.State?] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

/// One blocking MessagePack-RPC connection. A busy nvim times out instead of stalling meant.
private final class RPCConnection {
  private let descriptor: Int32
  private var nextID: Int64 = 1
  private var buffer: [UInt8] = []

  init?(path: String, timeout: TimeInterval) {
    let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard socket >= 0 else { return nil }
    guard Self.connect(socket, path: path, timeout: timeout) else {
      close(socket)
      return nil
    }
    var time = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
    setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    descriptor = socket
  }

  deinit { close(descriptor) }

  func call(_ method: String, _ parameters: [MessagePack]) -> MessagePack? {
    let id = nextID
    nextID += 1
    let request = MessagePack.array([.int(0), .int(id), .string(method), .array(parameters)]).encoded()
    let sent = request.withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, 0) }
    guard sent == request.count else { return nil }
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
      while let (message, length) = (try? MessagePack.decode(buffer)) ?? nil {
        buffer.removeFirst(length)
        guard let parts = message.array, parts.count == 4, parts[0].int == 1, parts[1].int == id else { continue }
        return parts[2].isNull ? parts[3] : nil
      }
      let count = recv(descriptor, &chunk, chunk.count, 0)
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  private static func connect(_ socket: Int32, path: String, timeout: TimeInterval) -> Bool {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else { return false }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      raw.copyBytes(from: pathBytes)
      raw[pathBytes.count] = 0
    }
    let flags = fcntl(socket, F_GETFL, 0)
    _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if connected != 0 && errno != EINPROGRESS {
      return false
    }
    if connected != 0 {
      var waiting = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
      guard poll(&waiting, 1, Int32(timeout * 1000)) > 0 else { return false }
      var error: Int32 = 0
      var size = socklen_t(MemoryLayout<Int32>.size)
      getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &size)
      guard error == 0 else { return false }
    }
    _ = fcntl(socket, F_SETFL, flags)
    return true
  }
}
