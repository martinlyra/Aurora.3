//renwicks: fictional unit to describe shield strength
//a small meteor hit will deduct 1 renwick of strength from that shield tile
//light explosion range will do 1 renwick's damage
//medium explosion range will do 2 renwick's damage
//heavy explosion range will do 3 renwick's damage
//explosion damage is cumulative. if a tile is in range of light, medium and heavy damage, it will take a hit from all three

/obj/machinery/shield_gen
	name = "bubble shield generator"
	desc = "Machine that generates an impenetrable field of energy when activated."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "generator0"
	var/active = 0
	var/field_radius = 3
	var/max_field_radius = 100
	var/list/field
	density = 1
	var/locked = 0
	var/average_field_strength = 0
	var/strengthen_rate = 0.2
	var/max_strengthen_rate = 0.5	//the maximum rate that the generator can increase the average field strength
	var/dissipation_rate = 0.030	//the percentage of the shield strength that needs to be replaced each second
	var/min_dissipation = 0.01		//will dissipate by at least this rate in renwicks per field tile (otherwise field would never dissipate completely as dissipation is a percentage)
	var/powered = 0
	var/check_powered = 1
	var/obj/machinery/shield_capacitor/owned_capacitor
	var/target_field_strength = 10
	var/max_field_strength = 10
	var/time_since_fail = 100
	var/energy_conversion_rate = 0.0002	//how many renwicks per watt?
	use_power = 0	//doesn't use APC power
	var/multiz = FALSE
	var/multi_unlocked = FALSE

/obj/machinery/shield_gen/Initialize()
	for(var/obj/machinery/shield_capacitor/possible_cap in range(1, src))
		if(get_dir(possible_cap, src) == possible_cap.dir)
			owned_capacitor = possible_cap
			break
	field = list()
	. = ..()

/obj/machinery/shield_gen/Destroy()
	for(var/obj/effect/energy_field/D in field)
		field.Remove(D)
		D.loc = null
	return ..()

/obj/machinery/shield_gen/emag_act(var/remaining_charges, var/mob/user)
	if(prob(75))
		src.locked = !src.locked
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = 1
		updateDialog()

	spark(src, 5, alldirs)

/obj/machinery/shield_gen/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/card/id))
		var/obj/item/card/id/C = W
		if((access_captain in C.access) || (access_security in C.access) || (access_engine in C.access))
			src.locked = !src.locked
			to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
			updateDialog()
		else
			to_chat(user, SPAN_ALERT("Access denied."))
	else if(W.iswrench())
		src.anchored = !src.anchored
		src.visible_message(SPAN_NOTICE("\The [src] has been [anchored ? "bolted to the floor":"unbolted from the floor"] by \the [user]."))

		if(active)
			toggle()
		if(anchored)
			spawn(0)
				for(var/obj/machinery/shield_capacitor/cap in range(1, src))
					if(cap.owned_gen)
						continue
					if(get_dir(cap, src) == cap.dir && cap.anchored)
						owned_capacitor = cap
						owned_capacitor.owned_gen = src
						updateDialog()
						break
		else
			if(owned_capacitor && owned_capacitor.owned_gen == src)
				owned_capacitor.owned_gen = null
			owned_capacitor = null
	else
		..()

/obj/machinery/shield_gen/attack_ai(user as mob)
	if(!ai_can_interact(user))
		return
	return src.attack_hand(user)

/obj/machinery/shield_gen/attack_hand(mob/user)
	if(stat & (BROKEN))
		return
	interact(user)

/obj/machinery/shield_gen/interact(mob/user)
	if(locked)
		to_chat(user, SPAN_WARNING("The device is locked. Swipe your ID to unlock it."))
		return
	if(!anchored)
		to_chat(user, SPAN_WARNING("The device needs to be bolted to the ground first."))
		return
	else
		if(owned_capacitor)
			if(!(owned_capacitor in range(1, src) && get_dir(owned_capacitor, src) == owned_capacitor.dir && owned_capacitor.anchored))
				if(owned_capacitor.owned_gen == src)
					owned_capacitor.owned_gen = null
				owned_capacitor = null
	if(!owned_capacitor)
		for(var/obj/machinery/shield_capacitor/cap in range(1, src))
			if(cap.owned_gen)
				continue
			if(get_dir(cap, src) == cap.dir && cap.anchored)
				owned_capacitor = cap
				owned_capacitor.owned_gen = src
				updateDialog()
				break
	return src.ui_interact(user)



