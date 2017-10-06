## Installation
You can use this module in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

	https://github.com/squatchus/defold-animactions/archive/master.zip


## Usage
```lua
-- 1) include this module to your script with:
      local act = require("main.action")
-- 2) create new GameObject domain (if you are in .script file)
      local domain = act.GO_DOMAIN()
--    or new GUI domain (if you are in .gui_script file)
      local domain = act.GUI_DOMAIN()
-- 3) create some actions. Note that "actor_id" is:
--    either the 'url' of your game object, or the 'id' of your gui node
      local scale = act.scaleTo("actor_id", 1.5, 0.25)
      local rotate = act.rotateTo("actor_id", 90, 0.25)
      local runsAllTogether = act.group({scale, rotate})
      local runsOneByOne = act.chain({scale, rotate})
      local repeatsFiveTimes = act.loop(runsOneByOne, 5)
-- 3.2) if you use flipbook animation, add the following line to on_message() function in your script:
--    this is required to proxy flipbook completion messages back to action.lua
      act.on_message(domain, message_id, message, sender)
-- 4) run the action (first arg is always your domain)
      act.run(domain, repeatsFiveTimes)
```

## Example
![animation](./preview.gif)

```lua
local act = require("shared.action")
local domain = act.GO_DOMAIN()

function init(self)
	local id = "main:/logo"
	local pulse = act.chain({
		act.scaleTo(id, 1.100, 6/60),
		act.scaleTo(id, 1.025, 10/60),
		act.scaleTo(id, 1.050, 6/60),
		act.scaleTo(id, 1.000, 6/60),
		act.rotateTo(id, 15, 7/60),
		act.rotateTo(id, -15, 14/60),
		act.rotateTo(id, 0, 7/60)
	})
	act.run(domain, act.loop(pulse, act.FOREVER))
end
```
