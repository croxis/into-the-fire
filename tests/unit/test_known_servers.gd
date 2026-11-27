extends GutTest
## KnownServers: the certificate each server showed the first time this client
## joined it (trust on first use), and the DTLS check against it.
const Network := preload("res://network/network.gd")

const PATH := "user://test_known_servers.cfg"
const DIR := "user://test_known_servers_identity"
const PORT := 2298

var identity: ServerIdentity


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	identity = ServerIdentity.new()
	identity.load_or_create(DIR)


func before_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _pem() -> String:
	return identity.certificate.save_to_string()


func test_a_server_never_joined_has_no_certificate() -> void:
	assert_null(KnownServers.new(PATH).pinned("10.0.0.1", 2258))


func test_remembers_a_certificate_between_runs() -> void:
	assert_true(KnownServers.new(PATH).remember("10.0.0.1", 2258, _pem()))
	var pin := KnownServers.new(PATH).pinned("10.0.0.1", 2258)
	assert_not_null(pin)
	assert_eq(pin.save_to_string(), _pem())


func test_each_address_and_port_is_its_own_server() -> void:
	var known := KnownServers.new(PATH)
	known.remember("10.0.0.1", 2258, _pem())
	assert_null(known.pinned("10.0.0.1", 2259))
	assert_null(known.pinned("10.0.0.2", 2258))


func test_refuses_something_that_is_not_a_certificate() -> void:
	var known := KnownServers.new(PATH)
	assert_false(known.remember("10.0.0.1", 2258, "hello"))
	assert_false(known.remember("10.0.0.1", 2258, 42))
	assert_null(known.pinned("10.0.0.1", 2258))


func test_server_details_carry_its_certificate() -> void:
	var info := {"certificate": _pem()}
	assert_eq(Network.certificate_in(info), _pem())
	assert_eq(Network.certificate_in({}), "")
	assert_eq(Network.certificate_in({"certificate": 7}), "")


func test_the_pinned_certificate_lets_a_client_in() -> void:
	assert_eq(await _connect_with(identity.certificate), MultiplayerPeer.CONNECTION_CONNECTED)


func test_another_certificate_keeps_a_client_out() -> void:
	var other := ServerIdentity.new()
	var other_dir := DIR + "_other"
	DirAccess.make_dir_recursive_absolute(other_dir)
	for f in DirAccess.get_files_at(other_dir):
		DirAccess.remove_absolute(other_dir.path_join(f))
	other.load_or_create(other_dir)
	assert_ne(await _connect_with(other.certificate), MultiplayerPeer.CONNECTION_CONNECTED,
			"A server that can't prove it holds the pinned certificate's key is refused")
	for e in get_errors():  # mbedtls reports the failed check.
		if not e.handled and ("TLS" in str(e.code, e.rationale) or "x509" in str(e.code, e.rationale).to_lower()):
			e.handled = true


## Connects a client that trusts [param pin] to a server using [member identity];
## returns the client's status once it settles.
func _connect_with(pin: X509Certificate) -> int:
	var server := ENetMultiplayerPeer.new()
	server.create_server(PORT, 2)
	Network.secure_server(server, identity)
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", PORT)
	Network.secure_client(client, "127.0.0.1", pin)
	var status := client.get_connection_status()
	for i in 300:
		server.poll()
		client.poll()
		status = client.get_connection_status()
		if status != MultiplayerPeer.CONNECTION_CONNECTING:
			break
		await wait_physics_frames(1)
	client.close()
	server.close()
	return status


func test_a_failed_join_names_a_changed_certificate_only_when_one_was_pinned() -> void:
	var plain := Network.connection_failed_reason("10.0.0.1", 2258, false, PATH)
	assert_string_contains(plain, "10.0.0.1:2258")
	assert_false("certificate" in plain)
	var pinned := Network.connection_failed_reason("10.0.0.1", 2258, true, PATH)
	assert_string_contains(pinned, "certificate changed")
	assert_string_contains(pinned, ProjectSettings.globalize_path(PATH), "says which file to edit")
