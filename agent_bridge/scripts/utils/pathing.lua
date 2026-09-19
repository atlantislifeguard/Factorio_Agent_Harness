local pathing = {}


-- Issue a path request. Returns the engine request id, or nil if no character.
function pathing.request(target_position, radius, char)
  
  if not char then return nil end

  local id = char.surface.request_path{
    bounding_box   = char.prototype.collision_box,
    collision_mask = char.prototype.collision_mask,
    start          = char.position,
    goal           = target_position,
    force          = char.force,
    radius         = radius or 1,
    entity_to_ignore = char,
  }

  storage.path_requests = storage.path_requests or {}
  storage.path_requests[id] = { status = "pending", tick = game.tick }
  return id
end

-- Event handler. Register in control.lua.
function pathing.on_path_finished(event)
  local entry = storage.path_requests and storage.path_requests[event.id]
  if not entry then return end                      -- not ours

  if event.try_again_later then
    storage.path_requests[event.id] = nil           -- caller re-requests on poll miss
  elseif not event.path then
    entry.status = "no_path"
  else
    entry.status = "done"
    entry.path = {}
    for i, wp in ipairs(event.path) do
      entry.path[i] = { x = wp.position.x, y = wp.position.y }
    end
  end
end

-- Movemen executor calls this each tick with its stored id. Returns nil while pending;
-- {status="done", path={...}} or {status="no_path"} once resolved.
function pathing.poll(id)
  local entry = storage.path_requests and storage.path_requests[id]
  if not entry then return { status = "lost" } end   -- dropped/try_again_later: re-request
  if entry.status == "pending" then return nil end
  storage.path_requests[id] = nil
  return entry
end



return pathing