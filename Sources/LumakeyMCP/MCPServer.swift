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

            guard let id = request["id"] else { continue }
            let params = request["params"] as? [String: Any] ?? [:]
            writeJSONLine(handleRequest(id: id, method: method, params: params))
        }
    }

    private func handleRequest(id: Any, method: String, params: [String: Any]) -> [String: Any] {
        switch method {
        case "initialize":
            return ok(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["resources": [:], "tools": [:]],
                "serverInfo": ["name": "lumakey-mcp", "version": "0.2.0"]
            ])
        case "ping":
            return ok(id: id, result: [:])
        case "resources/list":
            return ok(id: id, result: [
                "resources": [
                    [
                        "uri": "lumakey://specs/plugin-v1",
                        "name": "Lumakey Plugin Spec v1",
                        "description": "Manifest fields, directory layout and stdin/stdout script contract.",
                        "mimeType": "text/markdown"
                    ],
                    [
                        "uri": "lumakey://specs/plugin-v2",
                        "name": "Lumakey Plugin Spec v2",
                        "description": "Declarative view JSON payload, config fields, state persistence and hot-reload.",
                        "mimeType": "text/markdown"
                    ]
                ]
            ])
        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            let specText: String? = switch uri {
            case "lumakey://specs/plugin-v1": PluginSystem.specMarkdown
            case "lumakey://specs/plugin-v2": PluginSystem.specV2Markdown
            default: nil
            }
            guard let specText else {
                return err(id: id, code: -32602, message: "Unknown resource URI: \(uri)")
            }
            return ok(id: id, result: [
                "contents": [["uri": uri, "mimeType": "text/markdown", "text": specText]]
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
                    "enabled": desc.isEnabled,
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
            let mode = PluginMode(rawValue: arguments["mode"] as? String ?? "script") ?? .script
            do {
                let created = try PluginSystem.scaffoldPlugin(
                    id: id, name: displayName, keywords: keywords,
                    description: description, mode: mode, in: pluginsDirectory
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
            let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
            return textResult(prettyJSON(["id": desc.id, "valid": desc.isValid, "issues": desc.validationIssues]))

        case "lumakey_run_plugin_test":
            let id = arguments["id"] as? String ?? ""
            let query = arguments["query"] as? String ?? ""
            guard PluginSystem.isSafePluginID(id) else {
                return textResult("Invalid plugin id: \(id)", isError: true)
            }
            let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
            let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
            do {
                let res = try PluginSystem.runScriptPlugin(desc, query: query, in: pluginsDirectory)
                return textResult(prettyJSON([
                    "exitCode": res.exitCode,
                    "durationMs": res.durationMs,
                    "stdout": res.stdout,
                    "stderr": res.stderr
                ]), isError: res.exitCode != 0)
            } catch {
                return textResult("Execution error: \(error.localizedDescription)", isError: true)
            }

        case "lumakey_install_starter_plugin":
            let id = arguments["id"] as? String ?? ""
            let overwrite = arguments["overwrite"] as? Bool ?? true
            do {
                let installed = try PluginStarterGallery.install(templateID: id, in: pluginsDirectory, overwrite: overwrite)
                return textResult(prettyJSON([
                    "id": installed.id,
                    "name": installed.manifest.name,
                    "mode": installed.manifest.mode.rawValue,
                    "path": installed.directoryURL.path,
                    "valid": installed.isValid
                ]))
            } catch {
                return textResult("Install error: \(error.localizedDescription)", isError: true)
            }

        case "lumakey_set_plugin_enabled":
            let id = arguments["id"] as? String ?? ""
            guard let enabled = arguments["enabled"] as? Bool else {
                return textResult("Missing boolean argument 'enabled'", isError: true)
            }
            let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
            guard PluginSystem.isSafePluginID(id), FileManager.default.fileExists(atPath: dir.path) else {
                return textResult("Plugin not found or invalid id: \(id)", isError: true)
            }
            do {
                try PluginSystem.setPluginEnabled(id: id, isEnabled: enabled, in: pluginsDirectory)
                return textResult(prettyJSON(["id": id, "enabled": enabled]))
            } catch {
                return textResult("Error: \(error.localizedDescription)", isError: true)
            }

        case "lumakey_remove_plugin":
            let id = arguments["id"] as? String ?? ""
            do {
                try PluginSystem.removePlugin(id: id, in: pluginsDirectory)
                return textResult(prettyJSON(["id": id, "removed": true]))
            } catch {
                return textResult("Remove error: \(error.localizedDescription)", isError: true)
            }

        default:
            return textResult("Unknown tool: \(name)", isError: true)
        }
    }

    private func toolSchemas() -> [[String: Any]] {
        let starterIDs = PluginStarterGallery.templates.map(\.id)
        return [
            schema("lumakey_list_plugins", "List plugins in Lumakey Plugins directory.", [:], []),
            schema("lumakey_scaffold_plugin", "Scaffold a new Lumakey plugin manifest and executable script.", [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "keywords": ["type": "array", "items": ["type": "string"]],
                "description": ["type": "string"],
                "mode": ["type": "string", "enum": ["script", "view"]]
            ], ["id", "name", "keywords"]),
            schema("lumakey_validate_plugin", "Validate a plugin's plugin.json and entrypoint.", ["id": ["type": "string"]], ["id"]),
            schema("lumakey_run_plugin_test", "Run a plugin with a test query over stdin.", [
                "id": ["type": "string"], "query": ["type": "string"]
            ], ["id", "query"]),
            schema("lumakey_install_starter_plugin", "Install a curated starter plugin template.", [
                "id": ["type": "string", "enum": starterIDs], "overwrite": ["type": "boolean"]
            ], ["id"]),
            schema("lumakey_set_plugin_enabled", "Enable or disable an installed plugin.", [
                "id": ["type": "string"], "enabled": ["type": "boolean"]
            ], ["id", "enabled"]),
            schema("lumakey_remove_plugin", "Remove an installed plugin directory.", ["id": ["type": "string"]], ["id"])
        ]
    }

    private func schema(_ name: String, _ desc: String, _ props: [String: Any], _ req: [String]) -> [String: Any] {
        var input: [String: Any] = ["type": "object", "properties": props]
        if !req.isEmpty { input["required"] = req }
        return ["name": name, "description": desc, "inputSchema": input]
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
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func writeJSONLine(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
