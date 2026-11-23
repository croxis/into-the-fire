@tool
extends EditorPlugin
## Registers the StarField node and the StarCatalogs autoload, ships the
## pre-built catalogue with exports, and adds Project > Tools > Rebuild star
## catalogue (run it after editing the default CSV).

const AUTOLOAD := "StarCatalogs"
const MENU_ITEM := "Rebuild star catalogue"
const ExportPlugin := preload("star_catalog_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, "res://addons/star_field/star_catalog_service.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)


func _enter_tree() -> void:
	add_custom_type("StarField", "Node3D", preload("star_field_manager.gd"), preload("icon.png"))
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)
	add_tool_menu_item(MENU_ITEM, _rebuild_shipped_catalogue)


func _exit_tree() -> void:
	remove_custom_type("StarField")
	remove_export_plugin(_export_plugin)
	remove_tool_menu_item(MENU_ITEM)


func _rebuild_shipped_catalogue() -> void:
	var sources := PackedStringArray([StarCatalogService.DEFAULT_SOURCE])
	var err := StarCatalogCache.build_shipped(sources, StarCatalogService.SHIPPED_CATALOG)
	if err == OK:
		print("Star catalogue rebuilt: ", StarCatalogService.SHIPPED_CATALOG)
	else:
		push_error("Star catalogue rebuild failed: " + error_string(err))
