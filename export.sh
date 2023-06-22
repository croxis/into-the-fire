rm export/itf.zip
godot --headless --export-debug "Windows Desktop" export/itf.exe
godot --headless --export-debug "Linux/X11" export/itf.x86_64
cd export
zip itf.zip *
