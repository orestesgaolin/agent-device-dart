//
//  RunnerTests.swift
//  AgentDeviceRunnerUITests
//
//  Created by Michał Pierzchała on 30/01/2026.
//

import XCTest
import Network
#if canImport(UIKit)
import UIKit
typealias RunnerImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias RunnerImage = NSImage
#endif

final class RunnerTests: XCTestCase {
  enum RunnerErrorDomain {
    static let general = "AgentDeviceRunner"
    static let exception = "AgentDeviceRunner.NSException"
  }

  enum RunnerErrorCode {
    static let noResponseFromMainThread = 1
    static let commandReturnedNoResponse = 2
    static let mainThreadExecutionTimedOut = 3
    static let objcException = 1
  }

  static let springboardBundleId = "com.apple.springboard"
  static let defaultRecordingFps: Int32 = 15
  var listener: NWListener?
  var bsdServer: RunnerBSDSocketServer?
  var doneExpectation: XCTestExpectation?
  let app = XCUIApplication()
  lazy var springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleId)
  var currentApp: XCUIApplication?
  var currentBundleId: String?
  let maxRequestBytes = 2 * 1024 * 1024
  let maxSnapshotElements = 600
  let fastSnapshotLimit = 300
  let mainThreadExecutionTimeout: TimeInterval = 30
  let appExistenceTimeout: TimeInterval = 30
  let retryCooldown: TimeInterval = 0.2
  let postSnapshotInteractionDelay: TimeInterval = 0.2
  let firstInteractionAfterActivateDelay: TimeInterval = 0.25
  let scrollInteractionIdleTimeoutDefault: TimeInterval = 1.0
  let tvRemoteDoublePressDelayDefault: TimeInterval = 0.0
  let minRecordingFps = 1
  let maxRecordingFps = 120
  let minRecordingQuality = 5
  let maxRecordingQuality = 10
  var needsPostSnapshotInteractionDelay = false
  var needsFirstInteractionDelay = false
  var activeRecording: ScreenRecorder?
  let interactiveTypes: Set<XCUIElement.ElementType> = [
    .button,
    .cell,
    .checkBox,
    .collectionView,
    .link,
    .menuItem,
    .picker,
    .searchField,
    .segmentedControl,
    .slider,
    .stepper,
    .switch,
    .tabBar,
    .textField,
    .secureTextField,
    .textView
  ]
  // Keep blocker actions narrow to avoid false positives from generic hittable containers.
  let actionableTypes: Set<XCUIElement.ElementType> = [
    .button,
    .cell,
    .link,
    .menuItem,
    .checkBox,
    .switch
  ]

  // MARK: - XCTest Entry

  override func setUp() {
    continueAfterFailure = true
  }

  @MainActor
  func testCommand() throws {
    doneExpectation = expectation(description: "agent-device command handled")
    app.launch()
    currentApp = app
    let queue = DispatchQueue(label: "agent-device.runner")
    let desiredPort = RunnerEnv.resolvePort()
    NSLog("AGENT_DEVICE_RUNNER_DESIRED_PORT=%d", desiredPort)

    // Physical iOS device: use a raw BSD-socket HTTP server. NWListener
    // on iOS device gets wrapped by NECP (Network Extension Content
    // Policy), which hides the bound port from lockdown's port-relay
    // service so iproxy / CoreDevice tunnel can't reach it. POSIX
    // socket(2)/bind(2)/listen(2)/accept(2) bypasses NECP and the
    // listener becomes reachable.
    //
    // Simulator + macOS: NWListener works (the sim shares the host
    // network stack; macOS doesn't sandbox UI tests this way). Keep
    // it for those targets so we don't lose framing/QoS niceties.
    #if targetEnvironment(simulator) || os(macOS)
      try startNWListener(desiredPort: desiredPort, queue: queue)
    #else
      try startBSDSocketServer(desiredPort: desiredPort)
    #endif

    guard let expectation = doneExpectation else {
      XCTFail("runner expectation was not initialized")
      return
    }
    NSLog("AGENT_DEVICE_RUNNER_WAITING")
    let result = XCTWaiter.wait(for: [expectation], timeout: 24 * 60 * 60)
    NSLog("AGENT_DEVICE_RUNNER_WAIT_RESULT=%@", String(describing: result))
    bsdServer?.stop()
    if result != .completed {
      XCTFail("runner wait ended with \(result)")
    }
  }

  private func startNWListener(
    desiredPort: UInt16,
    queue: DispatchQueue
  ) throws {
    listener = try makeRunnerListener(desiredPort: desiredPort)
    listener?.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        NSLog("AGENT_DEVICE_RUNNER_LISTENER_READY")
        if let listenerPort = self?.listener?.port {
          NSLog("AGENT_DEVICE_RUNNER_PORT=%d", listenerPort.rawValue)
        } else {
          NSLog("AGENT_DEVICE_RUNNER_PORT_NOT_SET")
        }
      case .failed(let error):
        NSLog("AGENT_DEVICE_RUNNER_LISTENER_FAILED=%@", String(describing: error))
        self?.doneExpectation?.fulfill()
      default:
        break
      }
    }
    listener?.newConnectionHandler = { [weak self] conn in
      conn.start(queue: queue)
      self?.handle(connection: conn)
    }
    listener?.start(queue: queue)
  }

  private func startBSDSocketServer(desiredPort: UInt16) throws {
    let server = RunnerBSDSocketServer(
      host: "127.0.0.1",
      port: desiredPort,
      maxRequestBytes: maxRequestBytes
    ) { [weak self] body in
      guard let self = self else {
        let payload = "{\"ok\":false,\"error\":{\"message\":\"runner gone\"}}"
        return (500, Data(payload.utf8), false)
      }
      let result = self.handleRequestBodyForBSD(body)
      return (result.status, result.body, result.shouldFinish)
    }
    do {
      try server.start()
    } catch {
      NSLog("AGENT_DEVICE_RUNNER_LISTENER_FAILED=%@", String(describing: error))
      doneExpectation?.fulfill()
      throw error
    }
    bsdServer = server
    NSLog("AGENT_DEVICE_RUNNER_LISTENER_READY")
    NSLog("AGENT_DEVICE_RUNNER_PORT=%d", server.port)
  }

  /// BSD-socket variant of `handleRequestBody`. Mirrors the existing
  /// NWConnection path: decode the JSON command, execute, encode the
  /// response. Returns (status, body, shouldFinish) so the BSD server
  /// can fulfil the doneExpectation when the shutdown command lands.
  func handleRequestBodyForBSD(_ body: Data)
    -> (status: Int, body: Data, shouldFinish: Bool)
  {
    guard let json = String(data: body, encoding: .utf8),
          let data = json.data(using: .utf8) else {
      let r = Response(ok: false, error: ErrorPayload(message: "invalid json"))
      return (400, encodeResponseBody(r), false)
    }
    do {
      let command = try JSONDecoder().decode(Command.self, from: data)
      let response = try execute(command: command)
      let isShutdown = command.command == .shutdown
      if isShutdown {
        // NWConnection variant fulfils on the send-completion callback;
        // the BSD path doesn't have that, so we do it after returning
        // the response so the body still gets written.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.bsdServer?.stop()
          self?.doneExpectation?.fulfill()
        }
      }
      return (200, encodeResponseBody(response), isShutdown)
    } catch {
      let r = Response(ok: false, error: ErrorPayload(message: "\(error)"))
      return (500, encodeResponseBody(r), false)
    }
  }

  private func encodeResponseBody(_ response: Response) -> Data {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(response) {
      return data
    }
    return Data("{}".utf8)
  }

  private func makeRunnerListener(desiredPort: UInt16) throws -> NWListener {
    if desiredPort > 0, let port = NWEndpoint.Port(rawValue: desiredPort) {
      // Pin every variant to 127.0.0.1 explicitly. On macOS this was
      // already the case; on iOS the previous `NWListener(using: .tcp,
      // on: port)` form left interface selection up to Network.framework,
      // which under a UITest sandbox routes through NECP. NECP doesn't
      // register the listener with lockdown's port-forwarding service
      // (visible as `setsockopt SO_NECP_LISTENUUID failed` in the log),
      // so the bound port is invisible to host-side iproxy / CoreDevice
      // tunnel even though the runner thinks it's listening. Explicit
      // loopback binding skips NECP wrapping and the listener becomes
      // reachable through usbmux.
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
      return try NWListener(using: parameters)
    }
    return try NWListener(using: .tcp)
  }
}
