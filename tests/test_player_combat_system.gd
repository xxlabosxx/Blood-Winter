extends SceneTree
## Headless rigid test suite for PlayerCombatComponent, TimeDilationManager,
## CombatModifierComponent, Soft Lock-On, Attack Magnetism, Command Inputs,
## and Witch Time -> EnemyReactionComponent integration.

const TimeDilationScript = preload("res://core/time_dilation_manager.gd")
const ModifierComp = preload("res://combat/combat_modifier_component.gd")
const PlayerCombatComp = preload("res://combat/player_combat_component.gd")
const ReactionComp = preload("res://combat/enemy_reaction_component.gd")

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run_all_tests")


func _assert_true(cond: bool, label: String) -> void:
	if not cond:
		_failures.append("FAIL: %s" % label)
		printerr("[FAIL] %s" % label)


func _assert_approx(actual: float, expected: float, tol: float, label: String) -> void:
	if absf(actual - expected) > tol:
		_failures.append("FAIL: %s (expected %.4f, got %.4f)" % [label, expected, actual])
		printerr("[FAIL] %s (expected %.4f, got %.4f)" % [label, expected, actual])


func _run_all_tests() -> void:
	await physics_frame
	_test_1_combat_modifier_component()
	_test_2_time_dilation_manager()
	_test_3_double_jump_and_cut()
	_test_4_dodge_anti_mash_penalty()
	await _test_5_witch_time_ignores_enemy_poise()
	_test_6_soft_lock_and_attack_magnetism()
	_test_7_command_inputs_and_anytime_dodge_cancel()

	if _failures.is_empty():
		print("[ALL PASS] 7/7 PlayerCombatSystem tests passed!")
		quit(0)
	else:
		printerr("[FAILED] %d assertions failed." % _failures.size())
		quit(1)


func _test_1_combat_modifier_component() -> void:
	var mods: ModifierComp = ModifierComp.new()
	root.add_child(mods)

	mods.add_modifier(&"relic_dmg", &"damage_mult", 1.25, -1.0, ModifierComp.ModMode.MULTIPLY)
	mods.add_modifier(&"skill_dmg", &"damage_mult", 1.20, 1.0, ModifierComp.ModMode.MULTIPLY)
	mods.add_modifier(&"iframe_perk", &"dodge_iframe_bonus", 0.08, 0.5, ModifierComp.ModMode.ADD)

	_assert_approx(mods.get_multiplier(&"damage_mult"), 1.50, 0.001, "Test1: Multiplicative stacking 1.25 * 1.20 = 1.50")
	_assert_approx(mods.get_additive(&"dodge_iframe_bonus"), 0.08, 0.001, "Test1: Additive bonus = 0.08")
	_assert_true(mods.get_active_count() == 3, "Test1: 3 active modifiers")

	# Tick 0.6s -> iframe_perk expires, permanent & 1.0s buffs remain
	mods.tick(0.6)
	_assert_approx(mods.get_additive(&"dodge_iframe_bonus"), 0.0, 0.001, "Test1: Temporary additive expired")
	_assert_true(mods.get_active_count() == 2, "Test1: 2 active modifiers remain")

	# Tick another 0.5s -> skill_dmg expires, permanent relic remains
	mods.tick(0.5)
	_assert_approx(mods.get_multiplier(&"damage_mult"), 1.25, 0.001, "Test1: Only permanent modifier remains")

	mods.queue_free()
	print("[PASS] Test 1: CombatModifierComponent (Scalable Buffs/Relics)")


func _test_2_time_dilation_manager() -> void:
	var tdm: Node = TimeDilationScript.new()
	root.add_child(tdm)

	_assert_approx(float(tdm.get("world_time_scale")), 1.0, 0.001, "Test2: Initial world_time_scale = 1.0")
	tdm.call("trigger_witch_time", 2.0, 0.25)
	_assert_true(bool(tdm.get("is_witch_time_active")), "Test2: Witch Time active")
	_assert_approx(float(tdm.get("world_time_scale")), 0.25, 0.001, "Test2: world_time_scale = 0.25")
	_assert_approx(float(tdm.get("player_time_scale")), 1.0, 0.001, "Test2: player_time_scale stays 1.0")
	_assert_approx(float(tdm.call("get_enemy_delta", 0.1)), 0.025, 0.0001, "Test2: Enemy delta scaled by 0.25")
	_assert_approx(float(tdm.call("get_player_delta", 0.1)), 0.1, 0.0001, "Test2: Player delta remains 1.0x")

	tdm.call("tick", 2.1)
	_assert_true(not bool(tdm.get("is_witch_time_active")), "Test2: Witch Time expired")
	_assert_approx(float(tdm.get("world_time_scale")), 1.0, 0.001, "Test2: world_time_scale restored to 1.0")

	tdm.queue_free()
	print("[PASS] Test 2: TimeDilationManager (Separated World/Player TimeScale)")


