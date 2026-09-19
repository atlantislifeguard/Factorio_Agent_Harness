

local movement=require('scripts.actions.movement')
local mining= require('scripts.actions.mining')
local pathing = require('scripts.utils.pathing')
local geom    = require('scripts.utils.geom')
local crafting= require('scripts.actions.crafting')
local placement= require('scripts.actions.placement')


local DEFAULT_TIMEOUT = 60 * 60 -- in ticks, ( 60 ticks a second)
local MAX_RESULTS = 200          -- oldest untaken results are dropped past this

local function player()
  return game.get_player(1)
end

-- The agent drives its own character
local function character()
  local c = storage.agent_char
  if c and c.valid then return c end
  return nil
end



-- map inventory to flat name:count table
local function inventory_map(inv)
  local out = {}
  if not inv then return out end
  for _, stack in pairs(inv.get_contents()) do
    out[stack.name] = (out[stack.name] or 0) + stack.count
  end
  return out
end

local function new_id()
  storage.next_id = (storage.next_id or 0) + 1
  return storage.next_id
end

local function push_result(id, ok, data)
  storage.results = storage.results or {}
  table.insert(storage.results, { id = id, ok = ok, data = data or {}, tick = game.tick })
  while #storage.results > MAX_RESULTS do table.remove(storage.results, 1) end
end

-- Hand back one result by id, leaving every other result for whoever waits on it.
local function take_result(params)
  local id = params.id
  local results = storage.results or {}
  for i, r in ipairs(results) do
    if r.id == id then
      table.remove(results, i)
      return { ok = true, ready = true, result = r }
    end
  end

  local ct = storage.current_task
  local pending = (ct and ct.id == id) or crafting.is_pending(id)
  if not pending then
    for _, t in ipairs(storage.queue or {}) do
      if t.id == id then pending = true break end
    end
  end
  if pending then return { ok = true, ready = false } end
  return { ok = false, reason = "unknown_id", hint = "already taken, or dropped as too old" }
end

local function stop_body()
  local c = character()
  if c then
    c.walking_state = { walking = false }
    c.mining_state = { mining = false }
  end
end

local function finish_task(ok, data)
  local t = storage.current_task
  if t then push_result(t.id, ok, data) end
  storage.current_task = nil
  stop_body()
end

