rm export/itf.zip
rm export/ITF/README.md
rm export/ITF/CREDITS
cp README.md exports/ITF/README.md
cp CREDITS exports/ITF/CREDITS
godot --headless --export-debug "Windows Desktop" export/ITF/itf.exe
godot --headless --export-debug "Linux/X11" export/ITF/itf.x86_64
cd export
zip -r itf.zip ITF
