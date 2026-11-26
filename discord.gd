extends Control

## Discord rich presence: shows "Playing Into The Fire" and how long, on the
## player's Discord profile.
##
## Presence only, so no Discord sign-in: while the client is not connected to a
## Discord account, update_rich_presence goes through the Discord app running on
## the player's computer (see Client::UpdateRichPresence in the SDK's
## discordpp.h). Without that app nothing is shown, and nothing breaks. Signing
## in (authorize, get_token, connect_discord) is only needed for friends,
## lobbies or messages, and connecting would clear this presence.
##
## entry.gd adds this node only for players on a screen whose Discord extension
## loaded (LaunchOptions.wants_discord).

## The Into The Fire application in the Discord developer portal.
const APPLICATION_ID: int = 1356458511122567168

var client: DiscordClient
var _started_ms: int


func _ready() -> void:
	_started_ms = int(Time.get_unix_time_from_system() * 1000.0)
	client = DiscordClient.new()
	client.add_log_callback(_on_log_message, DiscordLoggingSeverity.WARNING)
	client.set_application_id(APPLICATION_ID)
	show_presence("In the menus")


## Replaces the presence. [param details] is the first line under the game's
## name, [param state] the second (optional). The play timer keeps running from
## when the game started.
func show_presence(details: String, state := "") -> void:
	var activity := DiscordActivity.new()
	activity.set_type(DiscordActivityTypes.PLAYING)
	activity.set_details(details)
	if not state.is_empty():
		activity.set_state(state)
	var timestamps := DiscordActivityTimestamps.new()
	timestamps.set_start(_started_ms)
	activity.set_timestamps(timestamps)
	client.update_rich_presence(activity, _on_rich_presence_updated)


func _process(_delta: float) -> void:
	Discord.run_callbacks()


func _on_log_message(message: String, severity: DiscordLoggingSeverity.Enum) -> void:
	Log.log(["Discord ", Discord.enum_to_string(severity, DiscordLoggingSeverity.id), ": ", message],
			Log.MessageType.WARNING)


func _on_rich_presence_updated(result: DiscordClientResult) -> void:
	if not result.successful():
		# Expected when Discord isn't running, so a warning, not an error.
		Log.log(["Discord presence not set: ", result.error()], Log.MessageType.WARNING)
