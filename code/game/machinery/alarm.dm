
#define AALARM_MODE_SCRUBBING 1
#define AALARM_MODE_VENTING 2 //makes draught
#define AALARM_MODE_PANIC 3 //constantly sucks all air
#define AALARM_MODE_REPLACEMENT 4 //sucks off all air, then refill and swithes to scrubbing
#define AALARM_MODE_OFF 5

#define AALARM_REPORT_TIMEOUT 100

#define AALARM_DANGERLEVEL_GOOD 	1
#define AALARM_DANGERLEVEL_WARNING	2
#define AALARM_DANGERLEVEL_BAD		3

// used in /obj/machinery/alarm
/datum/tlv
	var/bad_to_warn
	var/warn_to_good
	var/good_to_warn
	var/warn_to_bad

	// <- xxxxx|!!!!!!|......|!!!!!!|xxxxx ->
	//     bad   warn   good   warn   bad

	New(badToWarn as num, warnToGood as num, goodToWarn as num, warnToBad as num)
		bad_to_warn		= badToWarn
		warn_to_good	= warnToGood
		good_to_warn	= goodToWarn
		warn_to_bad		= warnToBad

	proc/get_danger_level(val as num)
		if (val <= bad_to_warn || val >= warn_to_bad)
			return AALARM_DANGERLEVEL_BAD
		if (val <= warn_to_good || val >= good_to_warn)
			return AALARM_DANGERLEVEL_WARNING

		return AALARM_DANGERLEVEL_GOOD

	proc/get_danger_class(val as num)
		var/lvl = get_danger_level(val)

		if (lvl == AALARM_DANGERLEVEL_GOOD)
			return "good"
		if (lvl == AALARM_DANGERLEVEL_WARNING)
			return "average"

		return "bad"


	proc/CopyFrom(datum/tlv/other)
		bad_to_warn		= other.bad_to_warn
		warn_to_good	= other.warn_to_good
		good_to_warn	= other.good_to_warn
		warn_to_bad		= other.warn_to_bad

/obj/machinery/alarm
	name = "alarm"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "alarm0"
	anchored = 1
	use_power = 1
	idle_power_usage = 4
	active_power_usage = 8
	power_channel = ENVIRON
	req_access = list(access_atmospherics)
	var/frequency = 1439
	//var/skipprocess = 0 //Experimenting
	var/alarm_frequency = 1437

	var/datum/radio_frequency/radio_connection
	var/locked = 1
	var/datum/wires/alarm/wires = null
	var/wiresexposed = 0 // If it's been screwdrivered open.
	var/aidisabled = 0
	var/AAlarmwires = 31
	var/shorted = 0
	var/buildstage = 2 // 2 = complete, 1 = no wires,  0 = circuit gone



	var/mode = AALARM_MODE_SCRUBBING

	var/list/screens = list(
		"info" = "info",
		"devices" = "devices",
		"sensors" = "sensors",
		"scrubbers" = "scrubbers",
		"vents" = "vents"
	)

	var/screen = "info"

	var/area_uid
	var/area/alarm_area
	var/danger_level = 0

	// breathable air according to human/Life()
	var/list/TLV = list(
		"oxygen"         = new/datum/tlv(  16,   19, 135, 140), // Partial pressure, kpa
		"carbon dioxide" = new/datum/tlv(-1.0, -1.0,   5,  10), // Partial pressure, kpa
		"plasma"         = new/datum/tlv(-1.0, -1.0, 0.2, 0.5), // Partial pressure, kpa
		"other"          = new/datum/tlv(-1.0, -1.0, 0.5, 1.0), // Partial pressure, kpa
		"pressure"       = new/datum/tlv(ONE_ATMOSPHERE*0.80,ONE_ATMOSPHERE*0.90,ONE_ATMOSPHERE*1.10,ONE_ATMOSPHERE*1.20), /* kpa */
		"temperature"    = new/datum/tlv(T0C, T0C+10, T0C+40, T0C+66), // K
	)

/*
	// breathable air according to wikipedia
		"oxygen"         = new/datum/tlv(   9,  12, 158, 296), // Partial pressure, kpa
		"carbon dioxide" = new/datum/tlv(-1.0,-1.0, 0.5,   1), // Partial pressure, kpa
*/
/obj/machinery/alarm/server
	//req_access = list(access_rd) //no, let departaments to work together
	TLV = list(
		"oxygen"         = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), // Partial pressure, kpa
		"carbon dioxide" = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), // Partial pressure, kpa
		"plasma"         = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), // Partial pressure, kpa
		"other"          = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), // Partial pressure, kpa
		"pressure"       = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), /* kpa */
		"temperature"    = new/datum/tlv(-1.0, -1.0,-1.0,-1.0), // K
	)

