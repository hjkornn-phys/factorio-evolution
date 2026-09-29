-- Builds the experiment in experiment.lua at the first tick, then every
-- `window` ticks after `warmup` writes one CSV line per sink and empties it.
-- Output: script-output/lab/<name>.csv, columns tick,sink,count.
local exp = require("experiment")

local function out_path()
  return "lab/" .. exp.name .. ".csv"
end

-- Growth (exp.growth): seeds laid one by one as ghosts of a blueprint at
-- given slots; a slot is built when no ghost is left in its area, and each
-- built slot lays per_done more (the seed-layer a circuit cannot be).
local function lay_seed(i, bp)
  local g = exp.growth
  local s = g.slots[i]
  local inv = game.create_inventory(1)
  local st = inv[1]
  st.set_stack{name = "blueprint"}
  -- bp: which of g.strings (a lineage's blueprint); none: g.string.
  if st.import_stack(bp and g.strings[bp] or g.string) ~= 0 then error("growth blueprint import failed") end
  -- shift: each lineage's offset of its blueprint's centre (a wider blueprint centres elsewhere).
  local sh = g.shift and g.shift[bp or 1] or {0, 0}
  local ghosts = st.build_blueprint{surface = game.surfaces[1], force = game.forces.player,
                                    position = {s.position[1] + sh[1], s.position[2] + sh[2]},
                                    build_mode = defines.build_mode.forced, skip_fog_of_war = false}
  local placed, anchors = 0, {}
  for _, gh in ipairs(ghosts) do
    if gh.valid and gh.type == "entity-ghost" then
      placed = placed + 1
      if gh.ghost_name == g.anchor then anchors[#anchors + 1] = gh end
    end
  end
  inv.destroy()
  -- expect: one count, or (a table) each lineage's own, indexed as g.strings.
  local want = type(g.expect) == "table" and g.expect[bp or 1] or g.expect
  if placed ~= want then
    -- Name what stands in the seed's area, so the fault says what blocked it.
    local what = {}
    for _, x in pairs(game.surfaces[1].find_entities_filtered{area = s.area}) do
      if x.type ~= "entity-ghost" then what[x.name .. "/" .. x.force.name] = (what[x.name .. "/" .. x.force.name] or 0) + 1 end
    end
    local list = {}
    for k, n in pairs(what) do list[#list + 1] = k .. " " .. n end
    error("growth seed " .. i .. " placed " .. placed .. " ghosts, expected " .. want ..
          "; in its area: " .. table.concat(list, ", "))
  end
  -- One ghost of the anchor's name must stand exactly at the slot's anchor.
  local hit, seen = false, {}
  for _, an in ipairs(anchors) do
    local a = an.position
    if math.abs(a.x - s.anchor[1]) <= 0.01 and math.abs(a.y - s.anchor[2]) <= 0.01 then hit = true end
    seen[#seen + 1] = a.x .. "," .. a.y
  end
  if not hit then
    error("growth seed " .. i .. ": no " .. g.anchor .. " at " .. s.anchor[1] .. "," .. s.anchor[2] ..
          " (found at " .. table.concat(seen, "; ") .. ")")
  end
  storage.growth.pending[i] = true
  storage.growth.laid = storage.growth.laid + 1
end

local function setup()
  local surface = game.surfaces[1]
  if exp.chunks_radius then
    -- Generate every chunk within this many chunks of the origin, now,
    -- inside the setup tick that the timing drops.
    surface.request_to_generate_chunks({0, 0}, exp.chunks_radius)
    surface.force_generate_chunk_requests()
  end
  local a = exp.area
  for _, e in pairs(surface.find_entities_filtered{area = a}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = a[1][1], a[2][1] - 1 do
    for y = a[1][2], a[2][2] - 1 do
      tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}}
    end
  end
  surface.set_tiles(tiles, true, true, true)
  local force = game.forces.player
  for _, tech in ipairs(exp.research or {}) do
    force.technologies[tech].researched = true
  end
  local by_tag = {}
  storage.sinks = {}
  storage.belt_sinks = {}
  local off = {x = 0, y = 0}
  -- One blueprint, or several (blueprints, each with its own anchor); the
  -- offset used by bp = true below is the first's.
  for bi, bp in ipairs(exp.blueprints or {exp.blueprint}) do
    -- A blueprint string built at a position and its ghosts revived. Its own
    -- coordinates are re-anchored by one entity (anchor: name, x, y in the
    -- blueprint's coordinates); entities with bp = true below, and the
    -- blueprint's tags, are given in those coordinates.
    local inv = game.create_inventory(1)
    local st = inv[1]
    st.set_stack{name = "blueprint"}
    if st.import_stack(bp.string) ~= 0 then error("blueprint import failed") end
    local ghosts = st.build_blueprint{surface = surface, force = force, position = bp.position,
                                      build_mode = defines.build_mode.forced, skip_fog_of_war = false}
    local revived, failed, placed = 0, 0, 0
    for _, g in ipairs(ghosts) do
      if g.valid and g.type == "entity-ghost" then
        placed = placed + 1
        if not bp.ghost then
          local _, ent = g.revive()
          if ent then revived = revived + 1 else failed = failed + 1 end
        end
      end
    end
    inv.destroy()
    if bp.ghost then
      -- Ghosts only (a plan for construction robots): the count placed must match.
      if placed ~= bp.expect then error("blueprint placed " .. placed .. " ghosts, expected " .. tostring(bp.expect)) end
    elseif failed > 0 or revived ~= bp.expect then
      error("blueprint revived " .. revived .. " (failed " .. failed .. "), expected " .. tostring(bp.expect))
    end
    local found = {}
    if bp.ghost then
      -- Among this blueprint's own ghosts, so several copies can share an anchor name.
      for _, g in ipairs(ghosts) do
        if g.valid and g.type == "entity-ghost" and g.ghost_name == bp.anchor.name then found[#found + 1] = g end
      end
    else
      found = surface.find_entities_filtered{name = bp.anchor.name, area = a}
    end
    if #found ~= 1 then error("blueprint anchor " .. bp.anchor.name .. " found " .. #found .. " times") end
    local o = {x = found[1].position.x - bp.anchor.x, y = found[1].position.y - bp.anchor.y}
    for tag, t in pairs(bp.tags or {}) do
      local ent = surface.find_entity(t.name, {t.x + o.x, t.y + o.y})
      if not ent then error("blueprint tag " .. tag .. ": no " .. t.name .. " at " .. t.x .. "," .. t.y) end
      by_tag[tag] = ent
    end
    for _, c in ipairs(bp.config or {}) do
      local cb = by_tag[c.tag].get_or_create_control_behavior()
      if c.constant then
        -- One more slot in the first section of a constant combinator.
        local sec = cb.get_section(1) or cb.add_section()
        local n = c.constant.signal
        sec.set_slot(sec.filters_count + 1, {value = {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n, quality = "normal"}, min = c.constant.count})
      end
      if c.input_networks then cb.input_networks = c.input_networks end
      if c.output_networks then cb.output_networks = c.output_networks end
    end
    for _, k in ipairs(bp.sinks or {}) do
      storage.sinks[#storage.sinks + 1] = {id = k.id, entity = by_tag[k.tag], by_item = k.by_item, keep = k.keep}
    end
    if bi == 1 then
      off = o
      storage.bp_off = o
    end
  end
  for _, e in ipairs(exp.entities) do
    local pos = e.bp and {e.position[1] + off.x, e.position[2] + off.y} or e.position
    local ent = surface.create_entity{
      name = e.name, position = pos, force = force,
      direction = e.direction and defines.direction[e.direction] or nil,
      create_build_effect_smoke = false,
    }
    if not ent then error("could not create " .. e.name .. " at " .. serpent.line(e.position)) end
    if e.tag then by_tag[e.tag] = ent end
    if e.recipe then ent.set_recipe(e.recipe) end
    if e.decider then
      -- A decider combinator. Either one condition (cond) -> one output copying input
      -- counts, or conds (ANDed, or ORed where a cond says compare = "or"; each with constant
      -- or second signal) -> outputs
      -- (each copying input, or a constant).
      local sig = function(n) return {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n} end
      local conds, outs = {}, {}
      for i, c in ipairs(e.decider.conds or {e.decider.cond}) do
        local x = {first_signal = sig(c.signal), comparator = c.comparator}
        if c.second then x.second_signal = sig(c.second) else x.constant = c.constant end
        if i > 1 then x.compare_type = c.compare or "and" end   -- "or" starts a new clause
        -- Optional: which input wire the condition reads ({red = , green = }).
        if c.networks then x.first_signal_networks = c.networks end
        conds[#conds + 1] = x
      end
      for _, o in ipairs(e.decider.outputs or {{signal = e.decider.output}}) do
        if o.constant then
          outs[#outs + 1] = {signal = sig(o.signal), copy_count_from_input = false, constant = o.constant}
        else
          -- Optional: which input wire the copied count comes from.
          outs[#outs + 1] = {signal = sig(o.signal), copy_count_from_input = true, networks = o.networks}
        end
      end
      ent.get_or_create_control_behavior().parameters = {conditions = conds, outputs = outs}
    end
    if e.constant then
      -- A constant combinator emitting one signal.
      local cb = ent.get_or_create_control_behavior()
      local sec = cb.get_section(1) or cb.add_section()
      -- One signal (signal, count), or several (signals: a list of {signal, count}).
      for i, k in ipairs(e.constant.signals or {{signal = e.constant.signal, count = e.constant.count}}) do
        local n = k.signal
        sec.set_slot(i, {value = {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n, quality = "normal"}, min = k.count})
      end
      if e.constant.enabled ~= nil then cb.enabled = e.constant.enabled end
    end
    if e.arith then
      -- An arithmetic combinator: first (a signal name, e.g. signal-each) op constant -> output.
      local sig = function(n) return {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n} end
      -- The second operand: a constant, or a signal (second, e.g. signal-each).
      local prm = {first_signal = sig(e.arith.first), operation = e.arith.op, output_signal = sig(e.arith.output)}
      if e.arith.second then prm.second_signal = sig(e.arith.second) else prm.second_constant = e.arith.constant end
      ent.get_or_create_control_behavior().parameters = prm
    end
    if e.selector then
      -- A selector combinator: its parameters as given (e.g. operation "select",
      -- select_max, index_constant).
      ent.get_or_create_control_behavior().parameters = e.selector
    end
    if e.control then
      local cb = ent.get_or_create_control_behavior()
      if e.control.read_contents ~= nil then cb.circuit_read_contents = e.control.read_contents end
      if e.control.read_mode then
        -- A belt's read mode: pulse, hold or entire_belt_hold.
        cb.read_contents = true
        cb.read_contents_mode = defines.control_behavior.transport_belt.content_read_mode[e.control.read_mode]
      end
      if e.control.include_in_crafting ~= nil then cb.include_in_crafting = e.control.include_in_crafting end
      -- The 2.1.7 wire selection: which wires an entity reads, and which it sends on.
      if e.control.input_networks then cb.input_networks = e.control.input_networks end
      if e.control.output_networks then cb.output_networks = e.control.output_networks end
      if e.control.enable_condition then
        local c = e.control.enable_condition
        cb.circuit_enable_disable = true
        cb.circuit_condition = {first_signal = {type = (c.signal:sub(1, 7) == "signal-") and "virtual" or "item", name = c.signal},
                                comparator = c.comparator, constant = c.constant}
      end
      if e.control.set_filters then
        -- Filters set from the circuit network (whitelist).
        ent.use_filters = true
        ent.inserter_filter_mode = "whitelist"
        cb.circuit_set_filters = true
      end
      if e.control.read_hand then
        -- An inserter's hand read: pulse or hold.
        cb.circuit_read_hand_contents = true
        cb.circuit_hand_read_mode = defines.control_behavior.inserter.hand_read_mode[e.control.read_hand]
      end
      if e.control.splitter_set_filter then
        -- A splitter whose filter comes from its circuit network.
        cb.set_filter = true
      end
      if e.control.output_left or e.control.output_right then
        -- A splitter's output side set by two conditions (left, right), each
        -- {signal, comparator, constant}.
        local sc = function(c) return {first_signal = {type = (c.signal:sub(1, 7) == "signal-") and "virtual" or "item", name = c.signal},
                                       comparator = c.comparator, constant = c.constant} end
        cb.set_output_side = true
        if e.control.output_left then cb.output_left_condition = sc(e.control.output_left) end
        if e.control.output_right then cb.output_right_condition = sc(e.control.output_right) end
      end
      if e.control.input_left or e.control.input_right then
        -- A splitter's input side set by two conditions (left, right), as the output side.
        local sc = function(c) return {first_signal = {type = (c.signal:sub(1, 7) == "signal-") and "virtual" or "item", name = c.signal},
                                       comparator = c.comparator, constant = c.constant} end
        cb.set_input_side = true
        if e.control.input_left then cb.input_left_condition = sc(e.control.input_left) end
        if e.control.input_right then cb.input_right_condition = sc(e.control.input_right) end
      end
      if e.control.set_requests then
        -- A requester or buffer chest whose requests come from its circuit network.
        -- Its contents are read onto the same network by default (2.1.7 allows both);
        -- that adds the contents to the request, so reading is off unless asked for.
        cb.set_requests = true
        cb.read_contents = e.control.read_logistic_contents == true
      end
      if e.control.set_recipe then
        -- A crafting machine that takes its recipe from the circuit network.
        cb.circuit_set_recipe = true
      end
      if e.control.read_ingredients then
        -- A crafting machine that outputs its current recipe's ingredients.
        cb.circuit_read_ingredients = true
      end
      if e.control.working_signal then
        -- A crafting machine's signal while it works.
        cb.circuit_read_working = true
        cb.circuit_working_signal = {type = (e.control.working_signal:sub(1, 7) == "signal-") and "virtual" or "item", name = e.control.working_signal}
      end
      if e.control.finished_signal then
        -- A crafting machine's pulse when a recipe finishes.
        cb.circuit_read_recipe_finished = true
        cb.circuit_recipe_finished_signal = {type = (e.control.finished_signal:sub(1, 7) == "signal-") and "virtual" or "item", name = e.control.finished_signal}
      end
      if e.control.stack_signal then
        -- An inserter's hand size set from a signal.
        cb.circuit_set_stack_size = true
        cb.circuit_stack_control_signal = {type = (e.control.stack_signal:sub(1, 7) == "signal-") and "virtual" or "item", name = e.control.stack_signal}
      end
    end
    if e.contents then
      -- One {item, count}, or a list of them (put in in that order).
      local list = e.contents.item and {e.contents} or e.contents
      for _, c in ipairs(list) do
        ent.get_inventory(defines.inventory.chest).insert{name = c.item, count = c.count}
      end
    end
    if e.modules then
      local inv = ent.get_module_inventory()
      if not inv or inv.insert{name = e.modules.item, count = e.modules.count} ~= e.modules.count then
        error("could not insert " .. e.modules.count .. " " .. e.modules.item .. " into " .. e.name)
      end
    end
    if e.belt_items then
      -- Items laid on one lane of this belt, 0.25 apart from its start (or
      -- from `offset`); a list lays several lanes.
      for _, bi in ipairs(e.belt_items[1] and e.belt_items or {e.belt_items}) do
        local line = ent.get_transport_line(bi.line)
        for i = 1, bi.count do
          if not line.insert_at((bi.offset or 0) + (i - 1) * 0.25, {name = bi.item, count = 1}) then
            error("could not lay item " .. i .. " on " .. e.name .. " at " .. serpent.line(e.position))
          end
        end
      end
    end
    if e.filter or e.filters then
      -- filter_mode: "whitelist" (the default) or "blacklist".
      ent.use_filters = true
      ent.inserter_filter_mode = e.filter_mode or "whitelist"
      for i, f in ipairs(e.filters or {e.filter}) do ent.set_filter(i, f) end
    end
    if e.group then
      -- An observed group, e.g. the belts of one unit: its items are summed.
      storage.groups = storage.groups or {}
      storage.groups[e.group] = storage.groups[e.group] or {}
      table.insert(storage.groups[e.group], ent)
    end
    if e.expect_beacons then
      storage.expect = storage.expect or {}
      storage.expect[#storage.expect + 1] = {tag = e.tag or e.name, entity = ent, n = e.expect_beacons}
    end
    if e.output_priority then
      -- A splitter's output priority ("left", "right", "none"); a filter acts only with one set.
      ent.splitter_output_priority = e.output_priority
    end
    if e.robots then
      -- Robots placed in a roboport's robot inventory: one kind, or a list of kinds.
      local inv = ent.get_inventory(defines.inventory.roboport_robot)
      for _, r in ipairs(e.robots[1] and e.robots or {e.robots}) do
        if inv.insert{name = r.item, count = r.count} ~= r.count then
          error("could not insert " .. r.count .. " " .. r.item)
        end
      end
    end
    if e.requests then
      -- A requester chest's own (static) requests, in its first logistic section.
      local lp = ent.get_logistic_point(defines.logistic_member_index.logistic_container)
      local sec = lp.get_section(1) or lp.add_section()
      for i, r in ipairs(e.requests) do
        sec.set_slot(i, {value = {type = "item", name = r.item, quality = "normal"}, min = r.count})
      end
    end
    if e.power then
      -- A limited supply: an electric-energy-interface producing `watts`, with a
      -- buffer of one tick's output, so it can never deliver more than that a tick.
      local per_tick = e.power.watts / 60
      ent.power_usage = 0
      ent.power_production = per_tick
      ent.electric_buffer_size = per_tick
      ent.energy = 0
    end
    if e.fluid then
      -- Fluid put into the entity's first fluidbox at build (e.g. {name = "water", amount = 100}).
      ent.insert_fluid{name = e.fluid.name, amount = e.fluid.amount}
    end
    if e.fuel then
      ent.get_fuel_inventory().insert{name = e.fuel.item, count = e.fuel.count}
    end
    if e.infinity_item then
      ent.set_infinity_container_filter(1, {name = e.infinity_item, count = 100, mode = "exactly"})
    end
    if e.sink then
      storage.sinks[#storage.sinks + 1] = {id = e.sink, entity = ent, by_item = e.sink_by_item, keep = e.sink_keep}
    end
    if e.belt_sink then
      -- A counting tile: every tick its two lanes are counted and emptied.
      storage.belt_sinks[#storage.belt_sinks + 1] = {id = e.belt_sink, entity = ent, acc = {left = 0, right = 0},
                                                     by_item = e.belt_sink_by_item and {} or nil}
    end
  end
  for _, w in ipairs(exp.wires or {}) do
    local a, b = by_tag[w[1]], by_tag[w[2]]
    if not (a and b) then error("wire names a missing tag: " .. w[1] .. " -> " .. w[2]) end
    -- Optional 4th/5th: "input" or "output" for a combinator's side.
    -- Colour "copper": a pole's copper, or a power switch's side ("left"/"right" as 4th/5th).
    local function cid(side)
      if w[3] == "copper" then
        return defines.wire_connector_id[side and ("power_switch_" .. side .. "_copper") or "pole_copper"]
      end
      return defines.wire_connector_id[(side and ("combinator_" .. side .. "_") or "circuit_") .. w[3]]
    end
    if not a.get_wire_connector(cid(w[4]), true).connect_to(b.get_wire_connector(cid(w[5]), true), false) then
      error("could not wire " .. w[1] .. " -> " .. w[2])
    end
  end
  -- A layout is checked in the game, not by our geometry: every effect
  -- receiver must see exactly the beacons it was designed for.
  if storage.expect then
    local lines = {"tag,beacons_count,crafting_speed\n"}
    for _, x in ipairs(storage.expect) do
      if x.entity.beacons_count ~= x.n then
        error(x.tag .. " sees " .. x.entity.beacons_count .. " beacons, designed for " .. x.n)
      end
      lines[#lines + 1] = string.format("%s,%d,%.6f\n", x.tag, x.entity.beacons_count, x.entity.crafting_speed)
    end
    helpers.write_file("lab/" .. exp.name .. "-check.csv", table.concat(lines), false)
  end
  if exp.posdump then
    -- Item positions (in 1/256 tile) on tagged belts' lanes at chosen ticks.
    storage.posdump = {}
    for _, tag in ipairs(exp.posdump.tags) do
      if not by_tag[tag] then error("posdump names a missing tag: " .. tag) end
      storage.posdump[#storage.posdump + 1] = {tag = tag, entity = by_tag[tag]}
    end
    helpers.write_file("lab/" .. exp.name .. "-pos.csv", "tick,tag,lane,positions\n", false)
  end
  storage.by_tag = by_tag
  if exp.export_blueprint then
    -- The built area as a blueprint string (entities, wires, settings), for a copy.
    local inv = game.create_inventory(1)
    local st = inv[1]
    st.set_stack{name = "blueprint"}
    st.create_blueprint{surface = surface, force = force, area = exp.export_blueprint.area}
    helpers.write_file("lab/" .. exp.name .. "-bp.txt", st.export_stack(), false)
    inv.destroy()
  end
  if exp.probe then
    -- A signal read each window from a tagged entity's network (red).
    storage.probe = {entity = by_tag[exp.probe.tag], signals = exp.probe.signals or {exp.probe.signal},
                     connector = exp.probe.connector}
    if not storage.probe.entity then error("probe names a missing tag: " .. exp.probe.tag) end
  end
  -- Several probes (probes: a list, each with an id), written as probe:<id>:<signal>.
  storage.probes = {}
  for _, p in ipairs(exp.probes or {}) do
    if p.at then
      -- By position ({name, x, y}), found each window: an entity built later (by robots) has no tag.
      storage.probes[#storage.probes + 1] = {id = p.id, at = p.at, signals = p.signals, connector = p.connector}
    else
      if not by_tag[p.tag] then error("probe names a missing tag: " .. p.tag) end
      storage.probes[#storage.probes + 1] = {id = p.id, entity = by_tag[p.tag], signals = p.signals, connector = p.connector}
    end
  end
  if exp.pulses then
    -- A belt's enable condition switched by schedule (copper-plate < c, no
    -- signal): enabled when c = 1, disabled when c = 0. Disabled from setup.
    local g = by_tag[exp.pulses.tag]
    if not g then error("pulses name a missing tag: " .. exp.pulses.tag) end
    storage.pulse = {entity = g, on = nil}
  end
  storage.start = game.tick
  if exp.growth then
    storage.growth = {next = 1, pending = {}, laid = 0, built = 0, log = {}}
    for _ = 1, exp.growth.initial do
      lay_seed(storage.growth.next)
      storage.growth.next = storage.growth.next + 1
    end
  end
  -- Filming (tools/colony-viz/film.md): screenshots and render objects are not
  -- state the machines read, so the run is unchanged by them.
  if exp.screenshots and exp.screenshots.speed then game.speed = exp.screenshots.speed end
  if exp.ups then
    -- A UPS run measures the game, not this script: stop ticking after setup.
    script.on_event(defines.events.on_tick, nil)
    return
  end
  helpers.write_file(out_path(), "tick,sink,count\n", false)
end

-- Observe mode (untimed): every `every` ticks up to `last`, count every
-- inserter by status and sum the items on each group. Output:
-- script-output/lab/<name>-observe.csv, columns tick,kind,key,value.
local status_name = {}
for k, v in pairs(defines.entity_status) do status_name[v] = k end

local function observe(t)
  local o = exp.observe
  if t % o.every ~= 0 or t > o["last"] then return end
  local path = "lab/" .. exp.name .. "-observe.csv"
  if t == 0 then helpers.write_file(path, "tick,kind,key,value\n", false) end
  local lines, by = {}, {}
  local nets, wired, lo_sig, hi_sig = {}, 0, math.huge, -math.huge
  for _, e in pairs(game.surfaces[1].find_entities_filtered{area = exp.area, type = "inserter"}) do
    local k = status_name[e.status] or tostring(e.status)
    by[k] = (by[k] or 0) + 1
    -- The red network each inserter sits on, and the iron-plate signal it sees.
    local net = e.get_circuit_network(defines.wire_connector_id.circuit_red)
    if net then
      wired = wired + 1
      nets[net.network_id] = true
      local v = net.get_signal({type = "item", name = "iron-plate"})
      lo_sig, hi_sig = math.min(lo_sig, v), math.max(hi_sig, v)
    end
  end
  for k, n in pairs(by) do lines[#lines + 1] = string.format("%d,inserter_status,%s,%d\n", t, k, n) end
  -- Belts by status: a circuit-stopped belt reads disabled_by_control_behavior.
  local belts = {}
  for _, e in pairs(game.surfaces[1].find_entities_filtered{area = exp.area, type = "transport-belt"}) do
    local k = status_name[e.status] or tostring(e.status)
    belts[k] = (belts[k] or 0) + 1
  end
  for k, n in pairs(belts) do lines[#lines + 1] = string.format("%d,belt_status,%s,%d\n", t, k, n) end
  if o.marker then
    -- Which tiles of one group hold the marker item: a moving loop moves it.
    local at = {}
    for _, e in ipairs((storage.groups or {})[o.marker.group] or {}) do
      local n = 0
      for i = 1, e.get_max_transport_line_index() do n = n + e.get_transport_line(i).get_item_count({name = o.marker.item}) end
      if n > 0 then at[#at + 1] = string.format("%g_%g", e.position.x, e.position.y) end
    end
    table.sort(at)
    lines[#lines + 1] = string.format("%d,marker,%s,%d\n", t, table.concat(at, "/"), #at)
  end
  local n_nets = 0
  for _ in pairs(nets) do n_nets = n_nets + 1 end
  lines[#lines + 1] = string.format("%d,inserter_red,wired,%d\n%d,inserter_red,networks,%d\n", t, wired, t, n_nets)
  if wired > 0 then
    lines[#lines + 1] = string.format("%d,inserter_red,plate_min,%d\n%d,inserter_red,plate_max,%d\n", t, lo_sig, t, hi_sig)
  end
  local lo, hi, total, groups = math.huge, 0, 0, 0
  for _, ents in pairs(storage.groups or {}) do
    local n = 0
    for _, e in ipairs(ents) do
      for i = 1, e.get_max_transport_line_index() do n = n + e.get_transport_line(i).get_item_count() end
    end
    lo, hi, total, groups = math.min(lo, n), math.max(hi, n), total + n, groups + 1
  end
  if groups > 0 then
    lines[#lines + 1] = string.format("%d,group_items,min,%d\n%d,group_items,max,%d\n%d,group_items,total,%d\n%d,group_items,groups,%d\n",
      t, lo, t, hi, t, total, t, groups)
  end
  if o.census and (t == 0 or t == o["last"]) then
    -- The whole surface, not just the built area: what else ticks here.
    local surface = game.surfaces[1]
    local chunks = 0
    for _ in surface.get_chunks() do chunks = chunks + 1 end
    lines[#lines + 1] = string.format("%d,census,seed,%d\n%d,census,chunks,%d\n", t, surface.map_gen_settings.seed, t, chunks)
    local types = {}
    for _, e in pairs(surface.find_entities_filtered{}) do
      local k = e.force.name .. ":" .. e.type
      types[k] = (types[k] or 0) + 1
    end
    for k, n in pairs(types) do lines[#lines + 1] = string.format("%d,census,%s,%d\n", t, k, n) end
  end
  helpers.write_file(path, table.concat(lines), true)
end

script.on_event(defines.events.on_tick, function(event)
  if not storage.start then
    setup()
    if exp.observe then observe(0) end
    return
  end
  local t = event.tick - storage.start
  if exp.observe then
    observe(t)
    return
  end
  local shots = exp.screenshots
  if shots and t % shots.every == 0 and t <= shots.last then
    game.take_screenshot{surface = game.surfaces[1], position = shots.position, resolution = shots.resolution,
      zoom = shots.zoom, daytime = 0, hide_clouds = true, hide_fog = true, force_render = true,
      path = string.format("lab/shots/%s/%08d.png", exp.name, t)}
  end
  if storage.posdump then
    for _, pt in ipairs(exp.posdump.ticks) do
      if pt == t then
        local lines = {}
        for _, d in ipairs(storage.posdump) do
          for lane = 1, 2 do
            local ps = {}
            for _, it in ipairs(d.entity.get_transport_line(lane).get_detailed_contents()) do
              ps[#ps + 1] = string.format("%d", math.floor(it.position * 256 + 0.5))
            end
            lines[#lines + 1] = string.format("%d,%s,%d,%s\n", t, d.tag, lane, table.concat(ps, ";"))
          end
          lines[#lines + 1] = string.format("%d,%s,status,%s\n", t, d.tag, status_name[d.entity.status] or tostring(d.entity.status))
        end
        helpers.write_file("lab/" .. exp.name .. "-pos.csv", table.concat(lines), true)
      end
    end
  end
  for _, ev in ipairs(exp.events or {}) do
    -- Injected faults: destroy a tagged entity, or lay an item on a tagged belt's lane.
    if ev.tick == t then
      local ent = ev.tag and storage.by_tag[ev.tag]
      if ev.tag and not (ent and ent.valid) then error("event names a missing tag: " .. ev.tag) end
      if ev.action == "destroy" then
        ent.destroy()
      elseif ev.action == "die" then
        -- Killed, not destroyed: it leaves a corpse and, with the research, a ghost.
        storage.died = storage.died or {}
        storage.died[ev.tag] = {name = ent.name, position = ent.position}
        ent.die()
      elseif ev.action == "die_area" then
        -- Every building in an area killed (robots, ghosts and the character spared):
        -- a machine without tags, e.g. one built by robots, removed whole.
        local skip = {["construction-robot"] = true, ["logistic-robot"] = true, ["entity-ghost"] = true,
                      character = true, corpse = true, ["item-entity"] = true}
        for _, x in ipairs(game.surfaces[1].find_entities_filtered{area = ev.area, force = "player"}) do
          if x.valid and not skip[x.type] then x.die() end
        end
      elseif ev.action == "on" or ev.action == "off" then
        -- A constant combinator switched on or off at a tick.
        ent.get_or_create_control_behavior().enabled = ev.action == "on"
      elseif ev.action == "fill_at" then
        -- Items inserted into a container found by position (bp: in the blueprint's coordinates).
        local off = storage.bp_off or {x = 0, y = 0}
        local pos = ev.bp and {ev.x + off.x, ev.y + off.y} or {ev.x, ev.y}
        local c = game.surfaces[1].find_entity(ev.name, pos)
        if not c then error("fill_at: no " .. ev.name .. " at " .. serpent.line(pos)) end
        c.get_inventory(defines.inventory.chest).insert{name = ev.item, count = ev.count}
      elseif ev.action == "inject" then
        if not ent.get_transport_line(ev.line).insert_at(0, {name = ev.item, count = 1}) then
          error("could not inject " .. ev.item .. " on " .. ev.tag)
        end
      else
        error("unknown event " .. tostring(ev.action))
      end
    end
  end
  if storage.pulse then
    local p = exp.pulses
    local k = t - p.start
    local on = k >= 0 and k < p.count * p.period and k % p.period < p.length
    if on ~= storage.pulse.on then
      local cb = storage.pulse.entity.get_or_create_control_behavior()
      if storage.pulse.entity.type == "constant-combinator" then
        -- A constant combinator is switched on and off.
        cb.enabled = on
      else
        cb.circuit_enable_disable = true
        cb.circuit_condition = {first_signal = {type = "item", name = "copper-plate"}, comparator = "<", constant = on and 1 or 0}
      end
      storage.pulse.on = on
    end
  end
  for _, b in ipairs(storage.belt_sinks) do
    for side, index in pairs{left = defines.transport_line.left_line, right = defines.transport_line.right_line} do
      local line = b.entity.get_transport_line(index)
      local c = line.get_item_count()
      if c > 0 then
        if b.by_item and t > exp.warmup then
          -- Per item (both lanes together), for a tile that receives more than one kind.
          for _, it in ipairs(line.get_contents()) do
            b.by_item[it.name] = (b.by_item[it.name] or 0) + it.count
          end
        end
        line.clear()
        if t > exp.warmup then b.acc[side] = b.acc[side] + c end
      end
    end
  end
  if storage.growth and t % 60 == 0 then
    local gr, g = storage.growth, exp.growth
    local done = {}
    for i, _ in pairs(gr.pending) do
      if #game.surfaces[1].find_entities_filtered{area = g.slots[i].area, type = "entity-ghost"} == 0 then
        done[#done + 1] = i
      end
    end
    table.sort(done)
    for _, i in ipairs(done) do
      gr.pending[i] = nil
      gr.built = gr.built + 1
      gr.log[#gr.log + 1] = string.format("%d,growth:done:%d,%d\n", t, i, t)
      for _ = 1, ((g.request or g.deploy) and 0 or g.per_done) do
        if gr.next <= #g.slots then
          lay_seed(gr.next)
          gr.log[#gr.log + 1] = string.format("%d,growth:laid:%d,%d\n", t, gr.next, t)
          gr.next = gr.next + 1
        end
      end
    end
    if g.deploy then
      -- Each machine its own deployer (deploy = {name, offset, connector, request, dir, step,
      -- founder}): a built machine with no seed open, whose deployer entity (at its anchor +
      -- offset) reads request > 0, asks for the site one step from its anchor in the direction
      -- (dir mod 4: east, south, west, north); the harness lays it there only if that is a
      -- prepared site (a slot) with nothing of the player's force in its area. It decides
      -- nothing else: a refused machine asks again as its own direction turns.
      local dp = g.deploy
      -- A founder built by the harness (dp.founder, lineage 1), or founders laid as seeds at
      -- the start (dp.initial = {{slot, bp}}): each built seed is a machine of the lineage
      -- whose blueprint it was laid from, and lays its own seeds from that blueprint.
      if not gr.machines then
        gr.machines, gr.bp_of = {}, {}
        if dp.founder then gr.machines[1] = {anchor = dp.founder, bp = 1} end
      end
      gr.used = gr.used or {}
      gr.refused = gr.refused or 0
      if dp.initial and not gr.initial_laid then
        gr.initial_laid = true
        for _, f in ipairs(dp.initial) do
          lay_seed(f[1], f[2])
          gr.used[f[1]] = true
          gr.bp_of[f[1]] = f[2]
          gr.log[#gr.log + 1] = string.format("%d,growth:laid:%d,%d\n%d,growth:type:%d,%d\n", t, f[1], t, t, f[1], f[2])
        end
      end
      if not gr.site_at then
        gr.site_at = {}
        for i, sl in ipairs(g.slots) do gr.site_at[sl.anchor[1] .. "," .. sl.anchor[2]] = i end
      end
      for _, i in ipairs(done) do
        for m, mc in ipairs(gr.machines) do
          if mc.pending == i then mc.pending = nil end
        end
        gr.machines[#gr.machines + 1] = {anchor = g.slots[i].anchor, bp = gr.bp_of[i]}
        local sh = exp.screenshots
        if sh and sh.overlay then
          local sl, c = g.slots[i], sh.lineage_colors[gr.bp_of[i] or 1]
          rendering.draw_rectangle{surface = game.surfaces[1], filled = true, draw_on_ground = true,
            color = {c[1], c[2], c[3], 0.45}, left_top = {sl.area[1][1], sl.area[1][2]},
            right_bottom = {sl.area[2][1], sl.area[2][2]}}
        end
      end
      local dirs = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
      local skip = {["construction-robot"] = true, ["logistic-robot"] = true}
      for m, mc in ipairs(gr.machines) do
        if not mc.pending then
          local ent = game.surfaces[1].find_entity(dp.name, {mc.anchor[1] + dp.offset[1], mc.anchor[2] + dp.offset[2]})
          local net = ent and ent.get_circuit_network(defines.wire_connector_id[dp.connector])
          local want = net and net.get_signal({type = "virtual", name = dp.request}) or 0
          if want > 0 then
            mc.ask = mc.ask or t
            local d = dirs[(net.get_signal({type = "virtual", name = dp.dir}) % 4) + 1]
            local key = (mc.anchor[1] + d[1] * dp.step) .. "," .. (mc.anchor[2] + d[2] * dp.step)
            local i = gr.site_at[key]
            local free = i and not gr.used[i]
            if free then
              for _, x in ipairs(game.surfaces[1].find_entities_filtered{area = g.slots[i].area, force = "player"}) do
                if not skip[x.type] then free = false break end
              end
            end
            if free then
              -- The child's lineage: the asker's own, or (dp.lineage) the signal it puts on
              -- its deployer's network (a machine that draws its child's blueprint itself).
              local kid = mc.bp
              if dp.lineage then
                local b = net.get_signal({type = "virtual", name = dp.lineage})
                if g.strings[b] then kid = b end
              end
              lay_seed(i, g.strings and kid or nil)
              gr.used[i] = true
              gr.bp_of[i] = kid
              mc.pending = i
              if g.strings then
                gr.log[#gr.log + 1] = string.format("%d,growth:type:%d,%d\n", t, i, kid)
              end
              gr.log[#gr.log + 1] = string.format("%d,growth:laid:%d,%d\n%d,growth:asked:%d,%d\n%d,growth:by:%d,%d\n",
                                                  t, i, t, t, i, mc.ask, t, i, m - 1)
              mc.ask = nil
            else
              gr.refused = gr.refused + 1
            end
          else
            mc.ask = nil
          end
        end
      end
    end
    if g.request then
      -- Laid on request only (request = {tag, connector, signal}): while fewer seeds
      -- are open than the signal on the tagged entity's network, lay the next. The
      -- harness decides nothing: the machines say how many gifts stand ready.
      local ent = storage.by_tag[g.request.tag]
      local net = ent and ent.valid and ent.get_circuit_network(defines.wire_connector_id[g.request.connector])
      local want = net and net.get_signal({type = "virtual", name = g.request.signal}) or 0
      gr.request = want
      local open = 0
      for _ in pairs(gr.pending) do open = open + 1 end
      while open < want and gr.next <= #g.slots do
        lay_seed(gr.next)
        gr.log[#gr.log + 1] = string.format("%d,growth:laid:%d,%d\n", t, gr.next, t)
        gr.next = gr.next + 1
        open = open + 1
      end
    end
  end
  if t == exp.warmup then
    for _, s in ipairs(storage.sinks) do s.entity.get_inventory(defines.inventory.chest).clear() end
  elseif t > exp.warmup and (t - exp.warmup) % exp.window == 0 then
    local lines = {}
    -- Probe and tally first, before any sink is emptied below.
    if storage.probe then
      local net = storage.probe.entity.get_circuit_network(defines.wire_connector_id[storage.probe.connector or "circuit_red"])
      for _, n in ipairs(storage.probe.signals) do
        -- A name "fluid:<name>" is a fluid signal; "signal-..." virtual; else an item.
        local sig = (n:sub(1, 6) == "fluid:") and {type = "fluid", name = n:sub(7)}
                    or {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n}
        local v = (not ent or not ent.valid) and -2 or net and net.get_signal(sig) or -1
        lines[#lines + 1] = string.format("%d,probe:%s,%d\n", t, n, v)
      end
    end
    if exp.priority_read then
      -- A splitter's current output priority, as a name in the sink column (count 1).
      lines[#lines + 1] = string.format("%d,prio:%s,1\n", t, storage.by_tag[exp.priority_read].splitter_output_priority)
    end
    if exp.input_priority_read then
      -- A splitter's current input priority, as a name in the sink column (count 1).
      lines[#lines + 1] = string.format("%d,iprio:%s,1\n", t, storage.by_tag[exp.input_priority_read].splitter_input_priority)
    end
    if exp.filter_read then
      -- A splitter's current filter (its name in the sink column, count 1; none: "none"),
      -- and whether its control behavior has set_filter on.
      local sp = storage.by_tag[exp.filter_read]
      local f = sp.splitter_filter
      local cb = sp.get_control_behavior()
      lines[#lines + 1] = string.format("%d,filter:%s,%d\n", t, f and (f.name and (type(f.name) == "string" and f.name or f.name.name)) or "none",
        (cb and cb.set_filter) and 1 or 0)
    end
    if exp.progress then
      -- A crafting machine's progress on its current craft (x 1000) and its crafted count.
      for _, tag in ipairs(exp.progress) do
        local m = storage.by_tag[tag]
        if not (m and m.valid) then
          -- Killed (event "die"): found again at its place once rebuilt.
          local d = (storage.died or {})[tag]
          m = d and game.surfaces[1].find_entity(d.name, d.position)
          if m then storage.by_tag[tag] = m end
        end
        if not m then
          lines[#lines + 1] = string.format("%d,absent:%s,1\n", t, tag)
          goto continue_progress
        end
        lines[#lines + 1] = string.format("%d,progress:%s,%d\n%d,crafted:%s,%d\n", t, tag,
          math.floor(m.crafting_progress * 1000 + 0.5), t, tag, m.products_finished)
        local r = m.get_recipe()
        -- The current recipe's name in the sink column, count 1 (none: "none").
        lines[#lines + 1] = string.format("%d,recipe:%s:%s,1\n", t, tag, r and r.name or "none")
        ::continue_progress::
      end
    end
    for _, p in ipairs(storage.probes or {}) do
      local ent = p.entity
      if p.at then ent = game.surfaces[1].find_entity(p.at.name, {p.at.x, p.at.y}) end
      local net = ent and ent.valid and ent.get_circuit_network(defines.wire_connector_id[p.connector or "circuit_red"])
      for _, n in ipairs(p.signals) do
        -- A name "fluid:<name>" is a fluid signal; "signal-..." virtual; else an item.
        local sig = (n:sub(1, 6) == "fluid:") and {type = "fluid", name = n:sub(7)}
                    or {type = (n:sub(1, 7) == "signal-") and "virtual" or "item", name = n}
        local v = (not ent or not ent.valid) and -2 or net and net.get_signal(sig) or -1
        lines[#lines + 1] = string.format("%d,probe:%s:%s,%d\n", t, p.id, n, v)
      end
    end
    for _, fp in ipairs(exp.fluidprobes or {}) do
      -- A tagged entity's fluid segment contents, by script (the truth a read is
      -- compared with), in thousandths of a unit: <id>:<fluid name>.
      local ent = storage.by_tag[fp.tag]
      local f = ent and ent.valid and ent.get_fluid_segment_fluid(1)
      lines[#lines + 1] = string.format("%d,fluid:%s:%s,%d\n", t, fp.id, f and f.name or "none",
                                        f and math.floor(f.amount * 1000 + 0.5) or 0)
    end
    if exp.watch then
      -- Entities found by position each window (built later, e.g. by robots):
      -- a container's items, a crafting machine's crafted count; absent if not there.
      local off = storage.bp_off or {x = 0, y = 0}
      for _, wt in ipairs(exp.watch) do
        local pos = wt.bp and {wt.x + off.x, wt.y + off.y} or {wt.x, wt.y}
        local ent = game.surfaces[1].find_entity(wt.name, pos)
        if not ent then
          lines[#lines + 1] = string.format("%d,watch:%s:absent,1\n", t, wt.id)
        elseif ent.type == "assembling-machine" then
          lines[#lines + 1] = string.format("%d,watch:%s:crafted,%d\n", t, wt.id, ent.products_finished)
        elseif ent.type == "inserter" then
          -- An inserter's hand: the item it holds (none: only "present").
          local h = ent.held_stack
          if h.valid_for_read then
            lines[#lines + 1] = string.format("%d,watch:%s:%s,%d\n", t, wt.id, h.name, h.count)
          end
          lines[#lines + 1] = string.format("%d,watch:%s:present,1\n", t, wt.id)
        else
          -- An entity with no chest inventory (a vehicle) reads as present only.
          local inv = ent.get_inventory(defines.inventory.chest)
          for _, it in ipairs(inv and inv.get_contents() or {}) do
            lines[#lines + 1] = string.format("%d,watch:%s:%s,%d\n", t, wt.id, it.name, it.count)
          end
          lines[#lines + 1] = string.format("%d,watch:%s:present,1\n", t, wt.id)
        end
      end
    end
    if storage.bp_off and not storage.bp_off_written then
      -- Where the blueprint landed: its offset from its own coordinates (first window only).
      lines[#lines + 1] = string.format("%d,bp_off_x,%d\n%d,bp_off_y,%d\n", t, storage.bp_off.x, t, storage.bp_off.y)
      storage.bp_off_written = true
    end
    if storage.growth then
      -- Seeds built and laid so far, and each seed's event in the window.
      for _, l in ipairs(storage.growth.log) do lines[#lines + 1] = l end
      storage.growth.log = {}
      lines[#lines + 1] = string.format("%d,growth:built,%d\n%d,growth:laid,%d\n", t, storage.growth.built, t,
                                        storage.growth.laid)
      if exp.growth.deploy then
        lines[#lines + 1] = string.format("%d,growth:refused,%d\n", t, storage.growth.refused or 0)
      end
      if exp.growth.request then
        lines[#lines + 1] = string.format("%d,growth:request,%d\n", t, storage.growth.request or 0)
      end
    end
    if exp.count_ghosts then
      lines[#lines + 1] = string.format("%d,ghosts,%d\n", t, #game.surfaces[1].find_entities_filtered{area = exp.area, type = "entity-ghost"})
      -- Ghosts by named area, when given (ghost_areas: {name = area}).
      for name, ar in pairs(exp.ghost_areas or {}) do
        local gs = game.surfaces[1].find_entities_filtered{area = ar, type = "entity-ghost"}
        lines[#lines + 1] = string.format("%d,ghosts:%s,%d\n", t, name, #gs)
        if exp.ghost_names then
          -- Which entities the ghosts stand for, when asked.
          local by = {}
          for _, g in ipairs(gs) do by[g.ghost_name] = (by[g.ghost_name] or 0) + 1 end
          for n, c in pairs(by) do lines[#lines + 1] = string.format("%d,ghosts:%s:%s,%d\n", t, name, n, c) end
        end
      end
    end
    if exp.tally then
      -- Items on the belts of a group (e.g. a dead-end buffer), at each window's end.
      for _, g in ipairs(exp.tally) do
        local n = 0
        for _, b in ipairs((storage.groups or {})[g] or {}) do
          for i = 1, b.get_max_transport_line_index() do n = n + b.get_transport_line(i).get_item_count() end
        end
        lines[#lines + 1] = string.format("%d,tally:%s,%d\n", t, g, n)
      end
    end

    for _, s in ipairs(storage.sinks) do
      local inv = s.entity.get_inventory(defines.inventory.chest)
      lines[#lines + 1] = string.format("%d,%s,%d\n", t, s.id, inv.get_item_count())
      if s.by_item then
        -- Per item, for a chest that receives more than one kind.
        for _, it in ipairs(inv.get_contents()) do
          lines[#lines + 1] = string.format("%d,%s:%s,%d\n", t, s.id, it.name, it.count)
        end
      end
      -- A kept sink is read, not emptied: its count is the chest's content.
      if not s.keep then inv.clear() end
    end
    for _, b in ipairs(storage.belt_sinks) do
      for _, side in ipairs{"left", "right"} do
        lines[#lines + 1] = string.format("%d,%s:%s,%d\n", t, b.id, side, b.acc[side])
        b.acc[side] = 0
      end
      if b.by_item then
        for name, n in pairs(b.by_item) do
          if n > 0 then lines[#lines + 1] = string.format("%d,%s:item:%s,%d\n", t, b.id, name, n) end
          b.by_item[name] = 0
        end
      end
    end
    helpers.write_file(out_path(), table.concat(lines), true)
  end
end)
