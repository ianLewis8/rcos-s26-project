@tool
extends EditorPlugin

const SINGLETON_NAME = "GodotDumdumDebugMenu"
const SINGLETON_PATH = "res://addons/debug/debug.tscn"

func _enter_tree() -> void:
	add_autoload_singleton(SINGLETON_NAME, SINGLETON_PATH)

func _exit_tree() -> void:
	remove_autoload_singleton(SINGLETON_NAME)
