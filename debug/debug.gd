## Debug module for real-time information and development tools.
##
## Features:
## - Customizable debug menu
## - Live-updating texts.
## - Rich console logging 
## - Auto disable in production builds.
##
## Hotkeys:
## - [F1]: Toggle Debug Menu visibility.
## - [F2]: Take a screenshot
## - [F3]: Pause/Unpause the game.
##
## Usable Functions:
## - Debug.log(...messages): Print a standard log message.
## - Debug.warn(...messages): Print a warning message.
## - Debug.error(...messages): Print an error message.
## - Debug.verbose(...messages): Print a verbose debug message.
## - Debug.register_live(key, callback): Register a function to display real-time info.
## - Debug.unregister_live(key): Remove a live-updating info item.
## - Debug.add_menu_item(text, function, arguments): Add a custom action to the debug menu.
## - Debug.add_separator(text): Add a separator or group header to the menu.
## - Debug.dialog_input(title, callback, description, default): Show an input dialog.
## - Debug.dialog_confirm(title, description, on_confirm, on_cancel): Show a confirmation dialog.
## - Debug.take_screenshot(): Capture and save a screenshot to the user folder.
## - Debug.time(id): Measure and print the elapsed time between two calls with the same ID.

# class_name Debug # Don't name the class, use as autoload
extends CanvasLayer

@onready var menu_button: MenuButton = $Control/HBoxContainer/MenuButton
@onready var popup_menu: PopupMenu = menu_button.get_popup()
@onready var label_live: RichTextLabel = $Control/HBoxContainer/VBoxContainer/LabelLive

var item_index := 0
var item_id_to_function := {}
var item_text_to_item := {}
var live_update_items: Dictionary[StringName, Callable] = {} ## Registering map to display live info
var elapsed_times: Dictionary[StringName, int] = {}


