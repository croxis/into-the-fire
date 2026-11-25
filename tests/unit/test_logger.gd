extends GutTest
## The game log's line prefix: who logged it and, once ticks run, at which tick.

const GameLog := preload("res://logger.gd")


func test_prefix_has_the_role_and_tick_while_ticking() -> void:
	assert_eq(GameLog.prefix("SERVER", 1234), "SERVER @1234")
	assert_eq(GameLog.prefix("123456", 0), "123456 @0")


func test_prefix_has_no_tick_before_ticks_run() -> void:
	assert_eq(GameLog.prefix("SERVER", -1), "SERVER")


func test_offline_prefix_is_empty() -> void:
	assert_eq(GameLog.prefix("", -1), "")