/obj/machinery/alarm/kitchen_cold_room
	TLV = list(
		"oxygen"         = new/datum/tlv(  16,   19, 135, 140), // Partial pressure, kpa
		"carbon dioxide" = new/datum/tlv(-1.0, -1.0,   5,  10), // Partial pressure, kpa
		"plasma"         = new/datum/tlv(-1.0, -1.0, 0.2, 0.5), // Partial pressure, kpa
		"other"          = new/datum/tlv(-1.0, -1.0, 0.5, 1.0), // Partial pressure, kpa
		"pressure"       = new/datum/tlv(ONE_ATMOSPHERE*0.80,ONE_ATMOSPHERE*0.90,ONE_ATMOSPHERE*1.50,ONE_ATMOSPHERE*1.60), /* kpa */
		"temperature"    = new/datum/tlv(200, 210, 273.15, 283.15), // K
	)

//all air alarms in area are connected via magic
/area
	var/obj/machinery/alarm/master_air_alarm
	var/list/air_vent_names = list()
	var/list/air_scrub_names = list()
	var/list/air_vent_info = list()
	var/list/air_scrub_info = list()

/obj/machinery/alarm/New(nloc, ndir, nbuild)
	..()
	wires = new(src)
	if(nloc)
		loc = nloc

	if(ndir)
		dir = ndir

	if(nbuild)
		buildstage = 0
		wiresexposed = 1
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -24 : 24)
		pixel_y = (dir & 3)? (dir ==1 ? -24 : 24) : 0

	alarm_area = get_area(loc)
	if (alarm_area.master)
		alarm_area = alarm_area.master
	area_uid = alarm_area.uid
	if (name == "alarm")
		name = "[alarm_area.name] Air Alarm"

	update_icon()
	if(ticker && ticker.current_state == 3)//if the game is running
		src.initialize()

/obj/machinery/alarm/initialize()
	set_frequency(frequency)
	if (!master_is_operating())
		elect_master()

/obj/machinery/alarm/proc/master_is_operating()
	return alarm_area.master_air_alarm && !(alarm_area.master_air_alarm.stat & (NOPOWER|BROKEN))

/obj/machinery/alarm/proc/elect_master()
	for (var/area/A in alarm_area.related)
		for (var/obj/machinery/alarm/AA in A)
			if (!(AA.stat & (NOPOWER|BROKEN)))
				alarm_area.master_air_alarm = AA
				return 1
	return 0

/obj/machinery/alarm/attack_hand(mob/user)
	. = ..()
	if (.)
		return
	user.set_machine(src)

	if ( (get_dist(src, user) > 1 ))
		if (!istype(user, /mob/living/silicon))
			user.unset_machine()
			user << browse(null, "window=AAlarmwires")
			return

	if(!shorted)
		ui_interact(user)

	if(wiresexposed && (!istype(user, /mob/living/silicon)))
		wires.Interact(user)

	return

/obj/machinery/alarm/proc/gen_val_danger_list(value as num, tlv_type)
	var/datum/tlv/cur = TLV[tlv_type]

	return list(
		"value" = value,
		"danger" = cur.get_danger_class(value)
	)

/obj/machinery/alarm/proc/gen_gas_list(pressure as num, total, tlv_type, gas_name)
	var/datum/tlv/cur = TLV[tlv_type]

	return list(
		"value" = pressure,
		"percentage" = (pressure * 100) / total,
		"name" = gas_name,
		"danger" = cur.get_danger_class(pressure)
	)

/obj/machinery/alarm/proc/danger_class_to_value(val)
	if (val == "good")
		return AALARM_DANGERLEVEL_GOOD
	if (val == "average")
		return AALARM_DANGERLEVEL_WARNING

	return AALARM_DANGERLEVEL_BAD

/obj/machinery/alarm/ui_interact(mob/user, ui_key = "info")
	if (!user)
		return

	var/turf/location = src.loc
	var/datum/gas_mixture/environment = location.return_air()
	var/total = environment.oxygen + environment.carbon_dioxide + environment.toxins + environment.nitrogen
	var/GET_PP = R_IDEAL_GAS_EQUATION*environment.temperature/environment.volume

	var/trace_gases = 0.0
	for(var/datum/gas/G in environment.trace_gases)
		trace_gases += G.moles

	var/list/tplData = list(
		"screen" = ui_key,
		"isLocked" = locked,
		"userIsSilicon" = istype(user, /mob/living/silicon),
		"siliconAccessForbidden" = src.aidisabled,
		"couldntObtainSample" = total == 0,
		"info" = list(
			"temperature" = gen_val_danger_list(environment.temperature, "temperature"),
			"pressure" = gen_val_danger_list(environment.return_pressure(), "pressure"),
			"gases" = list(
				gen_gas_list(environment.oxygen * GET_PP, total, "oxygen", "Oxygen"),
				gen_gas_list(environment.nitrogen * GET_PP, total, "nitrogen", "Nitrogen"),
				gen_gas_list(environment.carbon_dioxide * GET_PP, total, "carbon dioxide", "CO2"),
				gen_gas_list(environment.toxins * GET_PP, total, "plasma", "Toxins"),
				gen_gas_list(trace_gases * GET_PP, total, "other", "Miscellaneous")
			),
			"alarm" = 0,
			"habitability" = 1,
			"otherAlarmInArea" = 0
		),
		"devices" = list(
			"scrubbers" = list(),
			"vents" = list()
		)
	)

	var/max_danger_level = max(danger_class_to_value(tplData["info"]["temperature"]["danger"]), danger_class_to_value(tplData["info"]["pressure"]["danger"]))
	var/list/gasInfoList = tplData["info"]["gases"]

	for (var/list/L in gasInfoList)
		max_danger_level = max(max_danger_level, danger_class_to_value(L["danger"]))

	tplData["info"]["habitability"] = max_danger_level <= AALARM_DANGERLEVEL_WARNING
	tplData["info"]["alarm"] = alarm_area.atmosalm && max_danger_level != AALARM_DANGERLEVEL_GOOD
	tplData["info"]["otherAlarmInArea"] = alarm_area.atmosalm && max_danger_level == AALARM_DANGERLEVEL_GOOD

	var/datum/nanoui/ui = nanomanager.get_open_ui(user, src, "main")

	if (ui)
		ui.push_data(tplData)
		return
	else
		ui = new(user, src, ui_key, "airalarm.tmpl", "[alarm_area.name] Air Alarm", 500, 500)
		ui.set_initial_data(tplData)
		ui.open()
		ui.set_auto_update(1)
		return

