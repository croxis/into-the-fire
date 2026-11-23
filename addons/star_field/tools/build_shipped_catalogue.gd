extends SceneTree
## Rebuilds the shipped star catalogue from the default CSV, without the editor
## (same as Project > Tools > Rebuild star catalogue):
##   godot --headless --path . -s addons/star_field/tools/build_shipped_catalogue.gd


func _init() -> void:
	var sources := PackedStringArray([StarCatalogService.DEFAULT_SOURCE])
	var start := Time.get_ticks_msec()
	var err := StarCatalogCache.build_shipped(sources, StarCatalogService.SHIPPED_CATALOG)
	if err != OK:
		push_error("Star catalogue rebuild failed: " + error_string(err))
		quit(1)
		return
	print("Star catalogue: wrote %s in %d ms" % [StarCatalogService.SHIPPED_CATALOG, Time.get_ticks_msec() - start])
	quit()