/obj/machinery/shield_gen/machinery_process()
	if (!anchored && active)
		toggle()

	average_field_strength = max(average_field_strength, 0)

	if(field.len)
		time_since_fail++
		var/total_renwick_increase = 0 //the amount of renwicks that the generator can add this tick, over the entire field
		var/renwick_upkeep_per_field = max(average_field_strength * dissipation_rate, min_dissipation)

		//figure out how much energy we need to draw from the capacitor
		if(active && owned_capacitor && owned_capacitor.active)
			var/target_renwick_increase = min(target_field_strength - average_field_strength, strengthen_rate) + renwick_upkeep_per_field //per field tile

			var/required_energy = field.len * target_renwick_increase / energy_conversion_rate
			var/assumed_charge = min(owned_capacitor.stored_charge, required_energy)
			total_renwick_increase = assumed_charge * energy_conversion_rate
			owned_capacitor.stored_charge -= assumed_charge
		else
			renwick_upkeep_per_field = max(renwick_upkeep_per_field, 0.5)

		var/renwick_increase_per_field = total_renwick_increase/field.len //per field tile

		average_field_strength = 0 //recalculate the average field strength
		for(var/obj/effect/energy_field/E in field)
			var/amount_to_strengthen = renwick_increase_per_field - renwick_upkeep_per_field
			if(E.ticks_recovering > 0 && amount_to_strengthen > 0)
				E.Strengthen( min(amount_to_strengthen / 10, 0.1) )
				E.ticks_recovering -= 1
			else
				E.Strengthen(amount_to_strengthen)

			average_field_strength += E.strength

		average_field_strength /= field.len
		if(average_field_strength < 1)
			time_since_fail = 0
	else
		average_field_strength = 0

/obj/machinery/shield_gen/ex_act(var/severity)
	if(active)
		toggle()
	return ..()

/obj/machinery/shield_gen/proc/toggle()
	set background = 1
	active = !active
	update_icon()
	if(active)
		var/list/covered_turfs = get_shielded_turfs()
		var/turf/T = get_turf(src)
		if(T in covered_turfs)
			covered_turfs.Remove(T)
		for(var/turf/O in covered_turfs)
			var/obj/effect/energy_field/E = new(O)
			field.Add(E)
		covered_turfs = null

		for(var/mob/M in view(5,src))
			to_chat(M, "[icon2html(src, M)] You hear heavy droning start up.")
	else
		for(var/obj/effect/energy_field/D in field)
			field.Remove(D)
			D.loc = null

		for(var/mob/M in view(5,src))
			to_chat(M, "[icon2html(src, M)] You hear heavy droning fade out.")

/obj/machinery/shield_gen/update_icon()
	if(stat & BROKEN)
		icon_state = "broke"
	else
		if (src.active)
			icon_state = "generator1"
		else
			icon_state = "generator0"

//TODO MAKE THIS MULTIZ COMPATIBLE
//grab the border tiles in a circle around this machine
/obj/machinery/shield_gen/proc/get_shielded_turfs()
	var/turf/gen_turf = get_turf(src)
	. = list()

	if (!gen_turf)
		return

	var/turf/T

	for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
		T = locate(gen_turf.x + x_offset, gen_turf.y - field_radius, gen_turf.z)
		if (T)
			. += T

		T = locate(gen_turf.x + x_offset, gen_turf.y + field_radius, gen_turf.z)
		if (T)
			. += T

	for (var/y_offset = -field_radius+1; y_offset < field_radius; y_offset++)
		T = locate(gen_turf.x - field_radius, gen_turf.y + y_offset, gen_turf.z)
		if (T)
			. += T

		T = locate(gen_turf.x + field_radius, gen_turf.y + y_offset, gen_turf.z)
		if (T)
			. += T

/obj/machinery/shield_gen/ui_interact(mob/user)
	var/datum/vueui/ui = SSvueui.get_open_ui(user, src)
	if (!ui)
		ui = new(user, src, "machinery-shields-shield", 480, 400, "Shield Generator", state = interactive_state)
		ui.open()
		ui.auto_update_content = TRUE

/obj/machinery/shield_gen/vueui_data_change(list/data, mob/user, datum/vueui/ui)
	data = ..() || list()

	data["owned_capacitor"] = owned_capacitor
	data["active"] = active
	data["time_since_fail"] = time_since_fail
	data["multi_unlocked"] = multi_unlocked
	data["multiz"] = multiz
	data["field_radius"] = field_radius
	data["min_field_radius"] = 1
	data["max_field_radius"] = max_field_radius
	data["average_field"] = round(average_field_strength, 0.01)
	data["progress_field"] = (target_field_strength ? round(100 * average_field_strength / target_field_strength, 0.1) : "NA")
	data["power_take"] = round(field.len * max(average_field_strength * dissipation_rate, min_dissipation) / energy_conversion_rate)
	data["shield_power"] = round(field.len * min(strengthen_rate, target_field_strength - average_field_strength) / energy_conversion_rate)
	data["strengthen_rate"] = (strengthen_rate * 10)
	data["max_strengthen_rate"] = (max_strengthen_rate * 10)
	data["target_field_strength"] = target_field_strength

	return data

/obj/machinery/shield_gen/Topic(href, href_list)
	if (!isturf(loc))
		return 0

	if(href_list["toggle"])
		toggle()

	if(href_list["multiz"])
		multiz = !multiz

	if (href_list["size_set"])
		field_radius = between(1, text2num(href_list["size_set"]), max_field_radius)

	if (href_list["charge_set"])
		strengthen_rate = (between(1, text2num(href_list["charge_set"]), (max_strengthen_rate * 10)) / 10)

	if (href_list["field_set"])
		target_field_strength = between(1, text2num(href_list["field_set"]), 10)

	src.add_fingerprint(usr)
	return 1