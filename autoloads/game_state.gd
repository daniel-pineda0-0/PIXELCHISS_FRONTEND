extends Node

const states :Array=[
	"initializing",
	"lobby",
	"game"
]
const next_scene_paths:Dictionary= {
	"initializing":"res://features/lobby/RoomScreen.tscn",
	"lobby":"",
	"game":"res://features/lobby/RoomScreen.tscn"
}
var state:=0

func nextState()->void:
	state+=1

func next_scene_path()->String:
	return next_scene_paths[states[state]]
