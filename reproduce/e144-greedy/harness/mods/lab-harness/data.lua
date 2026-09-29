-- Lab-only prototypes an experiment asks for: copies of a base inserter with
-- one field changed. Instruments, never gameplay.
local exp = require("experiment")
for _, v in ipairs(exp.inserter_variants or {}) do
  local proto = table.deepcopy(data.raw.inserter[v.base])
  proto.name = v.name
  proto.rotation_speed = v.rotation_speed
  proto.next_upgrade = nil
  proto.minable = nil
  data:extend{proto}
end
