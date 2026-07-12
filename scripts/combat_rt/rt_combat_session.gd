class_name RTCombatSession
extends RefCounted

var context = null
var config = null
var battlefield = null
var units: Array = []
var intents: Dictionary = {}
var elapsed_seconds: float = 0.0
var finished: bool = false
var finish_reason: String = ""
var finish_detail: String = ""

func reset(new_context, new_config, new_battlefield, unit_list: Array, intent_store: Dictionary) -> void:
	context = new_context
	config = new_config
	battlefield = new_battlefield
	units = unit_list
	intents = intent_store
	elapsed_seconds = 0.0
	finished = false
	finish_reason = ""
	finish_detail = ""

func mark_finished(reason: String, detail: String) -> void:
	finished = true
	finish_reason = reason
	finish_detail = detail
