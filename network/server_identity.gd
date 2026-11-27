class_name ServerIdentity
extends RefCounted
## The server's private key and self-signed certificate, for encrypting ENet
## with DTLS (Network.secure_server). Made the first time a server starts and
## kept in user:// after, so the certificate stays the same between runs:
## clients remember it the first time they join (KnownServers) and refuse a
## server that can't prove it holds it later.

const KEY_FILE := "server_tls.key"
const CERT_FILE := "server_tls.crt"
const COMMON_NAME := "CN=Into The Fire server"

var key: CryptoKey
var certificate: X509Certificate


## Loads the key and certificate from [param dir], or makes and saves new ones
## when they are missing or unreadable. False only if they can't be made.
func load_or_create(dir := "user://") -> bool:
	var key_path := dir.path_join(KEY_FILE)
	var cert_path := dir.path_join(CERT_FILE)
	key = CryptoKey.new()
	certificate = X509Certificate.new()
	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path) \
			and key.load(key_path) == OK and certificate.load(cert_path) == OK:
		return true
	var crypto := Crypto.new()
	key = crypto.generate_rsa(2048)
	certificate = crypto.generate_self_signed_certificate(key, COMMON_NAME, "20260101000000", "20460101000000")
	if key == null or certificate == null:
		push_error("ServerIdentity: could not make a key and certificate")
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	if key.save(key_path) != OK or certificate.save(cert_path) != OK:
		Log.log(["ServerIdentity: could not save to ", dir, "; a new certificate each run"], Log.MessageType.WARNING)
	else:
		Log.log(["ServerIdentity: made a new key and certificate in ", dir], Log.MessageType.INFO)
	return true


func server_options() -> TLSOptions:
	return TLSOptions.server(key, certificate)
