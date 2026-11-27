extends GutTest
## Quitting with the connection open freed the world online: the server sent
## each client a despawn for every spawned node, including nodes that client was
## never told about (fog of war), and the client logged an error for each. The
## network node goes offline as it leaves the tree, before Galaxy does.

const Network := preload("res://network/network.gd")
const EntryScene := preload("res://entry.tscn")


func test_leaving_the_tree_goes_offline() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var network: Node = Network.new()
	holder.add_child(network)
	var mp := SceneMultiplayer.new()
	get_tree().set_multiplayer(mp, holder.get_path())
	network.peer = ENetMultiplayerPeer.new()
	network.peer.create_server(2272)
	mp.multiplayer_peer = network.peer
	holder.remove_child(network)
	assert_ne(mp.multiplayer_peer, network.peer, "offline: nothing more is sent through it")
	network.peer.close()
	network.free()
	get_tree().set_multiplayer(null, holder.get_path())


func test_network_leaves_the_tree_before_galaxy() -> void:
	# Godot frees a node's children last first, so network must come after Galaxy.
	var entry := EntryScene.instantiate()
	assert_gt(entry.get_node("network").get_index(), entry.get_node("Galaxy").get_index())
	entry.free()