/obj/machinery/alarm/proc/shock(mob/user, prb)
	if((stat & (NOPOWER)))		// unpowered, no shock
		return 0
	if(!prob(prb))
		return 0 //you lucked out, no shock for you
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, src)
	s.start() //sparks always.
	if (electrocute_mob(user, get_area(src), src))
		return 1
	else
		return 0

/obj/machinery/alarm/proc/refresh_all()
	for(var/id_tag in alarm_area.air_vent_names)
		var/list/I = alarm_area.air_vent_info[id_tag]
		if (I && I["timestamp"]+AALARM_REPORT_TIMEOUT/2 > world.time)
			continue
		send_signal(id_tag, list("status") )
	for(var/id_tag in alarm_area.air_scrub_names)
		var/list/I = alarm_area.air_scrub_info[id_tag]
		if (I && I["timestamp"]+AALARM_REPORT_TIMEOUT/2 > world.time)
			continue
		send_signal(id_tag, list("status") )

/obj/machinery/alarm/proc/set_frequency(new_frequency)
	radio_controller.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = radio_controller.add_object(src, frequency, RADIO_TO_AIRALARM)

/obj/machinery/alarm/proc/send_signal(var/target, var/list/command)//sends signal 'command' to 'target'. Returns 0 if no radio connection, 1 otherwise
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = 1 //radio signal
	signal.source = src

	signal.data = command
	signal.data["tag"] = target
	signal.data["sigtype"] = "command"

	radio_connection.post_signal(src, signal, RADIO_FROM_AIRALARM)
//			world << text("Signal [] Broadcasted to []", command, target)

	return 1


/*
	var/datum/tlv/cur_tlv
	var/GET_PP = R_IDEAL_GAS_EQUATION*environment.temperature/environment.volume

	cur_tlv = TLV["pressure"]
	var/environment_pressure = environment.return_pressure()
	var/pressure_dangerlevel = cur_tlv.get_danger_level(environment_pressure)

	cur_tlv = TLV["oxygen"]
	var/oxygen_dangerlevel = cur_tlv.get_danger_level(environment.oxygen*GET_PP)
	var/oxygen_percent = round(environment.oxygen / total * 100, 2)

	cur_tlv = TLV["carbon dioxide"]
	var/co2_dangerlevel = cur_tlv.get_danger_level(environment.carbon_dioxide*GET_PP)
	var/co2_percent = round(environment.carbon_dioxide / total * 100, 2)

	cur_tlv = TLV["plasma"]
	var/plasma_dangerlevel = cur_tlv.get_danger_level(environment.toxins*GET_PP)
	var/plasma_percent = round(environment.toxins / total * 100, 2)

	cur_tlv = TLV["other"]
	var/other_moles = 0.0
	for(var/datum/gas/G in environment.trace_gases)
		other_moles+=G.moles
	var/other_dangerlevel = cur_tlv.get_danger_level(other_moles*GET_PP)

	cur_tlv = TLV["temperature"]
	var/temperature_dangerlevel = cur_tlv.get_danger_level(environment.temperature) */

/obj/machinery/alarm/proc/apply_mode()
	switch(mode)
		if(AALARM_MODE_SCRUBBING)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list(
					"power"= 1,
					"co2_scrub"= 1,
					"scrubbing"= 1,
					"panic_siphon"= 0,
				))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list(
					"power"= 1,
					"checks"= 1,
					"set_external_pressure"= ONE_ATMOSPHERE
				))

		if(AALARM_MODE_VENTING)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list(
					"power"= 1,
					"panic_siphon"= 0,
					"scrubbing"= 0
				))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list(
					"power"= 1,
					"checks"= 1,
					"set_external_pressure"= ONE_ATMOSPHERE
				))
		if(
			AALARM_MODE_PANIC,
			AALARM_MODE_REPLACEMENT
		)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list(
					"power"= 1,
					"panic_siphon"= 1
				))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list(
					"power"= 0
				))
		if(AALARM_MODE_OFF)
			for(var/device_id in alarm_area.air_scrub_names)
				send_signal(device_id, list(
					"panic_siphon"= 0,
					"power"= 0
				))
			for(var/device_id in alarm_area.air_vent_names)
				send_signal(device_id, list(
					"power"= 0
				))