local function enqueue(task)
  task.id = new_id()
  task.created_tick = game.tick
  task.timeout = task.timeout or DEFAULT_TIMEOUT
  storage.queue = storage.queue or {}
  table.insert(storage.queue, task)
  return { ok = true, id = task.id, queued = #storage.queue }
end



-- task executors does work per tick


local executors = {}

executors.walk_to = movement.walk_to
executors.mine_at = mining.mine_at







-- observation functions

local function get_state()
  local char = character()
  local ct = storage.current_task
  return {
    ok = true,
    tick = game.tick,
    busy = (ct ~= nil) or (storage.queue and #storage.queue > 0) or false,
    current_task = ct and { id = ct.id, type = ct.type } or nil,
    queue_length = storage.queue and #storage.queue or 0,
    alive = char ~= nil,
    position = char and { x = char.position.x, y = char.position.y } or nil,
    health = char and char.health or nil,
    inventory = inventory_map(char and char.get_main_inventory()),
    crafting_queue_size = char and char.crafting_queue_size or 0,
    crafts = crafting.summary(),
  }
end

-- Create the agent's character at the spawn point.
local function spawn_agent(params)
  params = params or {}
  local existing = character()
  if existing then
    return { ok = false, reason = "agent_exists",
             position = { x = existing.position.x, y = existing.position.y } }
  end

  local p = player()
  local surface = (p and p.surface) or game.surfaces["nauvis"]
  local near
  if params.x and params.y then
    near = { x = params.x, y = params.y }
  elseif p then
    near = p.position
  else
    near = game.forces.player.get_spawn_position(surface)
  end

  local pos = surface.find_non_colliding_position("character", near, 10, 0.5)
  if not pos then return { ok = false, reason = "no_space" } end

  local c = surface.create_entity{ name = "character", position = pos, force = game.forces.player }
  if not c then return { ok = false, reason = "create_failed" } end
  storage.agent_char = c

  -- label so the agent is easy to tell apart from the player's own character
  rendering.draw_text{ text = "agent", surface = surface, target = { entity = c, offset = { 0, -2.5 } },
                       color = { 1, 0.6, 0 }, scale = 1.5, alignment = "center" }

  return { ok = true, position = { x = c.position.x, y = c.position.y } }
end

local function find_nearest(params)          -- {name=, radius=} or {type="resource"}
  local char = character()
  if not char then return { ok = false, reason = "no_character" } end
  if not (params.name or params.type) then return { ok = false, reason = "needs_name_or_resource" } end


  local found = char.surface.find_entities_filtered{
    name = params.name,
    type = params.type,
    position = char.position,
    radius = params.radius or 200,
  }

  local best = char.surface.get_closest(char.position, found)
  if not best then return { ok = false, reason = "not_found" } end

  return {
    ok = true,
    name = best.name,
    position = { x = best.position.x, y = best.position.y },
    distance = math.sqrt(geom.dist2(char.position, best.position)),
    amount = best.type == "resource" and best.amount or nil,
  }
end


-- remote interface (the ONLY interface the agent interacts with)

remote.add_interface("agent", {
  
  -- setup
  spawn_agent = spawn_agent,                  -- {x=?, y=?}

  -- observation
  get_state = get_state,
  find_nearest = find_nearest,
  take_result = take_result,                  -- {id=}
  drain_results = function()                  -- debugging: takes every result at once
    local r = storage.results or {}
    storage.results = {}
    return r
  end,

  -- queued events (multi-tick)


  walk_to = function(params)                  -- {x=, y=, stop_within=?, timeout=?}
    return enqueue{ type = "walk_to",
                    target = { x = params.x, y = params.y },
                    stop_within = params.stop_within ,
                    timeout = params.timeout }
  end,
  mine_at = function(params)                  -- {x=, y=, item=?, count=?, timeout=?}
    return enqueue{ type = "mine_at",
                    position = { x = params.x, y = params.y },
                    item = params.item, count = params.count,
                    timeout = params.timeout }
  end,

-- instant (single-tick) actions

  place_entity = function(params)                     -- {name=, position={x,y}, direction=?}
    local c= character()
    if not c then return { ok = false, reason = "no_character" } end
    return placement.do_place(c, params)
  end,




  -- runs alongside the body queue; returns an id whose result arrives on completion
  hand_craft = function(params)  -- {recipe=, count=?, timeout=?}
    local c= character()
    if not c then return { ok = false, reason = "no_character" } end
    return crafting.do_craft(c, params, new_id)
  end,

  list_craftable= function ()

    local c= character()
    if not c then return { ok = false, reason = "no_character" } end
    return crafting.list_craftable(c)

  end,

  can_hand_craft= function (params)   -- {recipe=, count=?}
    local c= character()
    if not c then return { ok = false, reason = "no_character" } end
    return crafting.can_hand_craft(c, params)
  end,

  cancel_all = function()
    storage.queue = {}
    finish_task(false, { reason = "cancelled" })
    crafting.cancel_all(character(), push_result)
    return { ok = true }
  end,
})



-- main tick handler

-- body lane: one task at a time from storage.queue
local function tick_body()
  local task = storage.current_task
  if not task then
    if storage.queue and #storage.queue > 0 then
      task = table.remove(storage.queue, 1)
      storage.current_task = task
    else
      return
    end
  end

  if not task.started_tick then
    task.started_tick= game.tick
  end

  if game.tick - task.started_tick > task.timeout then
    return finish_task(false, { reason = "timeout" })
  end

  local exec = executors[task.type]
  if not exec then
    return finish_task(false, { reason = "unknown_task_type", type = task.type })
  end

  local char = character()
  if not char then return finish_task(false, { reason = "no_character" }) end

  exec(task, char, finish_task)

end

script.on_event(defines.events.on_tick, function()
  crafting.tick(character(), push_result)          -- hands lane, independent of the body
  tick_body()
end)

script.on_event(defines.events.on_script_path_request_finished, pathing.on_path_finished)



-- lifecycle events

script.on_init(function()
  storage.queue = {}
  storage.results = {}
  storage.crafts = {}
  storage.next_id = 0
end)

script.on_event(defines.events.on_entity_died, function(event)
  if event.entity ~= storage.agent_char then return end
  print("[AGENT_EVT] died at time=" .. game.tick)
  storage.queue = {}
  finish_task(false, { reason = "died" })
  crafting.fail_all(push_result, "died")
  storage.agent_char = nil                         -- agent must spawn_agent again
end, {{ filter = "type", type = "character" }})

script.on_event(defines.events.on_player_respawned, function(event)
  local p = game.get_player(event.player_index)
  print("[AGENT_EVT] respawned at time=" .. game.tick ..
        " pos=" .. serpent.line(p.position))
end)

script.on_event(defines.events.on_research_finished, function(event)
  print("[AGENT_EVT] research_finished: " .. event.research.name.. " at time="..game.tick  )
end)


