-- movement.lua
local pathing = require("scripts.utils.pathing")
local geom= require("scripts.utils.geom")
local movement = {}

local ARRIVE = 0.35          -- waypoint arrival tolerance
local STUCK_CHECK = 30       -- ticks between progress checks
local STUCK_MIN = 0.05       -- min tiles per check
local STUCK_MAX_STRIKES = 6  -- x strikes until stuck returns true
local MAX_REPLANS = 3         -- returns if replans too many times
local PENDING_GRACE = 180    -- ticks  before re-requesting path
local LOOKAHEAD= 1          -- tiles to look ahead to avoid flickering




-- Move toward a waypoint. Called from the walk executor.
local function step_toward(char, position)
  char.walking_state = {
    walking = true,
    direction = geom.direction_toward(position.x - char.position.x,
                                 position.y - char.position.y),
  }
end



-- returns true if stuck-failure triggered
local function stuck_check(task, char)


  if game.tick - (task.last_check or task.created_tick) < STUCK_CHECK then
    return false
  end


  if task.last_pos and geom.within(char.position, task.last_pos, STUCK_MIN) then
     task.strikes = (task.strikes or 0) + 1
  else
    task.strikes = 0
  end

  task.last_check = game.tick
  task.last_pos = { x = char.position.x, y = char.position.y }

  return (task.strikes or 0) >= STUCK_MAX_STRIKES
end



local function replan(task, char)
  char.walking_state = { walking = false }

  task.phase = "planning"
  task.path, task.waypoint_index = nil, nil
  task.path_request_id = nil
  task.strikes = 0
  task.replan_count = (task.replan_count or 0) + 1
end


-- switch for different walk phases
local walk_phases= {}

walk_phases.planning= function (task, char, finish)

  if not task.path_request_id then
    task.path_request_id = pathing.request(task.target, task.stop_within or ARRIVE, char)
    task.request_tick = game.tick
    return
  end

  
  local path_response = pathing.poll(task.path_request_id)

  if path_response == nil then
    if game.tick - task.request_tick > PENDING_GRACE then 
      replan(task, char)
    end
    return
  end

 if path_response.status == "done" then
      task.path, task.waypoint_index = path_response.path, 1
      table.insert(task.path, { x = task.target.x, y = task.target.y })  -- final approach
      task.phase = "following"
      return
  end

  -- engine bounced it; re-request
  if path_response.status == "lost" then
      replan(task, char)
      return
  end  

  -- "no_path"
  return finish(false, { reason = "no_path" })
    
    
  
end

walk_phases.following = function (task, char, finish)


  -- consume everything already inside the lookahead circle
  while task.path[task.waypoint_index + 1] and geom.within(char.position, task.path[task.waypoint_index], LOOKAHEAD) do
    task.waypoint_index = task.waypoint_index + 1
  end
  local wp = task.path[task.waypoint_index]


  if stuck_check(task, char) then
    replan(task, char)                                    -- world changed, try a fresh path
    return
  end

  step_toward(char, wp)
  
end



-- movement executor
function movement.walk_to(task, char, finish)
  
  local arrive = task.stop_within or ARRIVE

  if geom.within(char.position, task.target, arrive) then
    return finish(true, { position = { x = char.position.x, y = char.position.y } })
  end

  if (task.replan_count or 0) > MAX_REPLANS then
    return finish(false, { reason = "no_path", detail = "replan_limit" })
  end

  task.phase = task.phase or "planning"

  walk_phases[task.phase] (task, char, finish) 


end


return movement