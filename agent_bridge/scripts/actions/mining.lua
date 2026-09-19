local geom = require("scripts.utils.geom")
local mining= {}

local MINABLE_RESOURCES= {"resource", "tree"}


local function resource_at(surface, position)
  local found = surface.find_entities_filtered{
    type = MINABLE_RESOURCES, position = position, radius = 0.6, limit = 1,
  }
  return found[1]
end


local function inventory_count(char, item)
  return char.get_main_inventory().get_item_count(item)
end


local function mined_amount(task, char)
  if not task.item then return 0 end
  return inventory_count(char, task.item) - task.starting_amount
end




function mining.mine_at(task, char, finish)
  if task.item and not task.starting_amount then
    task.starting_amount = inventory_count(char, task.item)
  end

  
  -- what to do if there is no entity
  if not (task.entity and task.entity.valid) then
    -- entity gone, if there was an entity here before, and no count, then mining finished
    if task.saw_entity and not task.count then
        return finish(true, { reason = "resource_seen_but_gone", mined = mined_amount(task, char)})
    end
    
    task.entity = resource_at(char.surface, task.position)

    if not task.entity then
        return finish(false, { reason = "resource_at_fail", mined = mined_amount(task, char)})
    end
    task.saw_entity = true
  end

  local ent = task.entity
  local reach = (ent.type == "resource") and char.resource_reach_distance or char.reach_distance
  if not geom.within(char.position, task.position, reach) then
    return finish(false, { reason = "out_of_reach", hint = "walk_to the resource first" })
  end

  if task.item and task.count then
    local mined =mined_amount(task, char)
    if mined >= task.count then return finish(true, { mined = mined }) end
  end

  if char.selected ~= ent then char.selected = ent end
  if not char.mining_state.mining then
    char.mining_state = { mining = true, position = ent.position }
  end
end

return mining