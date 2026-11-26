class_name InputLead
extends RefCounted
## The pilot's client: how far ahead of server time to run, so its inputs reach
## the server's queue just in time (time dilation, after the input cushion of
## netcode N3). No nodes or networking: Ship feeds it what the server reports
## with each state, and hands lead_seconds to netfox (NetworkTime.lead_seconds).
##
## The server applies one input a tick from a queue, holding the last when the
## queue runs dry and skipping the oldest when it backs up; each hold or skip is
## a tick of motion the client didn't predict (about 40 m at 2.5 km/s). Instead
## of letting that happen, the client keeps the queue (counted after the server
## uses that tick's input) at the server's cushion plus MARGIN, clear of
## running dry and of the server's backlog skip: a short queue means run further ahead
## (send sooner), a long one less far. The lead changes by at most MAX_RATE seconds per second, so the
## client's ticks run at most that much faster or slower: too little to feel.

## How many inputs over the cushion to keep queued (counted after the server
## uses one): a spare against running dry, well short of the backlog skip.
const MARGIN := 1
## How fast the lead may change: seconds of lead per second (1.5% faster or
## slower than real time at most).
const MAX_RATE := 0.015
## How strongly a queue away from its target pulls: seconds of lead per second,
## per input short or over.
const GAIN := 0.005
## How much of each report goes into the smoothed queue depth.
const SMOOTHING := 0.05
## Never further ahead or behind than this (a stalled or flooded queue must not
## run it away). Behind is fine: the queue's depth with no lead is whatever it
## was when the server first filled its cushion, often deeper than needed.
const MAX_LEAD := 0.5

var lead_seconds := 0.0
var _depth := -1.0  # Smoothed queue depth; -1 before the first report.
var _tick_seconds: float


func _init(tick_seconds: float) -> void:
	_tick_seconds = tick_seconds


## The server had [param queued] of our inputs waiting, with a cushion of
## [param cushion]; [param dt] seconds have passed since the last report.
func observe(queued: int, cushion: int, dt: float) -> void:
	_depth = float(queued) if _depth < 0.0 else lerpf(_depth, float(queued), SMOOTHING)
	var short := (cushion + MARGIN) - _depth  # Inputs short of the target (negative: over).
	var rate := clampf(short * GAIN, -MAX_RATE, MAX_RATE)
	lead_seconds = clampf(lead_seconds + rate * dt, -MAX_LEAD, MAX_LEAD)
