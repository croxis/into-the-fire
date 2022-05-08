rm export/itf.zip
godot4 --headless --export "Windows Desktop" export/itf.exe
godot4 --headless --export "Linux/X11" export/itf.x86_64
cd export
zip itf.zip *