/obj/machinery/alarm/update_icon()
	if(wiresexposed)
		switch(buildstage)
			if(2)
				if(src.AAlarmwires == 0) // All wires cut
					icon_state = "alarm_b2"
				else
					icon_state = "alarmx"
			if(1)
				icon_state = "alarm_b2"
			if(0)
				icon_state = "alarm_b1"
		return

	if((stat & (NOPOWER|BROKEN)) || shorted)
		icon_state = "alarmp"
		return
	switch(max(danger_level, alarm_area.atmosalm))
		if (0)
			src.icon_state = "alarm0"
		if (1)
			src.icon_state = "alarm2" //yes, alarm2 is yellow alarm
		if (2)
			src.icon_state = "alarm1"

/obj/machinery/alarm/process()
	if((stat & (NOPOWER|BROKEN)) || shorted)
		return

	var/turf/simulated/location = src.loc
	if (!istype(location))
		return 0

	var/datum/gas_mixture/environment = location.return_air()

	var/datum/tlv/cur_tlv
	var/GET_PP = R_IDEAL_GAS_EQUATION*environment.temperature/environment.volume

	cur_tlv = TLV["pressure"]
	var/environment_pressure = environment.return_pressure()
	var/pressure_dangerlevel = cur_tlv.get_danger_level(environment_pressure)

	cur_tlv = TLV["oxygen"]
	var/oxygen_dangerlevel = cur_tlv.get_danger_level(environment.oxygen*GET_PP)

	cur_tlv = TLV["carbon dioxide"]
	var/co2_dangerlevel = cur_tlv.get_danger_level(environment.carbon_dioxide*GET_PP)

	cur_tlv = TLV["plasma"]
	var/plasma_dangerlevel = cur_tlv.get_danger_level(environment.toxins*GET_PP)

	cur_tlv = TLV["other"]
	var/other_moles = 0.0
	for(var/datum/gas/G in environment.trace_gases)
		other_moles+=G.moles
	var/other_dangerlevel = cur_tlv.get_danger_level(other_moles*GET_PP)

	cur_tlv = TLV["temperature"]
	var/temperature_dangerlevel = cur_tlv.get_danger_level(environment.temperature)

	var/old_danger_level = danger_level
	danger_level = max(
		pressure_dangerlevel,
		oxygen_dangerlevel,
		co2_dangerlevel,
		plasma_dangerlevel,
		other_dangerlevel,
		temperature_dangerlevel
	)
	if (old_danger_level!=danger_level)
		apply_danger_level()

	if (mode==AALARM_MODE_REPLACEMENT && environment_pressure<ONE_ATMOSPHERE*0.05)
		mode=AALARM_MODE_SCRUBBING
		apply_mode()

	//src.updateDialog()
	return

/obj/machinery/alarm/proc/post_alert(alert_level)

	var/datum/radio_frequency/frequency = radio_controller.return_frequency(alarm_frequency)

	if(!frequency) return

	var/datum/signal/alert_signal = new
	alert_signal.source = src
	alert_signal.transmission_method = 1
	alert_signal.data["zone"] = alarm_area.name
	alert_signal.data["type"] = "Atmospheric"

	if(alert_level==2)
		alert_signal.data["alert"] = "severe"
	else if (alert_level==1)
		alert_signal.data["alert"] = "minor"
	else if (alert_level==0)
		alert_signal.data["alert"] = "clear"

	frequency.post_signal(src, alert_signal)

/obj/machinery/alarm/proc/apply_danger_level()
	var/new_area_danger_level = 0
	for (var/area/A in alarm_area.related)
		for (var/obj/machinery/alarm/AA in A)
			if (!(AA.stat & (NOPOWER|BROKEN)) && !AA.shorted)
				new_area_danger_level = max(new_area_danger_level,AA.danger_level)
	if (alarm_area.atmosalert(new_area_danger_level)) //if area was in normal state or if area was in alert state
		post_alert(new_area_danger_level)
	update_icon()

