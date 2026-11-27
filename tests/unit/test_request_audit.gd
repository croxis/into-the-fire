extends GutTest
## The request audit (2026-11-27): what a client can send the server, besides
## the handlers' own tests. Every any_peer RPC takes the sender from the
## connection and checks it; these cover the looser edges the audit found.

const Ticks := preload("res://tests/unit/ticks.gd")
const Network := preload("res://network/network.gd")
const SystemScene := preload("res://systems/system_template.tscn")


func test_a_client_cannot_confirm_a_ship_it_does_not_hold() -> void:
	var interest := Interest.new()
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	ship.interest.override = interest
	add_child_autofree(ship)
	var here := RefCounted.new()
	var elsewhere := RefCounted.new()
	interest.update({7: Interest.view(here, null, {ship: true}),
			8: Interest.view(elsewhere, null, {ship: true})}, {ship: here})  # 7 holds it, 8 doesn't.
	ship.have_ship_from(8)
	assert_false(ship.interest.confirmed.has(8), "a ship it was never sent")
	# One it holds is believed (on a ship with no interest manager every client
	# holds it, and there is no visibility to update for an unconnected peer).
	var plain: Ship = Content.instantiate(&"b5:aurora_starfury")
	add_child_autofree(plain)
	plain.have_ship_from(7)
	assert_true(plain.interest.confirmed.has(7))


func test_servers_do_not_relay_between_clients() -> void:
	# Nothing in the game needs a client to reach another through the server;
	# with relay on, any client RPC or synced value could be forwarded to all.
	var mp := SceneMultiplayer.new()
	assert_true(mp.server_relay, "Godot's default")
	Network.configure_server(mp)
	assert_false(mp.server_relay)


func test_the_server_flies_a_remote_player_only_from_their_input_channel() -> void:
	# Their client is the authority of their InputsSync, so the server accepts
	# whatever it syncs into Inputs. It must never act on it.
	var stepper := ZoneStepper.new()
	add_child_autofree(stepper)
	var system: System = SystemScene.instantiate()
	add_child_autofree(system)
	stepper.add_zone(system)
	var ship: Ship = Content.instantiate(&"b5:aurora_starfury")
	system.add_ship(ship)
	var pilot: Character = ship.get_node("CrewMultiplayerSpawner").spawn(Character.pilot_data("Remote", 0, 99, 1))
	(ship.get_node("Consoles/Cockpit") as Console).occupy(pilot)
	pilot._player_pilot_id = 5
	pilot.inputs.rotation_throttle = Vector3(1, 1, 1)  # As if synced from a tampered client.
	pilot.inputs.fire_primary = true
	var still := func(tick: int) -> Dictionary:
		return InputChannel.make_record(tick, Vector3.ZERO, Vector3.ZERO, false, false, false)
	pilot.receive_inputs_from(99, [still.call(7), still.call(8)])
	await Ticks.run(1, 30)
	var helm: HelmCapability = (ship.get_node("Consoles/Cockpit") as Console).get_capability(HelmCapability)
	assert_eq(helm.input_rotation_throttle, Vector3.ZERO, "the channel's input")
	assert_eq(system.shots.count(), 0, "no trigger in the channel")
