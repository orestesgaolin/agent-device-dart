//
//  RunnerBSDSocketServer.swift
//  AgentDeviceRunnerUITests
//
//  HTTP/1.1 server backed by raw POSIX sockets. Used in place of
//  NWListener on iOS physical devices because Apple's Network framework
//  wraps listeners in NECP (Network Extension Content Policy), which
//  hides the bound port from any external transport — including the
//  CoreDevice IPv6 tunnel that the host uses to reach the device.
//  Plain socket(2)/bind(2)/listen(2)/accept(2) calls bypass NECP
//  entirely and the listener becomes reachable through the tunnel.
//
//  The server understands just enough HTTP to satisfy the agent-device
//  runner protocol: one POST request per connection, Content-Length
//  body framing, JSON request body in / JSON response body out.
//

import Foundation
import Darwin

final class RunnerBSDSocketServer {
  enum SocketError: Error {
    case create(Int32)
    case setsockopt(Int32)
    case bind(Int32)
    case listen(Int32)
  }

  let host: String
  private(set) var port: UInt16
  private let onRequest: (Data) -> (status: Int, body: Data, shouldFinish: Bool)
  private let maxRequestBytes: Int
  private var serverFd: Int32 = -1
  private var acceptThread: Thread?
  private var stopRequested = false

  init(
    host: String,
    port: UInt16,
    maxRequestBytes: Int,
    onRequest: @escaping (Data) -> (status: Int, body: Data, shouldFinish: Bool)
  ) {
    self.host = host
    self.port = port
    self.maxRequestBytes = maxRequestBytes
    self.onRequest = onRequest
  }

