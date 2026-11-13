import Foundation
import LumakeyCore

final class MCPServer {
    private let pluginsDirectory: URL

    init(pluginsDirectory: URL) {
        self.pluginsDirectory = pluginsDirectory
    }

    func runStdioLoop() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String
            else { continue }

            let id = request["id"]
            if id == nil {
                continue // JSON-RPC notification requires no response
            }
            let params = request["params"] as? [String: Any] ?? [:]
            let response = handleRequest(id: id!, method: method, params: params)
            writeJSONLine(response)
        }
    }

    private func handleRequest(id: Any, method: String, params: [String: Any]) -> [String: Any] {
        switch method {
        case "initialize":
            return ok(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["resources": [:], "tools": [:]],
                "serverInfo": ["name": "lumakey-mcp", "version": "0.1.0"]
            ])
        case "ping":
            return ok(id: id, result: [:])
        case "resources/list":
            return ok(id: id, result: [
                "resources": [[
                    "uri": "lumakey://specs/plugin-v1",
                    "name": "Lumakey Plugin Spec v1",
                    "description": "Manifest fields, directory layout and stdin/stdout script contract.",
                    "mimeType": "text/markdown"
                ]]
            ])
        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            guard uri == "lumakey://specs/plugin-v1" else {
                return err(id: id, code: -32602, message: "Unknown resource URI: \(uri)")
            }
            return ok(id: id, result: [
                "contents": [[
                    "uri": uri,
                    "mimeType": "text/markdown",
                    "text": PluginSystem.specMarkdown
                ]]
            ])
        case "tools/list":
            return ok(id: id, result: ["tools": toolSchemas()])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return ok(id: id, result: callTool(name: name, arguments: args))
        default:
            return err(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "lumakey_list_plugins":
            let plugins = PluginSystem.listPlugins(in: pluginsDirectory).map { desc -> [String: Any] in
                [
                    "id": desc.id,
                    "name": desc.manifest.name,
                    "mode": desc.manifest.mode.rawValue,
                    "keywords": desc.manifest.keywords,
                    "valid": desc.isValid,
                    "issues": desc.validationIssues
                ]
            }
            return textResult(prettyJSON(plugins))

        case "lumakey_scaffold_plugin":
            let id = arguments["id"] as? String ?? ""
            let displayName = arguments["name"] as? String ?? id
            let keywords = arguments["keywords"] as? [String] ?? [id]
            let description = arguments["description"] as? String ?? "AI 生成插件"
            let modeRaw = arguments["mode"] as? String ?? "script"
            let mode = PluginMode(rawValue: modeRaw) ?? .script
            do {
                let created = try PluginSystem.scaffoldPlugin(
                    id: id,
                    name: displayName,
                    keywords: keywords,
                    description: description,
                    mode: mode,
                    in: pluginsDirectory
                )
                return textResult("Scaffolded plugin '\(created.id)' at \(created.directoryURL.path)")
            } catch {
                return textResult("Error: \(error.localizedDescription)", isError: true)
            }

        case "lumakey_validate_plugin":
            let id = arguments["id"] as? String ?? ""
            guard PluginSystem.isSafePluginID(id) else {
                return textResult("Invalid plugin id: \(id)", isError: true)
            }
            let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
            let desc = PluginSystem.loadPlugin(at: dir)
            return textResult(prettyJSON(["id": desc.id, "valid": desc.isValid, "issues": desc.validationIssues]))

        case "lumakey_run_plugin_test":
            let id = arguments["id"] as? String ?? ""
            let query = arguments["query"] as? String ?? ""
            guard PluginSystem.isSafePluginID(id) else {
                return textResult("Invalid plugin id: \(id)", isError: true)
            }
            let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
            let desc = PluginSystem.loadPlugin(at: dir)
            do {
                let res = try PluginSystem.runScriptPlugin(desc, query: query)
                return textResult(prettyJSON([
                    "exitCode": res.exitCode,
                    "durationMs": res.durationMs,
                    "stdout": res.stdout,
                    "stderr": res.stderr
                ]), isError: res.exitCode != 0)
            } catch {
                return textResult("Execution error: \(error.localizedDescription)", isError: true)
            }

        default:
            return textResult("Unknown tool: \(name)", isError: true)
        }
    }

    private func toolSchemas() -> [[String: Any]] {
        [
            [
                "name": "lumakey_list_plugins",
                "description": "List plugins in Lumakey Plugins directory.",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "lumakey_scaffold_plugin",
                "description": "Scaffold a new Lumakey plugin manifest and executable script.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "name": ["type": "string"],
                        "keywords": ["type": "array", "items": ["type": "string"]],
                        "description": ["type": "string"],
                        "mode": ["type": "string", "enum": ["script", "view"]]
                    ],
                    "required": ["id", "name", "keywords"]
                ]
            ],
            [
                "name": "lumakey_validate_plugin",
                "description": "Validate a plugin's plugin.json and entrypoint.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "string"]],
                    "required": ["id"]
                ]
            ],
            [
                "name": "lumakey_run_plugin_test",
                "description": "Run a script plugin with a test query over stdin.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "string"], "query": ["type": "string"]],
                    "required": ["id", "query"]
                ]
            ]
        ]
    }

    private func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func ok(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func err(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func writeJSONLine(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
