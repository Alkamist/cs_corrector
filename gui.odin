package main

import "clap"

gui_extension := clap.Plugin_Gui{
	is_api_supported = proc "c" (clap_plugin: ^clap.Plugin, api: cstring, is_floating: bool) -> bool {
		return api == clap.WINDOW_API && !is_floating
	},
	get_preferred_api = proc "c" (clap_plugin: ^clap.Plugin, api: ^cstring, is_floating: ^bool) -> bool {
		api^ = clap.WINDOW_API
		is_floating^ = false
		return true
	},
	create = proc "c" (clap_plugin: ^clap.Plugin, api: cstring, is_floating: bool) -> bool {
		if !(api == clap.WINDOW_API && !is_floating) {
			return false
		}
		return true
	},
	destroy = proc "c" (clap_plugin: ^clap.Plugin) {
	},
	set_scale = proc "c" (clap_plugin: ^clap.Plugin, scale: f64) -> bool {
		return false
	},
	get_size = proc "c" (clap_plugin: ^clap.Plugin, width, height: ^u32) -> bool {
		// let plugin = clapPlugin.getUserPlugin()
		// width^ = u32(plugin.window.widthPixels)
		// height^ = u32(plugin.window.heightPixels)
		return true
	},
	can_resize = proc "c" (clap_plugin: ^clap.Plugin) -> bool {
		return true
	},
	get_resize_hints = proc "c" (clap_plugin: ^clap.Plugin, hints: ^clap.Gui_Resize_Hints) -> bool {
		hints.can_resize_horizontally = true
		hints.can_resize_vertically = true
		hints.preserve_aspect_ratio = false
		return true
	},
	adjust_size = proc "c" (clap_plugin: ^clap.Plugin, width, height: ^u32) -> bool {
		return true
	},
	set_size = proc "c" (clap_plugin: ^clap.Plugin, width, height: u32) -> bool {
		// let plugin = clapPlugin.getUserPlugin()
		// plugin.window.setPosition(0, 0)
		// plugin.window.setSize(width.int, height.int)
		return true
	},
	set_parent = proc "c" (clap_plugin: ^clap.Plugin, window: ^clap.Window) -> bool {
		// let plugin = clapPlugin.getUserPlugin()
		// plugin.window.embedInsideWindow(cast[pointer](window.union.win32))
		// plugin.window.setPosition(0, 0)
		// plugin.window.setSize(plugin.window.widthPixels, plugin.window.heightPixels)
		return true
	},
	set_transient = proc "c" (clap_plugin: ^clap.Plugin, window: ^clap.Window) -> bool {
		return false
	},
	suggest_title = proc "c" (clap_plugin: ^clap.Plugin, title: cstring) {
	},
	show = proc "c" (clap_plugin: ^clap.Plugin) -> bool {
		// let plugin = clapPlugin.getUserPlugin()
		// plugin.window.show()
		return true
	},
	hide = proc "c" (clap_plugin: ^clap.Plugin) -> bool {
		// let plugin = clapPlugin.getUserPlugin()
		// plugin.window.hide()
		return true
	},
}