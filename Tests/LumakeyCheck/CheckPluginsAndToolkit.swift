import AppKit
import Foundation
import LumakeyCore
import Vision

func testV070PluginsAndToolkit() throws {
    try verifyPluginV2LifecycleAndWatcher()
    try verifyMCPServerV2Subprocess()
    try verifyDevToolkitAndSnippets()
    print("[ok] v0.7.0 PluginSystem v2 (view/config/state/watcher/gallery/MCP) + DevToolkitEngine + SnippetStore")
}

private func verifyPluginV2LifecycleAndWatcher() throws {
    let tmp = try makeTempDir("v070-plugins")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    // 1. Hot-reload watcher setup before creating plugins
    let watcherHit = DispatchSemaphore(value: 0)
    let watcher = PluginDirectoryWatcher(directoryURL: pluginsRoot, debounceInterval: 0.15) {
        watcherHit.signal()
    }
    check(watcher != nil && watcher?.isWatching == true, "PluginDirectoryWatcher started")

    // 2. v1 backward compatibility (7-arg manifest + script scaffold)
    let v1Desc = try PluginSystem.scaffoldPlugin(
        id: "legacy-v1",
        name: "Legacy V1",
        keywords: ["leg"],
        description: "v1 script compat",
        mode: .script,
        in: pluginsRoot
    )
    check(v1Desc.isValid && v1Desc.isEnabled, "v1 scaffolded plugin valid & enabled")
    let v1Exec = try PluginSystem.runScriptPlugin(v1Desc, query: "hello", in: pluginsRoot)
    check(v1Exec.exitCode == 0 && v1Exec.stdout.contains("[legacy-v1] ok"), "v1 script execution compatible")

    // Confirm hot-reload watcher fired on scaffold write
    let watchWait = watcherHit.wait(timeout: .now() + 3.0)
    check(watchWait == .success, "PluginDirectoryWatcher detected plugin directory changes")
    watcher?.stop()
    check(watcher?.isWatching == false, "PluginDirectoryWatcher cleanly stopped")

    // 3. v2 Manifest config + view JSON + async execution + plain-text fallback
    let v2Dir = pluginsRoot.appendingPathComponent("custom-view", isDirectory: true)
    try FileManager.default.createDirectory(at: v2Dir, withIntermediateDirectories: true)
    let v2Script = """
    #!/bin/zsh
    set -euo pipefail
    PAYLOAD="$(cat)"
    Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
    GREET="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.greeting raw -o - - 2>/dev/null || true)"
    CLIP="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract clipboard raw -o - - 2>/dev/null || true)"
    if [[ "$Q" == "plain" ]]; then
      echo "fallback plain: $GREET / $CLIP"
      exit 0
    fi
    cat <<EOF
    {"title":"$GREET $Q","subtitle":"clip=$CLIP","badge":"V2","markdown":"**Ready**","metrics":[{"key":"Env","value":"prod"}],"items":[{"title":"Copy Greeting","subtitle":"sub","icon":"sparkles","badge":"OK","copyText":"$GREET:$Q"}]}
    EOF
    """
    let v2ScriptURL = v2Dir.appendingPathComponent("run.sh")
    try v2Script.write(to: v2ScriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: v2ScriptURL.path)

    let v2Manifest = PluginManifest(
        id: "custom-view",
        name: "Custom View",
        version: "2.0.0",
        description: "Declarative view test",
        mode: .view,
        keywords: ["cv"],
        entry: "run.sh",
        author: "Lumakey",
        icon: "sparkles",
        hotkey: "⌥V",
        config: [
            PluginConfigField(key: "greeting", label: "Greeting", type: .text, defaultValue: "Hi"),
            PluginConfigField(key: "token", label: "Secret", type: .secret, defaultValue: ""),
            PluginConfigField(key: "verbose", label: "Verbose", type: .boolean, defaultValue: "true"),
            PluginConfigField(key: "region", label: "Region", type: .select, defaultValue: "cn", options: ["cn", "us"])
        ]
    )
    try JSONEncoder().encode(v2Manifest).write(to: v2Dir.appendingPathComponent("plugin.json"))

    try PluginSystem.updatePluginConfig(id: "custom-view", values: ["greeting": "HelloV2"], in: pluginsRoot)
    check(FileManager.default.fileExists(atPath: PluginSystem.stateFileURL(for: pluginsRoot).path), "plugin-state.json persisted in parent dir")

    let loadedV2 = PluginSystem.loadPlugin(at: v2Dir, in: pluginsRoot)
    check(loadedV2.isValid && loadedV2.userConfig["greeting"] == "HelloV2" && loadedV2.userConfig["region"] == "cn", "v2 config merges defaults & user values")

    let asyncBox = LockedResultBox<Result<PluginResolvedOutput, Error>?>(nil)
    let asyncSem = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let out = try await PluginSystem.runPluginAsync(loadedV2, query: "World", clipboardText: "CLIP99", in: pluginsRoot)
            asyncBox.set(.success(out))
        } catch {
            asyncBox.set(.failure(error))
        }
        asyncSem.signal()
    }
    check(asyncSem.wait(timeout: .now() + 5.0) == .success, "runPluginAsync completed in time")
    let resolved = try asyncBox.get()!.get()
    check(resolved.isStructuredView, "v2 view JSON parsed into PluginViewPayload")
    check(resolved.viewPayload?.title == "HelloV2 World", "config & query injected into stdin, got \(resolved.viewPayload?.title ?? "")")
    check(resolved.viewPayload?.subtitle == "clip=CLIP99", "clipboard injected into stdin")
    check(resolved.viewPayload?.metrics?.first?.value == "prod", "metrics decoded")
    check(resolved.viewPayload?.items?.first?.copyText == "HelloV2:World", "interactive items decoded")

    // Graceful degradation to plain text when view plugin emits non-JSON
    let fallbackOut = try PluginSystem.runPluginSync(loadedV2, query: "plain", clipboardText: "C1", in: pluginsRoot)
    check(!fallbackOut.isStructuredView && fallbackOut.plainText.contains("fallback plain: HelloV2 / C1"), "graceful plain text fallback")

    // 4. Enable / Disable persistence & enforcement
    try PluginSystem.setPluginEnabled(id: "custom-view", isEnabled: false, in: pluginsRoot)
    check(PluginSystem.listPlugins(in: pluginsRoot, includeDisabled: false).allSatisfy { $0.id != "custom-view" }, "disabled plugin excluded when includeDisabled=false")
    let disabledDesc = PluginSystem.loadPlugin(at: v2Dir, in: pluginsRoot)
    check(!disabledDesc.isEnabled, "descriptor reflects disabled state")
    var blockedDisabled = false
    do {
        _ = try PluginSystem.runScriptPlugin(disabledDesc, query: "x", in: pluginsRoot)
    } catch {
        blockedDisabled = true
    }
    check(blockedDisabled, "disabled plugin execution is blocked")
    try PluginSystem.setPluginEnabled(id: "custom-view", isEnabled: true, in: pluginsRoot)

    // 5. Starter Gallery (all 4 templates) + Export / Remove / Import roundtrip
    check(PluginStarterGallery.templates.count == 4, "4 starter templates registered")
    for tpl in PluginStarterGallery.templates {
        let inst = try PluginStarterGallery.install(templateID: tpl.id, in: pluginsRoot)
        check(inst.isValid, "starter template '\(tpl.id)' valid: \(inst.validationIssues)")
    }
    let ipOut = try PluginSystem.runPluginSync(PluginSystem.loadPlugin(at: pluginsRoot.appendingPathComponent("sys-ip-dns"), in: pluginsRoot), query: "", in: pluginsRoot)
    check(ipOut.isStructuredView && !(ipOut.viewPayload?.metrics ?? []).isEmpty, "sys-ip-dns returns structured view")

    let hashOut = try PluginSystem.runPluginSync(PluginSystem.loadPlugin(at: pluginsRoot.appendingPathComponent("quick-hash-uuid"), in: pluginsRoot), query: "abc", in: pluginsRoot)
    check(hashOut.isStructuredView && (hashOut.viewPayload?.items?.count ?? 0) >= 3, "quick-hash-uuid returns structured items")

    let portOut = try PluginSystem.runPluginSync(PluginSystem.loadPlugin(at: pluginsRoot.appendingPathComponent("port-killer"), in: pluginsRoot), query: "65531", in: pluginsRoot)
    check(portOut.isStructuredView, "port-killer returns structured view")

    let noteFile = tmp.appendingPathComponent("inbox.md")
    try PluginSystem.updatePluginConfig(id: "shell-note", values: ["notesPath": noteFile.path, "tagPrefix": "#v070"], in: pluginsRoot)
    let noteDesc = PluginSystem.loadPlugin(at: pluginsRoot.appendingPathComponent("shell-note"), in: pluginsRoot)
    let noteOut = try PluginSystem.runPluginSync(noteDesc, query: "Test quick capture", in: pluginsRoot)
    check(noteOut.execution.exitCode == 0 && (try? String(contentsOf: noteFile, encoding: .utf8))?.contains("#v070 Test quick capture") == true, "shell-note wrote configured markdown file")

    let exportParent = tmp.appendingPathComponent("exported", isDirectory: true)
    let exportedURL = try PluginSystem.exportPlugin(id: "quick-hash-uuid", to: exportParent, in: pluginsRoot)
    try PluginSystem.removePlugin(id: "quick-hash-uuid", in: pluginsRoot)
    check(!PluginStarterGallery.isInstalled(templateID: "quick-hash-uuid", in: pluginsRoot), "removePlugin deleted folder")
    let reimported = try PluginSystem.importPluginDirectory(from: exportedURL, in: pluginsRoot)
    check(reimported.isValid && reimported.id == "quick-hash-uuid", "importPluginDirectory restored valid plugin")
}

