class_name Match
extends Node
## What the game controller plays against: a local game with CPUs (LocalMatch)
## or a game on the server (NetMatch). The controller drives one seat,
## `local_player`. It sends moves with submit() and hears about every applied
## move, its own included, through `event`, with the state it may now see.
##
## Snapshots are always redacted for `local_player` and carry a rising "seq",
## so an older snapshot can never overwrite a newer one.

signal started(snapshot: Dictionary)
signal event(action: Dictionary, snapshot: Dictionary)   # actions also include {"type": "next_round"}
signal rejected(snapshot: Dictionary)                    # our submit() was illegal; here's the real state
signal seats_changed                                     # seat_names / seat_kinds changed
signal room_changed(room: Dictionary)                    # online: room info (rematch votes)
signal closed(reason: String)                            # online: the game is gone (disconnected, kicked)

var local_player := 0
var seat_names: Array[String] = []
var seat_kinds: Array[String] = []   # "you", "cpu", "human" or "bot" (a CPU took a player's seat)
var client_busy := false             # set by the controller while it animates; CPUs wait for it


func begin() -> void:
	pass


func submit(_action: Dictionary) -> void:
	pass


## The controller has finished showing the round's scores.
func scores_shown() -> void:
	pass


func leave() -> void:
	pass

