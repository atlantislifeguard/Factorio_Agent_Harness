local geom = require("scripts.utils.geom")
local placement= {}

-- Snap to the build grid the way cursor building does
local function snap(proto, position, direction)
  local w, h = proto.tile_width, proto.tile_height
  if direction == defines.direction.east or direction == defines.direction.west then
    w, h = h, w
  end
  local function axis(v, size)
    if size % 2 == 0 then return math.floor(v + 0.5) end
    return math.floor(v) + 0.5
  end
  return { x = axis(position.x, w), y = axis(position.y, h) }
end


-- The agent's character has no cursor, so this builds directly on the surface,
placement.do_place= function (char, params)

  local build_pos = params.position
  if not build_pos then return {ok=false, reason= "no_position_specified"} end

  local build_dir = params.direction or defines.direction.north

  local item = prototypes.item[params.name]
  local proto = item and item.place_result
  if not proto then return {ok= false, reason= "not_buildable_entity"} end

  local inv = char.get_main_inventory()
  if inv.get_item_count(params.name) < 1 then return { ok = false, reason = "no_item" } end

  local pos = snap(proto, build_pos, build_dir)
  if not geom.within(char.position, pos, char.build_distance) then
    return { ok = false, reason = "out_of_reach", hint = "walk_to closer first" }
  end

  local surface = char.surface
  local spec = { name = proto.name, position = pos, direction = build_dir, force = char.force }

  --to-do add local funtion checking for failure states, ie obstructions, terrain, etc
  spec.build_check_type = defines.build_check_type.manual
  if not surface.can_place_entity(spec) then return { ok = false, reason = "cannot_place" } end
  spec.build_check_type = nil

  spec.raise_built = true
  local new_structure = surface.create_entity(spec)
  if not new_structure then return { ok = false, reason = "building_not_found" } end

  inv.remove{ name = params.name, count = 1 }

  return { ok = true, name = new_structure.name, unit_number = new_structure.unit_number,
         direction = new_structure.direction,
         position = { x = new_structure.position.x, y = new_structure.position.y } }

end


return placement
