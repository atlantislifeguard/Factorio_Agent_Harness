local crafting= {}

local DEFAULT_TIMEOUT = 60 * 60 -- ticks

-- Crafts run in the character's own crafting queue, in parallel with the body task
-- An id is issued  and posted on completion storage.crafts[id] = { recipe=, product=, before=, target=, started_tick=, timeout= }
-- Completion is judged by the product's inventory count
-- 1 product is allowed at a time (though multiple counts can work).


local function main_product(recipe)
  for _, product in pairs(recipe.products) do
    if product.type == "item" then return product end
  end
end


local function job_for_product(product_name)
  for id, job in pairs(storage.crafts or {}) do
    if job.product == product_name then return id end
  end
end


-- Starts the craft and returns an id, the result arrives later.
crafting.do_craft=  function(char, params, new_id)

  local flag= crafting.can_hand_craft(char, params)

  if not flag.ok then
    return flag
  end

  local recipe = char.force.recipes[params.recipe]
  local product = main_product(recipe)
  if not product then return { ok = false, reason = "no_item_product" } end

  local running = job_for_product(product.name)
  if running then
    return { ok = false, reason = "already_crafting", id = running,
             hint = "wait for this id, or raise count on a single craft" }
  end

  local before = char.get_main_inventory().get_item_count(product.name)
  local started = char.begin_crafting{ recipe = params.recipe, count = params.count or 1 }

  if started == 0 then
    return { ok = false, reason = "cannot_craft",
             hint = "unknown_error_try_again" }
  end

  local id = new_id()
  storage.crafts = storage.crafts or {}
  storage.crafts[id] = {
    recipe = params.recipe,
    product = product.name,
    before = before,
    target = before + started * (product.amount or product.amount_max or 1),
    started_tick = game.tick,
    timeout = params.timeout or DEFAULT_TIMEOUT,
  }
  return { ok = true, id = id, started = started, product = product.name }
end


-- Called every tick. Posts a result for each tracked craft that has finished.
crafting.tick = function(char, push_result)
  if not storage.crafts or next(storage.crafts) == nil then return end
  if not char then return crafting.fail_all(push_result, "no_character") end

  local inv = char.get_main_inventory()
  for id, job in pairs(storage.crafts) do
    local count = inv.get_item_count(job.product)
    local crafted = math.max(0, count - job.before)
    local data = { recipe = job.recipe, product = job.product, crafted = crafted }

    if count >= job.target then
      storage.crafts[id] = nil
      push_result(id, true, data)
    elseif char.crafting_queue_size == 0 then
      -- queue drained but count short: the product was used or moved mid-craft
      storage.crafts[id] = nil
      data.note = "queue_empty_count_uncertain"
      push_result(id, true, data)
    elseif game.tick - job.started_tick > job.timeout then
      storage.crafts[id] = nil                     -- craft keeps going, just untracked
      data.reason = "timeout"
      push_result(id, false, data)
    end
  end
end


-- Stop tracking every craft and post `reason` for each (death, missing character).
crafting.fail_all = function(push_result, reason)
  for id, job in pairs(storage.crafts or {}) do
    push_result(id, false, { reason = reason, recipe = job.recipe, product = job.product })
  end
  storage.crafts = {}
end


-- Cancel the character's whole crafting queue (ingredients are refunded) and fail
-- the tracked crafts as cancelled.
crafting.cancel_all = function(char, push_result)
  if char then
    for _ = 1, 100 do                             -- guard: each pass removes one entry
      local queue = char.crafting_queue
      if not queue or #queue == 0 then break end
      local last = queue[#queue]
      char.cancel_crafting{ index = last.index, count = last.count }
    end
  end
  crafting.fail_all(push_result, "cancelled")
end


crafting.is_pending = function(id)
  return storage.crafts ~= nil and storage.crafts[id] ~= nil
end


crafting.summary = function()
  local out = {}
  for id, job in pairs(storage.crafts or {}) do
    table.insert(out, { id = id, recipe = job.recipe, product = job.product })
  end
  return out
end


crafting.can_hand_craft= function(char, params)

  local count = params.count or 1
  if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
    return { ok = false, reason = "invalid_count" }
  end

  local recipe_name= params.recipe or ""
  local recipe = char.force.recipes[recipe_name]

  if not recipe then return { ok = false, reason = "unknown_recipe" } end
  if recipe.hidden then return  { ok = false, reason = "recipe_hidden" } end
  if not recipe.enabled then return { ok = false, reason = "recipe_locked" } end
  if not char.prototype.crafting_categories[recipe.category] then
    return { ok = false, reason = "not_hand_craftable", category = recipe.category }
  end

  local craftable_count = char.get_craftable_count(recipe_name)
  if craftable_count >= count then return { ok = true, craftable = craftable_count } end

  local inventory= char.get_main_inventory()
  local missing =  {}

  for _, ingredient in pairs(recipe.ingredients) do
    local deficit = ingredient.amount * count - inventory.get_item_count(ingredient.name)
    if deficit > 0 then missing[ingredient.name] = deficit end
  end
  return { ok = false, reason = "missing_ingredients", craftable = craftable_count, missing = missing }

end


crafting.list_craftable= function(char)
    
    local craftable_list= {}
    local craftable_categories= char.prototype.crafting_categories
    for recipe_name, recipe_object in pairs(char.force.recipes) do
       
        local is_enabled= recipe_object.enabled
        local is_not_hidden= not recipe_object.hidden
        local is_hand_craftable= craftable_categories[recipe_object.category]

        if is_enabled and is_not_hidden and is_hand_craftable then
            local count= char.get_craftable_count(recipe_name)
            table.insert(craftable_list, {recipe= recipe_name, craftable=count })
        end
        
        
    end

    table.sort(craftable_list, function(x, y) return x.craftable> y.craftable end )

    return {ok = true, craftable_list= craftable_list}

end

return crafting
