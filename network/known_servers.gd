class_name KnownServers
extends RefCounted
## The certificate each server showed the first time this client joined it,
## by address and port (trust on first use, as SSH does). Later joins give it
## to DTLS (Network.secure_client), which then refuses any server that can't
## prove it holds that certificate's key: someone pretending to be the server
## can't read the login. The first join is trusted as it is.

const DEFAULT_PATH := "user://known_servers.cfg"
const SECTION := "servers"
const PEM_START := "-----BEGIN CERTIFICATE-----"

var path: String
var _config := ConfigFile.new()


func _init(file_path := DEFAULT_PATH) -> void:
	path = file_path
	if FileAccess.file_exists(path):
		_config.load(path)


static func key_for(address: String, port: int) -> String:
	return "%s:%d" % [address, port]


## The certificate remembered for [param address] and [param port], or null
## for a server never joined.
func pinned(address: String, port: int) -> X509Certificate:
	var pem: Variant = _config.get_value(SECTION, key_for(address, port), "")
	if not pem is String or not (pem as String).begins_with(PEM_START):
		return null
	var cert := X509Certificate.new()
	return cert if cert.load_from_string(pem) == OK else null


## Remembers [param pem] (from the server, so anything at all) for
## [param address] and [param port]. False if it isn't a certificate.
func remember(address: String, port: int, pem: Variant) -> bool:
	if not pem is String or not (pem as String).begins_with(PEM_START):
		return false
	if X509Certificate.new().load_from_string(pem) != OK:
		return false
	_config.set_value(SECTION, key_for(address, port), pem)
	if _config.save(path) != OK:
		Log.log(["KnownServers: could not save ", path], Log.MessageType.WARNING)
	return true
