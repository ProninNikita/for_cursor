extends RefCounted

var tree: SceneTree
var failures: Array[String] = []

func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree

func fail(message: String) -> bool:
	failures.append(message)
	print("QA_FAIL: %s" % message)
	return false

func check(condition: bool, message: String) -> bool:
	if not condition:
		return fail(message)
	return true

func has_failures() -> bool:
	return not failures.is_empty()

func wait_frames(count: int = 1) -> void:
	for _i in range(maxi(1, count)):
		await tree.process_frame

func wait_seconds(seconds: float) -> void:
	await tree.create_timer(seconds, true, false, true).timeout

func load_scene(scene_path: String) -> Node:
	var err := tree.change_scene_to_file(scene_path)
	if err != OK:
		fail("Не удалось загрузить сцену %s, код ошибки %d" % [scene_path, err])
		return null
	await wait_frames(3)
	var root := tree.current_scene
	if root == null:
		fail("После загрузки %s current_scene == null" % scene_path)
		return null
	check(root.scene_file_path == scene_path, "Ожидалась сцена %s, открыта %s" % [scene_path, root.scene_file_path])
	return root

func wait_for_scene(scene_path: String, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if tree.current_scene != null and tree.current_scene.scene_file_path == scene_path:
			return true
		await wait_seconds(0.05)
		elapsed += 0.05
	return fail("Сцена %s не открылась за %.1f сек, текущая: %s" % [scene_path, timeout_seconds, get_current_scene_path()])

func wait_for_any_scene(scene_paths: Array, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if tree.current_scene != null and tree.current_scene.scene_file_path in scene_paths:
			return true
		await wait_seconds(0.05)
		elapsed += 0.05
	return fail("Ни одна из сцен %s не открылась за %.1f сек, текущая: %s" % [str(scene_paths), timeout_seconds, get_current_scene_path()])

func wait_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if bool(predicate.call()):
			return true
		await wait_seconds(0.05)
		elapsed += 0.05
	return fail("Условие не выполнено за %.1f сек: %s" % [timeout_seconds, label])

func get_current_scene_path() -> String:
	if tree.current_scene == null:
		return "<none>"
	return tree.current_scene.scene_file_path

func get_current_root() -> Node:
	return tree.current_scene

func find_by_qa_id(qa_id: String, root: Node = null) -> Node:
	if root == null:
		root = tree.current_scene
	if root == null:
		return null
	return _find_by_qa_id_recursive(root, qa_id)

func _find_by_qa_id_recursive(node: Node, qa_id: String) -> Node:
	if str(node.get_meta("qa_id", "")) == qa_id:
		return node
	for child in node.get_children():
		var found := _find_by_qa_id_recursive(child, qa_id)
		if found != null:
			return found
	return null

func press_qa(qa_id: String) -> bool:
	var node := find_by_qa_id(qa_id)
	if node == null:
		return fail("Кнопка с qa_id=%s не найдена в %s" % [qa_id, get_current_scene_path()])
	if not node is BaseButton:
		return fail("Node qa_id=%s не является BaseButton" % qa_id)
	return await press_button(node as BaseButton, qa_id)

func press_path(node_path: String) -> bool:
	var root := tree.current_scene
	if root == null:
		return fail("Нельзя нажать %s: current_scene == null" % node_path)
	var node := root.get_node_or_null(node_path)
	if node == null:
		return fail("Кнопка по пути %s не найдена в %s" % [node_path, get_current_scene_path()])
	if not node is BaseButton:
		return fail("Node %s не является BaseButton" % node_path)
	return await press_button(node as BaseButton, node_path)

func press_button(button: BaseButton, label: String = "") -> bool:
	var name := label if label != "" else str(button.name)
	if button == null:
		return fail("Нельзя нажать null-кнопку")
	if not button.is_visible_in_tree():
		return fail("Кнопка %s не видима" % name)
	if button.disabled:
		return fail("Кнопка %s отключена" % name)
	if button is CheckBox:
		var checkbox := button as CheckBox
		var next_value := not checkbox.button_pressed
		checkbox.set_pressed_no_signal(next_value)
		checkbox.emit_signal("toggled", next_value)
	button.emit_signal("pressed")
	await wait_frames(3)
	return true

func set_checkbox_qa(qa_id: String, value: bool) -> bool:
	var node := find_by_qa_id(qa_id)
	if node == null:
		return fail("CheckBox с qa_id=%s не найден" % qa_id)
	if not node is CheckBox:
		return fail("Node qa_id=%s не является CheckBox" % qa_id)
	return await set_checkbox(node as CheckBox, value, qa_id)

func set_checkbox(checkbox: CheckBox, value: bool, label: String = "") -> bool:
	var name := label if label != "" else str(checkbox.name)
	if checkbox == null:
		return fail("Нельзя переключить null CheckBox")
	if checkbox.disabled:
		return fail("CheckBox %s отключен" % name)
	if checkbox.button_pressed == value:
		return true
	checkbox.set_pressed_no_signal(value)
	checkbox.emit_signal("toggled", value)
	await wait_frames(2)
	return true

func find_checkboxes_with_prefix(prefix: String) -> Array:
	var result: Array = []
	if tree.current_scene != null:
		_collect_checkboxes_with_prefix(tree.current_scene, prefix, result)
	return result

func _collect_checkboxes_with_prefix(node: Node, prefix: String, result: Array) -> void:
	if node is CheckBox and str(node.get_meta("qa_id", "")).begins_with(prefix):
		result.append(node)
	for child in node.get_children():
		_collect_checkboxes_with_prefix(child, prefix, result)

func collect_enabled_buttons() -> Array:
	var result: Array = []
	if tree.current_scene != null:
		_collect_enabled_buttons_recursive(tree.current_scene, result)
	return result

func _collect_enabled_buttons_recursive(node: Node, result: Array) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if button.is_visible_in_tree() and not button.disabled:
			result.append(button)
	for child in node.get_children():
		_collect_enabled_buttons_recursive(child, result)

func count_controls() -> int:
	if tree.current_scene == null:
		return 0
	return _count_controls_recursive(tree.current_scene)

func _count_controls_recursive(node: Node) -> int:
	var count := 1 if node is Control else 0
	for child in node.get_children():
		count += _count_controls_recursive(child)
	return count
