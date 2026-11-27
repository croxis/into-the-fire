extends GutTest
## ServerIdentity: the server's key and certificate for DTLS, kept between runs,
## and a real encrypted connection over loopback.
const Network := preload("res://network/network.gd")

const DIR := "user://test_server_identity"
const PORT := 2296


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))


func test_creates_a_key_and_certificate_the_first_time() -> void:
	var identity := ServerIdentity.new()
	assert_true(identity.load_or_create(DIR))
	assert_true(FileAccess.file_exists(DIR.path_join(ServerIdentity.KEY_FILE)))
	assert_true(FileAccess.file_exists(DIR.path_join(ServerIdentity.CERT_FILE)))
	assert_not_null(identity.server_options())


func test_keeps_the_same_certificate_next_run() -> void:
	var first := ServerIdentity.new()
	first.load_or_create(DIR)
	var second := ServerIdentity.new()
	second.load_or_create(DIR)
	assert_eq(second.certificate.save_to_string(), first.certificate.save_to_string(),
			"A stable certificate is what a client could pin later")


func test_a_client_connects_over_dtls() -> void:
	var identity := ServerIdentity.new()
	identity.load_or_create(DIR)
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 2), OK)
	assert_eq(Network.secure_server(server, identity), OK)
	var client := ENetMultiplayerPeer.new()
	assert_eq(client.create_client("127.0.0.1", PORT), OK)
	assert_eq(Network.secure_client(client, "127.0.0.1"), OK)
	for i in 300:
		server.poll()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await wait_physics_frames(1)
	assert_eq(client.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTED)
	client.close()
	server.close()


func test_a_plain_client_cannot_join_an_encrypted_server() -> void:
	var identity := ServerIdentity.new()
	identity.load_or_create(DIR)
	var server := ENetMultiplayerPeer.new()
	server.create_server(PORT + 1, 2)
	Network.secure_server(server, identity)
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", PORT + 1)
	for i in 60:
		server.poll()
		client.poll()
		await wait_physics_frames(1)
	assert_ne(client.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTED)
	assert_gt(_expect_errors("TLS handshake"), 0, "The server refuses the plain packets")
	client.close()
	server.close()


## Marks this test's engine errors containing [param text] as expected (they
## fail the test otherwise) and returns how many there were.
func _expect_errors(text: String) -> int:
	var count := 0
	for e in get_errors():
		if not e.handled and text.to_lower() in str(e.code, " ", e.rationale).to_lower():
			e.handled = true
			count += 1
	return count