private func verifyMCPServerV2Subprocess() throws {
    let tmp = try makeTempDir("v070-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lumakey-mcp")
    let proc = Process()
    proc.executableURL = mcpURL
    proc.arguments = ["--plugins-dir", tmp.path]
    let inPipe = Pipe()
    let outPipe = Pipe()
    proc.standardInput = inPipe
    proc.standardOutput = outPipe
    try proc.run()

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"lumakey://specs/plugin-v2"}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lumakey_install_starter_plugin","arguments":{"id":"quick-hash-uuid"}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lumakey_set_plugin_enabled","arguments":{"id":"quick-hash-uuid","enabled":false}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lumakey_run_plugin_test","arguments":{"id":"quick-hash-uuid","query":"hi"}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"lumakey_set_plugin_enabled","arguments":{"id":"quick-hash-uuid","enabled":true}}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"lumakey_run_plugin_test","arguments":{"id":"quick-hash-uuid","query":"hi"}}}"#,
        #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"lumakey_remove_plugin","arguments":{"id":"quick-hash-uuid"}}}"#
    ]
    try inPipe.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
    try inPipe.fileHandleForWriting.close()
    proc.waitUntilExit()
    check(proc.terminationStatus == 0, "lumakey-mcp v2 exited 0")

    let lines = (String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .split(separator: "\n").map(String.init)
    check(lines.count == 8, "expected 8 MCP responses, got \(lines.count)")
    check(lines[0].contains("lumakey://specs/plugin-v1") && lines[0].contains("lumakey://specs/plugin-v2"), "resources/list exposes v1 & v2")
    check(lines[1].contains("PluginViewPayload"), "plugin-v2 spec content returned")
    check(lines[2].contains("quick-hash-uuid"), "lumakey_install_starter_plugin succeeded")
    check(lines[4].contains(#""isError":true"#), "disabled plugin run returns isError=true")
    check(lines[6].contains(#""isError":false"#), "re-enabled plugin run succeeds")
    check(lines[7].contains(#""removed" : true"#) || lines[7].contains("removed"), "lumakey_remove_plugin succeeded")
}

private func verifyDevToolkitAndSnippets() throws {
    // 1. Timestamps
    check(DevToolkitEngine.evaluate("ts").count == 3, "ts returns sec/ms/local")
    let ts10 = DevToolkitEngine.evaluate("1731500000")
    check(ts10.contains(where: { $0.copyText == "2024-11-13T12:13:20Z" }), "10-digit timestamp UTC conversion, got \(ts10)")
    let ts13 = DevToolkitEngine.evaluate("1731500000000")
    check(ts13.contains(where: { $0.copyText == "2024-11-13T12:13:20Z" }), "13-digit ms timestamp UTC conversion")

    // 2. UUID & Random Password
    let uuids = DevToolkitEngine.evaluate("uuid")
    check(uuids.first?.copyText.count == 36, "uuid length 36")
    let pwds = DevToolkitEngine.evaluate("pass 24")
    check(pwds.first?.copyText.count == 24, "pass 24 generates 24-char password")

    // 3. Base64 / URL / MD5 / SHA256 / JWT
    check(DevToolkitEngine.evaluate("b64 Lumakey").first?.copyText == "THVtYWtleQ==", "b64 encode")
    check(DevToolkitEngine.evaluate("b64d THVtYWtleQ==").first?.copyText == "Lumakey", "b64 decode")
    check(DevToolkitEngine.evaluate("url a b&c=1").first?.copyText == "a%20b%26c%3D1", "url encode")
    check(DevToolkitEngine.evaluate("urld a%20b%26c%3D1").first?.copyText == "a b&c=1", "url decode")
    check(DevToolkitEngine.evaluate("md5 hello").first?.copyText == "5d41402abc4b2a76b9719d911017c592", "md5 hash")
    check(DevToolkitEngine.evaluate("sha256 hello").first?.copyText == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "sha256 hash")

    let headerB64 = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let payloadB64 = Data(#"{"sub":"u42","role":"admin"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let jwtHits = DevToolkitEngine.evaluate("jwt \(headerB64).\(payloadB64).sig")
    check(jwtHits.first?.copyText.contains(#""role" : "admin""#) == true, "jwt decoded pretty JSON")

    // 4. Color conversion
    let hexHits = DevToolkitEngine.evaluate("#3478f6")
    check(hexHits.count == 4 && hexHits.first?.colorHex == "#3478F6", "#HEX color conversion")
    check(hexHits.contains(where: { $0.copyText == "rgb(52, 120, 246)" }), "HEX to RGB")
    let rgbHits = DevToolkitEngine.evaluate("rgb(52, 120, 246)")
    check(rgbHits.first?.copyText == "#3478F6", "rgb() to #HEX")

    // 5. JSON pretty & validation
    let jsonOK = DevToolkitEngine.evaluate(#"json {"b":1,"a":[2,3]}"#)
    check(jsonOK.first?.copyText.contains("\n") == true, "json pretty print")
    let jsonClip = DevToolkitEngine.evaluate("json", clipboardText: #"{"ok":true}"#)
    check(jsonClip.first?.badge == "JSON 美化", "bare json formats valid clipboard JSON")
    let jsonBad = DevToolkitEngine.evaluate("json {broken")
    check(jsonBad.first?.badge == "JSON 错误", "invalid json surfaces diagnostic")

    // 6. Native CoreImage QR code (360x360 crisp PNG + Vision roundtrip!)
    let qrHits = DevToolkitEngine.evaluate("qr https://lumakey.dev")
    guard let qrURL = qrHits.first?.previewImageURL else {
        check(false, "qr generated previewImageURL")
        return
    }
    defer { try? FileManager.default.removeItem(at: qrURL) }
    check(qrURL.path.contains("lumakey-clipboard"), "QR stored in lumakey-clipboard bucket")
    check(MediaClassifier.readImageDimensions(at: qrURL) == CGSize(width: 360, height: 360), "QR PNG is exact 360x360")
    let barcodeReq = VNDetectBarcodesRequest()
    try VNImageRequestHandler(url: qrURL, options: [:]).perform([barcodeReq])
    let qrPayloads = (barcodeReq.results ?? []).compactMap(\.payloadStringValue)
    check(qrPayloads.contains("https://lumakey.dev"), "Vision decodes generated CoreImage QR code")

    // 7. SnippetStore persistence & dynamic placeholders
    let tmp = try makeTempDir("v070-snippets")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let snippetsURL = tmp.appendingPathComponent("snippets.json")
    let store = SnippetStore(fileURL: snippetsURL)
    check(store.allSnippets().contains(where: { $0.keyword == ";date" }), "default snippets loaded")

    let fixedDate = Date(timeIntervalSince1970: 1_731_500_000)
    let expanded = SnippetStore.expand("D={{date}} T={{datetime}} C={{clipboard}} U={{uuid}}", clipboardText: "CLIP_OK", now: fixedDate)
    check(expanded.contains("CLIP_OK") && !expanded.contains("{{uuid}}") && expanded.count > 50, "placeholders expanded: \(expanded)")

    let custom = try store.upsert(SnippetItem(title: "Deploy Tag", keyword: ";dep", content: "deploy-{{date}}-{{clipboard}}", category: "Dev"))
    let reloadedStore = SnippetStore(fileURL: snippetsURL)
    let matched = reloadedStore.match(query: ";de", clipboardText: "v070", now: fixedDate)
    check(matched.first?.snippet.id == custom.id && matched.first?.expandedText.hasSuffix("-v070") == true, "snippet prefix match & live expansion")
    try reloadedStore.delete(id: custom.id)
    check(!reloadedStore.allSnippets().contains(where: { $0.id == custom.id }), "snippet deleted cleanly")
}

private final class LockedResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func set(_ next: T) { lock.withLock { value = next } }
    func get() -> T { lock.withLock { value } }
}
