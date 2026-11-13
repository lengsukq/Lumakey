import Foundation
import LumakeyCore

var pluginsDir = PluginSystem.defaultPluginsDirectory()
let args = CommandLine.arguments
if let flagIndex = args.firstIndex(of: "--plugins-dir"), flagIndex + 1 < args.count {
    pluginsDir = URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
}

MCPServer(pluginsDirectory: pluginsDir).runStdioLoop()
