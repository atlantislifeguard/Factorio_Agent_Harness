## Embodied Agent Harness

This mod lets an external agent give console commands over RCON. Care is taken to only give 
the agent the same abilities as human players


Completed/Currently Testing: Walking, mining, hand-crafting and Placement


## Quick-Start

1. Put the mod in the Factorio mods folder on your machine
2. Run your Factorio game in single player
3. Open the console using the Tilde key (~)
4. you should be able to spawn the agent with the the following call 

```
/c remote.call('agent', 'spawn_agent', {})
```

Note that you might have to do this twice, as initially the console will give a warning regarding running commmands in the console


## Using an AI agent

You'll need to run the game as a dedicated RCON server and some kind of RCON client, the one I use for testing is factorio-rcon-py, and you'll use that to send commands to the server 


## API functions


### Setup

| Function | Arguments | Returns |
|---|---|---|
| `spawn_agent` | `{x=?, y=?}` | `{ok, position}`, or `agent_exists` |

### Observation (instant)

| Function | Arguments | Returns |
|---|---|---|
| `get_state` | — | tick, busy, current task, queue length, alive, position, health, inventory, crafting queue size, active crafts |
| `find_nearest` | `{name=?, type=?, radius=?}` (name or type required) | `{ok, name, position, distance, amount}` |
| `list_craftable` | — | hand-craftable recipes with how many can be made now |
| `can_hand_craft` | `{recipe=, count=?}` | `{ok}` or the reason, including missing ingredients |

### Blocking actions (queued, returns an id)

| Function | Arguments | Finishes when |
|---|---|---|
| `walk_to` | `{x=, y=, stop_within=?, timeout=?}` | within `stop_within` (default 0.35) of the target |
| `mine_at` | `{x=, y=, item=?, count=?, timeout=?}` | `count` of `item` mined, or the ore tile / tree is gone. Needs to be in reach: 2.7 tiles for ore, normal reach for trees |

### Non-Blocking actions (returns an id)

| Function | Arguments | Finishes when |
|---|---|---|
| `hand_craft` | `{recipe=, count=?, timeout=?}` | the product count reaches its target. Only one tracked craft per product at a time (`already_crafting` returns the running id); use `count` for several |

### Instant actions

| Function | Arguments | Returns |
|---|---|---|
| `place_entity` | `{name=, position={x=, y=}, direction=?}` | `{ok, name, unit_number, position, direction}`. The position snaps to the build grid; needs the item and build reach |
| `cancel_all` | — | cancels the body queue and all crafts (ingredients refunded); each gets a `cancelled` result |

### Results

| Function | Arguments | Returns |
|---|---|---|
| `take_result` | `{id=}` | `{ok, ready=true, result}`, `{ok, ready=false}` while running, or `unknown_id` |
| `drain_results` | — | every stored result at once (debugging; takes results others may be waiting on) |