func _test_3_double_jump_and_cut() -> void:
	var cc: PlayerCombatComp = PlayerCombatComp.new()
	root.add_child(cc)

	_assert_true(cc.consume_jump(true), "Test3: 1st jump from floor succeeds")
	_assert_true(cc.jumps_used == 1, "Test3: jumps_used == 1")
	_assert_true(cc.consume_jump(false), "Test3: 2nd jump (Double Jump) in air succeeds")
	_assert_true(cc.jumps_used == 2, "Test3: jumps_used == 2")
	_assert_true(not cc.consume_jump(false), "Test3: 3rd jump in air blocked")
	cc.reset_air_jumps()
	_assert_true(cc.jumps_used == 0, "Test3: Landing resets jumps_used to 0")
	_assert_approx(cc.jump_cut_gravity_multiplier, 2.5, 0.01, "Test3: Variable jump gravity cut = 2.5")

	cc.queue_free()
	print("[PASS] Test 3: Double Jump & Variable Jump Height")


func _test_4_dodge_anti_mash_penalty() -> void:
	var cc: PlayerCombatComp = PlayerCombatComp.new()
	root.add_child(cc)

	for i: int in range(4):
		var stumbled: bool = cc.register_dodge()
		_assert_true(not stumbled, "Test4: Dodge #%d allowed normally" % (i + 1))

	# 5th consecutive dodge triggers Stumble penalty!
	var fifth_stumbled: bool = cc.register_dodge()
	_assert_true(fifth_stumbled, "Test4: 5th consecutive dodge triggers Stumble penalty")
	_assert_true(cc.is_stumbling, "Test4: is_stumbling flag is true")

	# Attacking resets dodge chain
	for i: int in range(3):
		cc.register_dodge()
	cc.on_attack_performed()
	_assert_true(cc.consecutive_dodges == 0, "Test4: Attack resets consecutive_dodges to 0")

	cc.queue_free()
	print("[PASS] Test 4: Dodge Spam Penalty (5 dodges -> Stumble)")


func _test_5_witch_time_ignores_enemy_poise() -> void:
	var tdm: Node = TimeDilationScript.new()
	var mods: ModifierComp = ModifierComp.new()
	var cc: PlayerCombatComp = PlayerCombatComp.new()
	root.add_child(tdm)
	root.add_child(mods)
	root.add_child(cc)

	mods.add_modifier(&"wt_ext", &"witch_time_duration_mult", 1.5, -1.0, ModifierComp.ModMode.MULTIPLY)

	var body: CharacterBody3D = CharacterBody3D.new()
	var vis: Node3D = Node3D.new()
	var hp: HealthComponent = HealthComponent.new()
	var data: EnemyData = EnemyData.new()
	data.max_poise = 100.0
	hp.configure_max_health(200.0, true)
	var rc: ReactionComp = ReactionComp.new()
	body.add_child(vis)
	body.add_child(hp)
	body.add_child(rc)
	root.add_child(body)
	rc.configure(body, vis, hp, data, 24.5)

	# By default Witch Time is disabled until unlocked as a skill/modifier
	_assert_true(not cc.witch_time_enabled, "Test5: Witch Time disabled by default")
	_assert_true(not cc.try_trigger_witch_time(Vector3.ZERO, [], mods, true, tdm), "Test5: Blocked while locked")

	# Unlock via skill modifier and trigger Witch Time with buff multiplier (2.6 * 1.5 = 3.9s)
	mods.add_modifier(&"wt_skill", &"witch_time_unlocked", 1.0, -1.0, ModifierComp.ModMode.ADD)
	var triggered: bool = cc.try_trigger_witch_time(Vector3.ZERO, [], mods, true, tdm)
	_assert_true(triggered, "Test5: Witch Time triggered")
	_assert_approx(float(tdm.get("witch_time_remaining")), 3.9, 0.01, "Test5: Witch Time duration scaled by CombatModifierComponent")

	# Sync world_time_scale to EnemyReactionComponent -> Launch must bypass full Poise (100)!
	rc.time_slow_multiplier = float(tdm.get("world_time_scale"))
	var launch_hit: DamageInfo = DamageInfo.new()
	launch_hit.amount = 25.0
	launch_hit.stagger_power = 20.0
	launch_hit.is_launcher = true
	launch_hit.launch_vector = Vector3(0.0, 11.0, 0.0)
	var res: Dictionary = rc.process_hit(launch_hit, false)

	_assert_true(bool(res["entered_reaction"]), "Test5: Witch Time bypasses enemy full Poise")
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.LAUNCHED, "Test5: Enemy enters LAUNCHED immediately")

	body.queue_free()
	tdm.queue_free()
	mods.queue_free()
	cc.queue_free()
	print("[PASS] Test 5: Witch Time -> EnemyReactionComponent Integration")