/obj/machinery/alarm/attackby(obj/item/W as obj, mob/user as mob)
	switch(buildstage)
		if(2)
			if(istype(W, /obj/item/weapon/wirecutters) && AAlarmwires == 0)
				playsound(src.loc, 'sound/items/Wirecutter.ogg', 50, 1)
				user << "You cut the final wires."
				var/obj/item/weapon/cable_coil/cable = new /obj/item/weapon/cable_coil( src.loc )
				cable.amount = 5
				buildstage = 1
				update_icon()
				return

			if(istype(W, /obj/item/weapon/screwdriver))  // Opening that Air Alarm up.
				playsound(src.loc, 'sound/items/Screwdriver.ogg', 50, 1)
				wiresexposed = !wiresexposed
				user << "The wires have been [wiresexposed ? "exposed" : "unexposed"]"
				update_icon()
				return

			if (wiresexposed && ((istype(W, /obj/item/device/multitool) || istype(W, /obj/item/weapon/wirecutters))))
				return src.attack_hand(user)
			else if (istype(W, /obj/item/weapon/card/id) || istype(W, /obj/item/device/pda))// trying to unlock the interface with an ID card
				if(stat & (NOPOWER|BROKEN))
					user << "It does nothing"
				else
					if(src.allowed(usr) && !wires.IsIndexCut(AALARM_WIRE_IDSCAN))
						locked = !locked
						user << "\blue You [ locked ? "lock" : "unlock"] the Air Alarm interface."
					else
						user << "\red Access denied."
				return
		if(1)
			if(istype(W, /obj/item/weapon/crowbar) && AAlarmwires == 0)
				user << "You pry out the circuit."
				playsound(src.loc, 'sound/items/Crowbar.ogg', 50, 1)
				spawn(20)
					new /obj/item/weapon/airalarm_electronics( src.loc )
					playsound(src.loc, 'sound/items/Deconstruct.ogg', 50, 1)
					buildstage = 0
					update_icon()
				return

			if(istype(W, /obj/item/weapon/cable_coil))
				var/obj/item/weapon/cable_coil/cable = W
				if(cable.amount < 5)
					user << "You need more cable!"
					return

				user << "You start wiring the air alarm!"
				spawn(20)
					cable.amount -= 5
					if(!cable.amount)
						del(cable)

					user << "You wire the air alarm!"
					src.AAlarmwires = 31
					buildstage = 2
					update_icon()
				return
		if(0)
			if(istype(W, /obj/item/weapon/airalarm_electronics))
				user << "You insert the circuit!"
				buildstage = 1
				update_icon()
				user.drop_item()
				del(W)
				return

			if(istype(W, /obj/item/weapon/wrench))
				user << "You detach \the [src] from the wall!"
				playsound(src.loc, 'sound/items/Ratchet.ogg', 50, 1)
				new /obj/item/alarm_frame( user.loc )
				del(src)
				return

	return ..()

/obj/machinery/alarm/power_change()
	if(powered(power_channel))
		stat &= ~NOPOWER
	else
		stat |= NOPOWER
	spawn(rand(0,15))
		update_icon()

/*
AIR ALARM CIRCUIT
Just a object used in constructing air alarms
*/
/obj/item/weapon/airalarm_electronics
	name = "air alarm electronics"
	icon = 'icons/obj/module.dmi'
	icon_state = "airalarm_electronics"
	desc = "Looks like a circuit. Probably is."
	w_class = 2.0
	m_amt = 50
	g_amt = 50


/*
AIR ALARM ITEM
Handheld air alarm frame, for placing on walls
Code shamelessly copied from apc_frame
*/
/obj/item/alarm_frame
	name = "air alarm frame"
	desc = "Used for building Air Alarms"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "alarm_bitem"
	flags = FPRINT | TABLEPASS| CONDUCT

/obj/item/alarm_frame/attackby(obj/item/weapon/W as obj, mob/user as mob)
	if (istype(W, /obj/item/weapon/wrench))
		new /obj/item/stack/sheet/metal( get_turf(src.loc), 2 )
		del(src)
		return
	..()

/obj/item/alarm_frame/proc/try_build(turf/on_wall)
	if (get_dist(on_wall,usr)>1)
		return

	var/ndir = get_dir(on_wall,usr)
	if (!(ndir in cardinal))
		return

	var/turf/loc = get_turf(usr)
	var/area/A = loc.loc
	if (!istype(loc, /turf/simulated/floor))
		usr << "\red Air Alarm cannot be placed on this spot."
		return
	if (A.requires_power == 0 || A.name == "Space")
		usr << "\red Air Alarm cannot be placed in this area."
		return

	if(gotwallitem(loc, ndir))
		usr << "\red There's already an item on this wall!"
		return

	new /obj/machinery/alarm(loc, ndir, 1)

	del(src)


/*
FIRE ALARM
*/
/obj/machinery/firealarm
	name = "fire alarm"
	desc = "<i>\"Pull this in case of emergency\"<i>. Thus, keep pulling it forever."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "fire0"
	var/detecting = 1.0
	var/working = 1.0
	var/time = 10.0
	var/timing = 0.0
	var/lockdownbyai = 0
	anchored = 1.0
	use_power = 1
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON
	var/last_process = 0
	var/wiresexposed = 0
	var/buildstage = 2 // 2 = complete, 1 = no wires,  0 = circuit gone