  /// Open the listening socket. Throws on bind/listen failure. After a
  /// successful return, [port] reflects the actual bound port.
  ///
  /// We bind on the IPv6 wildcard `::` with `IPV6_V6ONLY = 0`, which on
  /// Darwin gives a dual-stack listener that accepts BOTH IPv4 and IPv6
  /// connections on every interface — including loopback (for in-device
  /// callers) AND the CoreDevice IPv6 tunnel (for host-side reach over
  /// USB). The previous IPv4-loopback-only bind was invisible to the
  /// CoreDevice tunnel because that tunnel routes from a non-loopback
  /// remote IPv6 address.
  func start() throws {
    let fd = socket(AF_INET6, SOCK_STREAM, 0)
    guard fd >= 0 else { throw SocketError.create(errno) }

    var yes: Int32 = 1
    if setsockopt(
      fd, SOL_SOCKET, SO_REUSEADDR,
      &yes, socklen_t(MemoryLayout<Int32>.size)
    ) < 0 {
      let err = errno
      close(fd)
      throw SocketError.setsockopt(err)
    }

    // Disable IPV6_V6ONLY so this single listener also accepts IPv4
    // connections (over the v4-mapped-v6 form ::ffff:x.y.z.w).
    var off: Int32 = 0
    if setsockopt(
      fd, IPPROTO_IPV6, IPV6_V6ONLY,
      &off, socklen_t(MemoryLayout<Int32>.size)
    ) < 0 {
      let err = errno
      close(fd)
      throw SocketError.setsockopt(err)
    }

    var addr = sockaddr_in6()
    addr.sin6_family = sa_family_t(AF_INET6)
    addr.sin6_port = port.bigEndian
    addr.sin6_addr = in6addr_any
    let addrSize = socklen_t(MemoryLayout<sockaddr_in6>.size)

    let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        bind(fd, sockaddrPtr, addrSize)
      }
    }
    if bindResult < 0 {
      let err = errno
      close(fd)
      throw SocketError.bind(err)
    }

    if listen(fd, 8) < 0 {
      let err = errno
      close(fd)
      throw SocketError.listen(err)
    }

    if port == 0 {
      var bound = sockaddr_in6()
      var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
      let r = withUnsafeMutablePointer(to: &bound) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          getsockname(fd, $0, &len)
        }
      }
      if r == 0 {
        port = UInt16(bigEndian: bound.sin6_port)
      }
    }

    serverFd = fd
    let thread = Thread { [weak self] in self?.acceptLoop() }
    thread.name = "agent-device.runner.bsd-accept"
    thread.start()
    acceptThread = thread
  }

  /// Best-effort shutdown: stop the accept loop and close the socket.
  func stop() {
    stopRequested = true
    let fd = serverFd
    serverFd = -1
    if fd >= 0 { close(fd) }
  }

  // MARK: - Accept + request handling

  private func acceptLoop() {
    while !stopRequested && serverFd >= 0 {
      var clientAddr = sockaddr_in()
      var len = socklen_t(MemoryLayout<sockaddr_in>.size)
      let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          accept(serverFd, $0, &len)
        }
      }
      if clientFd < 0 {
        if stopRequested { return }
        // Accept can be interrupted (EINTR) or fail benignly when the
        // socket gets closed; either way, loop and re-check stopRequested.
        continue
      }
      // Handle each connection on its own thread so a slow request
      // doesn't block the next one.
      Thread { [weak self] in self?.handle(clientFd: clientFd) }.start()
    }
  }

  private func handle(clientFd: Int32) {
    defer { close(clientFd) }
    guard let body = readRequestBody(clientFd: clientFd) else {
      sendStatus(clientFd, status: 400, bodyText: "{\"ok\":false,\"error\":{\"message\":\"bad request\"}}")
      return
    }
    if body.count > maxRequestBytes {
      sendStatus(clientFd, status: 413, bodyText: "{\"ok\":false,\"error\":{\"message\":\"request too large\"}}")
      return
    }
    let result = onRequest(body)
    writeHttpResponse(clientFd, status: result.status, body: result.body)
    // Caller decides whether the runner should exit (shutdown command).
    // We don't act on `shouldFinish` here — RunnerTests owns that.
  }

  /// Read until we have the full HTTP request (headers + Content-Length
  /// bytes of body). Returns the body bytes only; the caller doesn't
  /// care about headers beyond Content-Length.
  private func readRequestBody(clientFd: Int32) -> Data? {
    var buf = Data()
    let chunkSize = 4096
    var chunk = [UInt8](repeating: 0, count: chunkSize)
    var headerEnd: Int? = nil
    var contentLength: Int? = nil

    while true {
      let n = chunk.withUnsafeMutableBufferPointer {
        Darwin.read(clientFd, $0.baseAddress, chunkSize)
      }
      if n <= 0 { return nil }
      buf.append(chunk, count: n)
      if buf.count > maxRequestBytes + 8192 { return nil } // headers + body cap

      if headerEnd == nil {
        if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
          headerEnd = range.upperBound
          let headerBytes = buf.subdata(in: 0..<range.lowerBound)
          let headerStr = String(decoding: headerBytes, as: UTF8.self)
          for line in headerStr.split(separator: "\r\n") {
            let parts = line.split(
              separator: ":", maxSplits: 1
            ).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
              contentLength = Int(parts[1])
              break
            }
          }
          if contentLength == nil { return Data() }
        }
      }
      if let end = headerEnd, let len = contentLength {
        if buf.count >= end + len {
          return buf.subdata(in: end..<(end + len))
        }
      }
    }
  }

  private func writeHttpResponse(_ clientFd: Int32, status: Int, body: Data) {
    let reason = status == 200 ? "OK" : (status == 400 ? "Bad Request" :
      (status == 413 ? "Payload Too Large" : "Server Error"))
    let header =
      "HTTP/1.1 \(status) \(reason)\r\n" +
      "Content-Type: application/json\r\n" +
      "Content-Length: \(body.count)\r\n" +
      "Connection: close\r\n" +
      "\r\n"
    let headerData = Data(header.utf8)
    writeAll(clientFd, headerData)
    if !body.isEmpty {
      writeAll(clientFd, body)
    }
  }

  private func sendStatus(_ clientFd: Int32, status: Int, bodyText: String) {
    writeHttpResponse(clientFd, status: status, body: Data(bodyText.utf8))
  }

  private func writeAll(_ clientFd: Int32, _ data: Data) {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var ptr = raw.baseAddress
      var remaining = data.count
      while remaining > 0 {
        let written = Darwin.write(clientFd, ptr, remaining)
        if written <= 0 { return }
        ptr = ptr?.advanced(by: written)
        remaining -= written
      }
    }
  }
}