func _test_6_soft_lock_and_attack_magnetism() -> void:
	var cc: PlayerCombatComp = PlayerCombatComp.new()
	root.add_child(cc)

	var enemy_front: Node3D = Node3D.new()
	enemy_front.position = Vector3(0.0, 0.0, -3.0)
	var enemy_behind: Node3D = Node3D.new()
	enemy_behind.position = Vector3(0.0, 0.0, 2.0)
	root.add_child(enemy_front)
	root.add_child(enemy_behind)

	var found: Node3D = cc.find_soft_lock_target(Vector3.ZERO, Vector3.FORWARD, [enemy_front, enemy_behind])
	_assert_true(found == enemy_front, "Test6: Soft Lock-On picks enemy inside frontal cone (-Z)")

	# Magnetism inside 1.25m..4.2m pulls toward enemy
	var mag_vel: Vector3 = cc.compute_attack_magnetism_velocity(Vector3.ZERO, enemy_front)
	_assert_true(mag_vel.z < -1.0, "Test6: Attack Magnetism pulls forward toward 3m target")

	# Magnetism inside <= 1.25m stops pulling so player does not clip through enemy capsule
	enemy_front.position = Vector3(0.0, 0.0, -1.0)
	var stop_vel: Vector3 = cc.compute_attack_magnetism_velocity(Vector3.ZERO, enemy_front)
	_assert_approx(stop_vel.length(), 0.0, 0.001, "Test6: Attack Magnetism stops at capsule boundary")

	enemy_front.queue_free()
	enemy_behind.queue_free()
	cc.queue_free()
	print("[PASS] Test 6: Soft Lock-On & Attack Magnetism")


func _test_7_command_inputs_and_anytime_dodge_cancel() -> void:
	var cc: PlayerCombatComp = PlayerCombatComp.new()
	root.add_child(cc)

	var enemy: Node3D = Node3D.new()
	enemy.position = Vector3(0.0, 0.0, -4.0)
	root.add_child(enemy)

	# Ground directional inputs
	var cmd_stinger: StringName = cc.resolve_attack_command(true, enemy, Vector3(0, 0, -1), Vector3.FORWARD, false, 7.6, 7.6, Vector3.ZERO)
	var cmd_launcher: StringName = cc.resolve_attack_command(true, enemy, Vector3(0, 0, 1), Vector3.FORWARD, false, 7.6, 7.6, Vector3.ZERO)
	var cmd_ground: StringName = cc.resolve_attack_command(true, enemy, Vector3.ZERO, Vector3.FORWARD, false, 0.0, 7.6, Vector3.ZERO)
	# Air directional input
	var cmd_air_slam: StringName = cc.resolve_attack_command(false, enemy, Vector3(0, 0, 1), Vector3.FORWARD, false, 5.0, 7.6, Vector3.ZERO)

	_assert_true(cmd_stinger == &"stinger", "Test7: Forward + Attack at range -> Stinger")
	_assert_true(cmd_launcher == &"launcher", "Test7: Back + Attack -> Launcher")
	_assert_true(cmd_ground == &"ground", "Test7: Neutral + Attack -> Ground String")
	_assert_true(cmd_air_slam == &"air_slam", "Test7: Back/Down + Attack in Air -> Air Slam")

	# ComboStepData anytime dodge cancel rule
	var step: ComboStepData = ComboStepData.new()
	_assert_true(step.can_cancel_with_dodge(0.0, 1.0), "Test7: Anytime Dodge Cancel allowed at frame 0 (Startup)")
	step.allow_anytime_dodge_cancel = false
	step.cancel_dodge_time = 0.2
	_assert_true(not step.can_cancel_with_dodge(0.05, 1.0), "Test7: Restricted step blocks Dodge Cancel before cancel_dodge_time")

	enemy.queue_free()
	cc.queue_free()
	print("[PASS] Test 7: Command Inputs & Anytime Dodge Cancel Flag")