/obj/machinery/firealarm/update_icon()

	if(wiresexposed)
		switch(buildstage)
			if(2)
				icon_state="fire_b2"
			if(1)
				icon_state="fire_b1"
			if(0)
				icon_state="fire_b0"

		return

	if(stat & BROKEN)
		icon_state = "firex"
	else if(stat & NOPOWER)
		icon_state = "firep"
	else if(!src.detecting)
		icon_state = "fire1"
	else
		icon_state = "fire0"

/obj/machinery/firealarm/temperature_expose(datum/gas_mixture/air, temperature, volume)
	if(src.detecting)
		if(temperature > T0C+200)
			src.alarm()			// added check of detector status here
	return

/obj/machinery/firealarm/attack_ai(mob/user as mob)
	return src.attack_hand(user)

/obj/machinery/firealarm/bullet_act(BLAH)
	return src.alarm()

/obj/machinery/firealarm/attack_paw(mob/user as mob)
	return src.attack_hand(user)

/obj/machinery/firealarm/emp_act(severity)
	if(prob(50/severity)) alarm()
	..()

/obj/machinery/firealarm/attackby(obj/item/W as obj, mob/user as mob)
	src.add_fingerprint(user)

	if (istype(W, /obj/item/weapon/screwdriver) && buildstage == 2)
		wiresexposed = !wiresexposed
		update_icon()
		return

	if(wiresexposed)
		switch(buildstage)
			if(2)
				if (istype(W, /obj/item/device/multitool))
					src.detecting = !( src.detecting )
					if (src.detecting)
						user.visible_message("\red [user] has reconnected [src]'s detecting unit!", "You have reconnected [src]'s detecting unit.")
					else
						user.visible_message("\red [user] has disconnected [src]'s detecting unit!", "You have disconnected [src]'s detecting unit.")

				else if (istype(W, /obj/item/weapon/wirecutters))
					buildstage = 1
					playsound(src.loc, 'sound/items/Wirecutter.ogg', 50, 1)
					var/obj/item/weapon/cable_coil/coil = new /obj/item/weapon/cable_coil()
					coil.amount = 5
					coil.loc = user.loc
					user << "You cut the wires from \the [src]"
					update_icon()
			if(1)
				if(istype(W, /obj/item/weapon/cable_coil))
					var/obj/item/weapon/cable_coil/coil = W
					if(coil.amount < 5)
						user << "You need more cable for this!"
						return

					coil.amount -= 5
					if(!coil.amount)
						del(coil)

					buildstage = 2
					user << "You wire \the [src]!"
					update_icon()

				else if(istype(W, /obj/item/weapon/crowbar))
					user << "You pry out the circuit!"
					playsound(src.loc, 'sound/items/Crowbar.ogg', 50, 1)
					spawn(20)
						var/obj/item/weapon/firealarm_electronics/circuit = new /obj/item/weapon/firealarm_electronics()
						circuit.loc = user.loc
						buildstage = 0
						update_icon()
			if(0)
				if(istype(W, /obj/item/weapon/firealarm_electronics))
					user << "You insert the circuit!"
					del(W)
					buildstage = 1
					update_icon()

				else if(istype(W, /obj/item/weapon/wrench))
					user << "You remove the fire alarm assembly from the wall!"
					var/obj/item/firealarm_frame/frame = new /obj/item/firealarm_frame()
					frame.loc = user.loc
					playsound(src.loc, 'sound/items/Ratchet.ogg', 50, 1)
					del(src)
		return

	src.alarm()
	return

/obj/machinery/firealarm/process()//Note: this processing was mostly phased out due to other code, and only runs when needed
	if(stat & (NOPOWER|BROKEN))
		return

	if(src.timing)
		if(src.time > 0)
			src.time = src.time - ((world.timeofday - last_process)/10)
		else
			src.alarm()
			src.time = 0
			src.timing = 0
			processing_objects.Remove(src)
		src.updateDialog()
	last_process = world.timeofday
	return

/obj/machinery/firealarm/power_change()
	if(powered(ENVIRON))
		stat &= ~NOPOWER
		update_icon()
	else
		spawn(rand(0,15))
			stat |= NOPOWER
			update_icon()

