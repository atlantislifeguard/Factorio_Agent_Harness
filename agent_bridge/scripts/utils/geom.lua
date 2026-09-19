local geom= {}


local OCTANTS = {
  defines.direction.east,  defines.direction.southeast,
  defines.direction.south, defines.direction.southwest,
  defines.direction.west,  defines.direction.northwest,
  defines.direction.north, defines.direction.northeast,
}


--calculate angle using x y coordinates, and snaps to octant
function geom.direction_toward(dx, dy)
  local angle = math.atan2(dy, dx)
  local octant = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8
  return OCTANTS[octant + 1]
end


--square distance between 2 points
function geom.dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

function geom.within(current, target, limit)

  return limit>=0 and geom.dist2(current, target) <= limit* limit

end

return geom