func _ready() -> void:
	# Hide scene in editor
	if visible:
		visible = _is_debug_build()

	process_mode = Node.PROCESS_MODE_ALWAYS if _is_debug_build() else Node.PROCESS_MODE_DISABLED

	if not _is_debug_build():
		return
		
	popup_menu.clear()
	popup_menu.id_pressed.connect(_on_item_press)
	_build_menu()
	
	register_live(&"Resolution", func(): return get_viewport().size)
	register_live(&"Draw Call", func(): return Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	register_live(&"Orphan node", func():
		var result := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		return result if result > 0 else null
	)


func _exit_tree() -> void:
	unregister_live(&"Resolution")
	unregister_live(&"Draw Call")
	unregister_live(&"Orphan node")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_F1:
			visible = !visible
			Debug.log("Toggle Debug Menu", visible)
		elif event.keycode == KEY_F2:
			take_screenshot()
		elif event.keycode == KEY_F3:
			get_tree().paused = not get_tree().paused
			Debug.log("Pause: ", get_tree().paused)


#region Debug UI
## Rebuilds the debug menu with all registered items.
func _build_menu() -> void:
	add_menu_item("Take screenshot [F2]", take_screenshot)
	add_menu_item("Pause [F3]", func(): get_tree().paused = !get_tree().paused)
	add_menu_item("Reload Scene", func(): get_tree().reload_current_scene())


## Adds a separator to the debug menu with optional text.
func add_separator(text: String = "") -> void:
	popup_menu.add_separator(text, item_index)
	item_index += 1


## Adds an item to the debug menu that calls a function when pressed.
func add_menu_item(text: String, function: Callable = Callable(), arguments: Array[Variant] = []) -> void:
	if item_text_to_item.has(text):
		var existing_item_index: int = item_text_to_item[text]
		item_id_to_function[existing_item_index] = {"function": function, "arguments": arguments}
		return
	
	item_id_to_function[item_index] = {"function": function, "arguments": arguments}
	popup_menu.add_item(text, item_index)
	item_text_to_item[text] = item_index
	item_index += 1


func _on_item_press(id: int) -> void:
	var caller = item_id_to_function.get(id, {"function": Callable(), "arguments": []})
	var function: Callable = caller["function"]

	if function.is_valid():
		function.callv(caller["arguments"])
		Debug.log(str(function), "called")


## Ability to show real time text infomation for debugging
## Callback must return a string to display[br][br]
## Eg: To show real-time: "Screen Size: 640x320"[br]
## [code]Debug.register_live(&"Screen Size", func(): return "%dx%d (%s)" % [get_viewport().size.x, get_viewport().size.y, Debug._get_aspect_ratio_string(get_viewport())])[/code][br][br]
## And don't forget to remove it when exit_tree()[br]
## [code]unregister_live("Screen Size")[/code]
func register_live(key: StringName, callback: Callable) -> void:
	live_update_items[key] = callback


## Unregisters a live update item.
func unregister_live(key: StringName, _callback: Callable = Callable()) -> void:
	live_update_items.erase(key)


func _on_update_label_live_timer_timeout() -> void:
	var text = ""

	for key in live_update_items:
		var callback: Callable = live_update_items[key]
		if callback.is_valid():
			var value = callback.call()
			if value == null or (typeof(value) == TYPE_STRING and value == ""):
				continue
			text += "%s: %s\n" % [key, value]

	if text != label_live.text:
		label_live.text = text

enum LogType { LOG, WARNING, ERROR, VERBOSE, UNKNOWN }

const LOG_TYPE_COLORS := {
	LogType.LOG: Color("f3f3f3ff"),
	LogType.WARNING: Color("dfcb33ff"),
	LogType.ERROR: Color("ff5a5aff"),
	LogType.VERBOSE: Color("8d8d8dff"),
}
#endregion Debug UI


#region Pretty print log
func _log(log_type: LogType = LogType.LOG, messages: Array = []) -> void:
	var message: String = " ".join(messages)
	var _time = Time.get_time_dict_from_system()
	var stack = get_stack()

	if stack.size() > 1:
		# Debug.warn and Debug.error cause showing "debug.gd:129 warn() Message..."
		if stack.size() > 2 and "debug.gd" in stack[1].get("source", ""):
			stack = stack[2]
		else:
			stack = stack[1]
	elif stack.size() > 0:
		stack = stack[0]
	else:
		stack = null # Threading does not support get_stack()

	if stack:
		stack["source"] = stack["source"].replace("res://", "")
		stack["file"] = stack["source"].split("/")[-1]

	var function_path = "[url=res://{source}:{line}]{file}:{function}()[/url]".format(stack) if stack else ""
	var log_color = LOG_TYPE_COLORS[log_type]

	# Only editor support colors
	if OS.has_feature("editor"):
		print_rich("[color=#636363][%02d:%02d:%02d]%s[/color] [color=%s]%s[/color]" % [_time.hour, _time.minute, _time.second, function_path, log_color.to_html(), message])
		return

	print("[%02d:%02d:%02d][%s]%s %s" % [_time.hour, _time.minute, _time.second, LogType.keys()[log_type], function_path, message])


## Prints a message to the console with LOG level.
func log(...messages: Array) -> void:
	_log(LogType.LOG, messages)


## Prints a message to the console with WARNING level.
func warn(...messages: Array) -> void:
	_log(LogType.WARNING, messages)


## Prints a message to the console with ERROR level.
func error(...messages: Array) -> void:
	_log(LogType.ERROR, messages)


## Prints a message to the console with VERBOSE level.
func verbose(...messages: Array) -> void:
	_log(LogType.VERBOSE, messages)
	
#endregion Pretty print log


## Displays an input dialog.
func dialog_input(message: String, on_complete: Callable, description: String = "", default_value: String = "") -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.ok_button_text = "OK"
	dialog.title = message

	if description:
		dialog.dialog_text = description

	var input := LineEdit.new()

	if default_value:
		input.text = default_value
	else:
		dialog.get_ok_button().disabled = true

	dialog.add_child(input)
	input.text_changed.connect(func(t): dialog.get_ok_button().disabled = t.strip_edges() == "")
	input.text_submitted.connect(func(_text): dialog.get_ok_button().pressed.emit())

	dialog.confirmed.connect(func():
		on_complete.call(input.text)
		dialog.queue_free()
	)

	add_child(dialog)
	await get_tree().process_frame
	dialog.popup_centered(Vector2(500, 200))
	input.grab_focus()
	input.select_all()
	return dialog


## Displays a confirmation dialog.
func dialog_confirm(message: String, description: String = "", on_confirm: Callable = Callable(), on_cancel: Callable = Callable()) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.ok_button_text = "OK"
	dialog.cancel_button_text = "Cancel"
	dialog.title = message

	if description:
		dialog.dialog_text = description

	dialog.confirmed.connect(func():
		if on_confirm: on_confirm.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		if on_cancel: on_cancel.call()
		dialog.queue_free())

	add_child(dialog)
	await get_tree().process_frame
	dialog.popup_centered(Vector2(500, 160))
	return dialog


## Captures a screenshot and saves it to the user folder.
func take_screenshot() -> void:
	var was_visible := visible
	visible = false
	
	await RenderingServer.frame_post_draw # Wait until frame is ready
	var image := get_viewport().get_texture().get_image() 

	# Fix image size for true pixel game, too small image output
	if image.get_size().x != get_viewport().size.x or image.get_size().y != get_viewport().size.y:
		image.resize(get_viewport().size.x, get_viewport().size.y, Image.INTERPOLATE_NEAREST)
	
	if not image:
		Debug.error("Failed to capture screen.")
		return

	# Ensure the screenshots directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))

	var path := "user://screenshots/screenshot_%s.png" % Time.get_datetime_string_from_system().replace(":", "_")
	var err := image.save_png(ProjectSettings.globalize_path(path))

	if err == OK:
		Debug.log("Screenshot saved to", ProjectSettings.globalize_path(path))
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
	else:
		Debug.error("Failed to save screenshot:", err)
		
	visible = was_visible








func _on_screen_size_timer_timeout() -> void:
	Debug.verbose("Screen size changed to", get_viewport().size)


## Print elapsed time between first call and second call
## Eg:
## Debug.time("Index")
## startIndexing()
## Debug.time("Index") => Print "[Timing] Index completed in 100ms"
func time(id: StringName) -> void:
	if elapsed_times.has(id):
		Debug.verbose("%s %.2fms" % [id, Time.get_ticks_msec() - elapsed_times[id]])
		elapsed_times.erase(id)
		return

	elapsed_times[id] = Time.get_ticks_msec()


#region Internal Helpers
static func _is_debug_build() -> bool:
	return OS.is_debug_build() and not Engine.is_editor_hint()


static func _get_aspect_ratio_string(viewport: Viewport) -> String:
	var viewport_size = viewport.size
	var width = float(viewport_size.x)
	var height = float(viewport_size.y)
	var actual_ratio = width / height

	var standard_ratios = {
		"16/9": 16.0 / 9.0,
		"4/3": 4.0 / 3.0,
		"21/9": 21.0 / 9.0,
		"3/2": 3.0 / 2.0,
		"1/1": 1.0
	}

	var closest_ratio = ""
	var min_percentage_diff = INF

	for ratio_name in standard_ratios:
		var standard_value = standard_ratios[ratio_name]
		var difference = abs(actual_ratio - standard_value)
		var percentage_diff = (difference / standard_value) * 100.0

		if percentage_diff < min_percentage_diff:
			min_percentage_diff = percentage_diff
			closest_ratio = ratio_name

	if min_percentage_diff > 10.0:
		closest_ratio = "~" + closest_ratio

	return closest_ratio
#endregion Internal Helpers