/obj/machinery/firealarm/attack_hand(mob/user as mob)
	if(user.stat || stat & (NOPOWER|BROKEN))
		return

	if (buildstage != 2)
		return

	user.set_machine(src)
	var/area/A = src.loc
	var/d1
	var/d2
	var/dat = ""
	if (istype(user, /mob/living/carbon/human) || istype(user, /mob/living/silicon))
		A = A.loc

		if (A.fire)
			d1 = text("<A href='?src=\ref[];reset=1'>Reset - Lockdown</A>", src)
		else
			d1 = text("<A href='?src=\ref[];alarm=1'>Alarm - Lockdown</A>", src)
		if (src.timing)
			d2 = text("<A href='?src=\ref[];time=0'>Stop Time Lock</A>", src)
		else
			d2 = text("<A href='?src=\ref[];time=1'>Initiate Time Lock</A>", src)
		var/second = round(src.time) % 60
		var/minute = (round(src.time) - second) / 60
		dat = "[d1]<br /><b>The current alert level is: [get_security_level()]</b><br /><br />Timer System: [d2]<br />Time Left: <A href='?src=\ref[src];tp=-30'>-</A> <A href='?src=\ref[src];tp=-1'>-</A> [(minute ? "[minute]:" : null)][second] <A href='?src=\ref[src];tp=1'>+</A> <A href='?src=\ref[src];tp=30'>+</A>"
		//user << browse(dat, "window=firealarm")
		//onclose(user, "firealarm")
	else
		A = A.loc
		if (A.fire)
			d1 = text("<A href='?src=\ref[];reset=1'>[]</A>", src, stars("Reset - Lockdown"))
		else
			d1 = text("<A href='?src=\ref[];alarm=1'>[]</A>", src, stars("Alarm - Lockdown"))
		if (src.timing)
			d2 = text("<A href='?src=\ref[];time=0'>[]</A>", src, stars("Stop Time Lock"))
		else
			d2 = text("<A href='?src=\ref[];time=1'>[]</A>", src, stars("Initiate Time Lock"))
		var/second = round(src.time) % 60
		var/minute = (round(src.time) - second) / 60
		dat = "[d1]<br /><b>The current alert level is: [stars(get_security_level())]</b><br /><br />Timer System: [d2]<br />Time Left: <A href='?src=\ref[src];tp=-30'>-</A> <A href='?src=\ref[src];tp=-1'>-</A> [(minute ? text("[]:", minute) : null)][second] <A href='?src=\ref[src];tp=1'>+</A> <A href='?src=\ref[src];tp=30'>+</A>"
		//user << browse(dat, "window=firealarm")
		//onclose(user, "firealarm")
	var/datum/browser/popup = new(user, "firealarm", "Fire Alarm")
	popup.set_content(dat)
	popup.set_title_image(user.browse_rsc_icon(src.icon, src.icon_state))
	popup.open()
	return

/obj/machinery/firealarm/Topic(href, href_list)
	if(..())
		return

	if (buildstage != 2)
		return

	usr.set_machine(src)
	if (href_list["reset"])
		src.reset()
	else if (href_list["alarm"])
		src.alarm()
	else if (href_list["time"])
		src.timing = text2num(href_list["time"])
		last_process = world.timeofday
		processing_objects.Add(src)
	else if (href_list["tp"])
		var/tp = text2num(href_list["tp"])
		src.time += tp
		src.time = min(max(round(src.time), 0), 120)

	src.updateUsrDialog()

/obj/machinery/firealarm/proc/reset()
	if (!( src.working ))
		return
	var/area/A = src.loc
	A = A.loc
	if (!( istype(A, /area) ))
		return
	for(var/area/RA in A.related)
		RA.firereset()
	update_icon()
	return

/obj/machinery/firealarm/proc/alarm()
	if (!( src.working ))
		return
	var/area/A = src.loc
	A = A.loc
	if (!( istype(A, /area) ))
		return
	for(var/area/RA in A.related)
		RA.firealert()
	update_icon()
	//playsound(src.loc, 'sound/ambience/signal.ogg', 75, 0)
	return

/obj/machinery/firealarm/New(loc, dir, building)
	..()

	if(loc)
		src.loc = loc

	if(dir)
		src.dir = dir

	if(building)
		buildstage = 0
		wiresexposed = 1
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -24 : 24)
		pixel_y = (dir & 3)? (dir ==1 ? -24 : 24) : 0

	if(z == 1)
		if(security_level)
			src.overlays += image('icons/obj/monitors.dmi', "overlay_[get_security_level()]")
		else
			src.overlays += image('icons/obj/monitors.dmi', "overlay_green")

	update_icon()

/*
FIRE ALARM CIRCUIT
Just a object used in constructing fire alarms
*/
/obj/item/weapon/firealarm_electronics
	name = "fire alarm electronics"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_electronics"
	desc = "A circuit. It has a label on it, it says \"Can handle heat levels up to 40 degrees celsius!\""
	w_class = 2.0
	m_amt = 50
	g_amt = 50


/*
FIRE ALARM ITEM
Handheld fire alarm frame, for placing on walls
Code shamelessly copied from apc_frame
*/
/obj/item/firealarm_frame
	name = "fire alarm frame"
	desc = "Used for building Fire Alarms"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "fire_bitem"
	flags = FPRINT | TABLEPASS| CONDUCT


/*
 * Party button
 */

/obj/machinery/partyalarm
	name = "\improper PARTY BUTTON"
	desc = "Cuban Pete is in the house!"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "fire0"
	var/detecting = 1.0
	var/working = 1.0
	var/time = 10.0
	var/timing = 0.0
	var/lockdownbyai = 0
	anchored = 1.0
	use_power = 1
	idle_power_usage = 2
	active_power_usage = 6

/obj/item/firealarm_frame/attackby(obj/item/weapon/W as obj, mob/user as mob)
	if (istype(W, /obj/item/weapon/wrench))
		new /obj/item/stack/sheet/metal( get_turf(src.loc), 2 )
		del(src)
		return
	..()

/obj/item/firealarm_frame/proc/try_build(turf/on_wall)
	if (get_dist(on_wall,usr)>1)
		return

	var/ndir = get_dir(on_wall,usr)
	if (!(ndir in cardinal))
		return

	var/turf/loc = get_turf(usr)
	var/area/A = loc.loc
	if (!istype(loc, /turf/simulated/floor))
		usr << "\red Fire Alarm cannot be placed on this spot."
		return
	if (A.requires_power == 0 || A.name == "Space")
		usr << "\red Fire Alarm cannot be placed in this area."
		return

	if(gotwallitem(loc, ndir))
		usr << "\red There's already an item on this wall!"
		return

	new /obj/machinery/firealarm(loc, ndir, 1)

	del(src)

/obj/machinery/partyalarm/attack_paw(mob/user as mob)
	return src.attack_hand(user)
/obj/machinery/partyalarm/attack_hand(mob/user as mob)
	if(user.stat || stat & (NOPOWER|BROKEN))
		return

	user.set_machine(src)
	var/area/A = src.loc
	var/d1
	var/d2
	if (istype(user, /mob/living/carbon/human) || istype(user, /mob/living/silicon/ai))
		A = A.loc

		if (A.party)
			d1 = text("<A href='?src=\ref[];reset=1'>No Party :(</A>", src)
		else
			d1 = text("<A href='?src=\ref[];alarm=1'>PARTY!!!</A>", src)
		if (src.timing)
			d2 = text("<A href='?src=\ref[];time=0'>Stop Time Lock</A>", src)
		else
			d2 = text("<A href='?src=\ref[];time=1'>Initiate Time Lock</A>", src)
		var/second = src.time % 60
		var/minute = (src.time - second) / 60
		var/dat = text("<HTML><HEAD></HEAD><BODY><TT><B>Party Button</B> []\n<HR>\nTimer System: []<br />\nTime Left: [][] <A href='?src=\ref[];tp=-30'>-</A> <A href='?src=\ref[];tp=-1'>-</A> <A href='?src=\ref[];tp=1'>+</A> <A href='?src=\ref[];tp=30'>+</A>\n</TT></BODY></HTML>", d1, d2, (minute ? text("[]:", minute) : null), second, src, src, src, src)
		user << browse(dat, "window=partyalarm")
		onclose(user, "partyalarm")
	else
		A = A.loc
		if (A.fire)
			d1 = text("<A href='?src=\ref[];reset=1'>[]</A>", src, stars("No Party :("))
		else
			d1 = text("<A href='?src=\ref[];alarm=1'>[]</A>", src, stars("PARTY!!!"))
		if (src.timing)
			d2 = text("<A href='?src=\ref[];time=0'>[]</A>", src, stars("Stop Time Lock"))
		else
			d2 = text("<A href='?src=\ref[];time=1'>[]</A>", src, stars("Initiate Time Lock"))
		var/second = src.time % 60
		var/minute = (src.time - second) / 60
		var/dat = text("<HTML><HEAD></HEAD><BODY><TT><B>[]</B> []\n<HR>\nTimer System: []<br />\nTime Left: [][] <A href='?src=\ref[];tp=-30'>-</A> <A href='?src=\ref[];tp=-1'>-</A> <A href='?src=\ref[];tp=1'>+</A> <A href='?src=\ref[];tp=30'>+</A>\n</TT></BODY></HTML>", stars("Party Button"), d1, d2, (minute ? text("[]:", minute) : null), second, src, src, src, src)
		user << browse(dat, "window=partyalarm")
		onclose(user, "partyalarm")
	return

/obj/machinery/partyalarm/proc/reset()
	if (!( src.working ))
		return
	var/area/A = src.loc
	A = A.loc
	if (!( istype(A, /area) ))
		return
	A.partyreset()
	return

/obj/machinery/partyalarm/proc/alarm()
	if (!( src.working ))
		return
	var/area/A = src.loc
	A = A.loc
	if (!( istype(A, /area) ))
		return
	A.partyalert()
	return

/obj/machinery/partyalarm/Topic(href, href_list)
	if(..())
		return
	if (usr.stat || stat & (BROKEN|NOPOWER))
		return
	if ((usr.contents.Find(src) || ((get_dist(src, usr) <= 1) && istype(src.loc, /turf))) || (istype(usr, /mob/living/silicon/ai)))
		usr.set_machine(src)
		if (href_list["reset"])
			src.reset()
		else
			if (href_list["alarm"])
				src.alarm()
			else
				if (href_list["time"])
					src.timing = text2num(href_list["time"])
				else
					if (href_list["tp"])
						var/tp = text2num(href_list["tp"])
						src.time += tp
						src.time = min(max(round(src.time), 0), 120)
		src.updateUsrDialog()

		src.add_fingerprint(usr)
	else
		usr << browse(null, "window=partyalarm")
		return
	return
