-- -- USAGE:
-- --
-- -- 1) include this module to your script with:
--       local act = require("main.action")
-- -- 2) create new GameObject domain (if you are in .script file)
--       local domain = act.GO_DOMAIN()
-- --    or new GUI domain (if you are in .gui_script file)
--       local domain = act.GUI_DOMAIN()
-- -- 3) create some actions. Note that "actor_id" is:
-- --    either the 'url' of your game object, or the 'id' of your gui node
--       local scale = act.scaleTo("actor_id", 1.5, 0.25)
--       local rotate = act.rotateTo("actor_id", 90, 0.25)
--       local runsAllTogether = act.group({scale, rotate})
--       local runsOneByOne = act.chain({scale, rotate})
--       local repeatsFiveTimes = act.loop(runsOneByOne, 5)
-- -- 3.2) add the following line to on_message() function in your script:
-- --    this is required to proxy flipbook action completion messages back to action.lua
--       act.on_message(domain, message_id, message, sender)
-- -- 4) run the action (first arg is always your domain)
-- --    make sure that you call act.run(...) after your script's init() get called
-- --    it's ok to run actions right from within init() function itself
--       act.run(domain, repeatsFiveTimes)

local act = {}

-- this constants can be changed
--
local DEBUG_ACTIONS = false
local LOG_ACT_ANIM = false
local LOG_GO_ANIMATE = false
local LOG_GUI_ANIMATE = false
-- don't change the following constants
--
act.STATE_WILL_RUN = 0
act.STATE_RUNNING = 1
act.STATE_COMPLETED = 2

act.TYPE_UNDEFINED = -1
act.TYPE_ANIM = 0
act.TYPE_GROUP = 1
act.TYPE_CHAIN = 2
act.TYPE_LOOP = 3
act.TYPE_BOOK = 4

act.FOREVER = -1
act.PLAYBACK_ONCE = -1
act.EASING_LINEAR = -1

-- #########################
-- ### ACTION MANAGEMENT ###
-- #########################

function act.run(domain, action)
  if action.type == act.TYPE_ANIM then runAnim(domain, action)
  elseif action.type == act.TYPE_GROUP then runGroup(domain, action)
  elseif action.type == act.TYPE_CHAIN then runChain(domain, action)
  elseif action.type == act.TYPE_LOOP then runLoop(domain, action)
  elseif action.type == act.TYPE_BOOK then runBook(domain, action) end
end

function runAnim(domain, action)
  action.state = act.STATE_RUNNING
  domain.runningAnims[key(action)] = action
  debugPrint("RA++", domain, action)
  domain.animator(action, function() onActionComplete(domain, action) end)
end

function runGroup(domain, group)
  group.state = act.STATE_RUNNING
  domain.runningGroups[key(group)] = group
  debugPrint("RG++", domain, group)
  for i=1, #group.actions do act.run(domain, group.actions[i]) end
end

function runChain(domain, chain)
  chain.state = act.STATE_RUNNING
  domain.runningChains[key(chain)] = chain
  debugPrint("RC++", domain, chain)
  act.run(domain, chain.actions[1])
end

function runLoop(domain, loop)
  loop.state = act.STATE_RUNNING
  domain.runningLoops[key(loop)] = loop
  debugPrint("RL++", domain, loop)
  act.run(domain, loop.loop.action)
end

function runBook(domain, action)
  action.state = act.STATE_RUNNING
  local b_key = key(action)
  domain.runningBooks[b_key] = action
  debugPrint("RB++", domain, action)
  msg.post(action.book.actor_id, "play_animation", {id = hash(action.book.anim_id)})
end

function act.on_message(domain, message_id, message, sender)
  if message_id == hash("animation_done") and message.id ~= nil then
    for key,action in pairs(domain.runningBooks) do
      if sender == msg.url(action.book.actor_id) and hash(message.id) == hash(action.book.anim_id) then
        onActionComplete(domain,action)
      end
    end
  end
end

function onActionComplete(domain, action)
  -- print("onActionComplete: " .. action.type)
  -- pprint(action)

  if action.type == act.TYPE_ANIM then
    -- on anim action completed
    local a_key = key(action)
    domain.runningAnims[a_key] = nil
    action.state = act.STATE_COMPLETED
    if action.complete ~= nil then action.complete(action) end
    debugPrint("RA--", domain, action)
  elseif action.type == act.TYPE_BOOK then
    -- on book action complete
    local b_key = key(action)
    domain.runningBooks[b_key] = nil
    action.state = act.STATE_COMPLETED
    if action.complete ~= nil then action.complete(action) end
    debugPrint("RB--", domain, action)
  end
  -- now check if parent action (group, chain or loop) completed
  checkIfParentComplete(domain, action.parentGroup, domain.runningGroups)
  checkIfParentComplete(domain, action.parentChain, domain.runningChains)
  checkIfParentComplete(domain, action.parentLoop, domain.runningLoops)
end

function checkIfParentComplete(domain, parentKey, parentArray)
  if parentKey == nil then return false end
  local parent = parentArray[parentKey]
  if parent == nil then return false end

  -- print("checkIfParentComplete: " .. parentKey)

  if parent.type == act.TYPE_GROUP then
    return checkIfGroupComplete(domain, parentKey, parent)
  elseif parent.type == act.TYPE_CHAIN then
    return checkIfChainComplete(domain, parentKey, parent)
  elseif parent.type == act.TYPE_LOOP then
    return checkIfLoopComplete(domain, parentKey, parent)
  end
end

function checkIfGroupComplete(domain, key, group)
  for i = 1, #group.actions do
    if group.actions[i].state ~= act.STATE_COMPLETED then return false end
  end
  -- on group action completed
  domain.runningGroups[key] = nil
  group.state = act.STATE_COMPLETED
  debugPrint("RG--", domain, group)
  if group.complete ~= nil then group.complete(group) end
  onActionComplete(domain, group)
  return  true
end

function checkIfChainComplete(domain, key, chain)
  for i = 1, #chain.actions do
    if chain.actions[i].state ~= act.STATE_COMPLETED then
      act.run(domain, chain.actions[i]) -- run next action from chain
      return false -- some action not completed yet
    end
  end
  -- on chain action completed
  domain.runningChains[key] = nil
  chain.state = act.STATE_COMPLETED
  debugPrint("RС--", domain, chain)
  if chain.complete ~= nil then chain.complete(chain) end
  onActionComplete(domain, chain)
  return true
end

function checkIfLoopComplete(domain, key, loop)
  -- print("checkIfLoopComplete")
  -- chain completed
  loop.loop.repeats = loop.loop.repeats - 1
  if loop.loop.repeats > 0 or loop.loop.repeats < 0 then
    local action = loop.loop.action
    if (action.state == act.STATE_COMPLETED and action.actions ~= nil) then
      for i=1,#action.actions do action.actions[i].state = act.STATE_NOT_RUNNING end
    end
    act.run(domain, action)
    return false
  end
  -- on loop action complete
  domain.runningLoops[key] = nil
  loop.state = act.STATE_COMPLETED
  debugPrint("RL--", domain, loop)
  if loop.complete ~= nil then loop.complete(loop) end
  onActionComplete(domain, loop)
  return true
end

-- ###############
-- ### HELPERS ###
-- ###############

function debugPrint(prefix, domain, action)
  if (DEBUG_ACTIONS) then
    if action.type == act.TYPE_ANIM then
      print(prefix.."["..length(domain.runningAnims).."]: "..key(action).."->"..action.anim.to)
    elseif action.type == act.TYPE_GROUP then
      print(prefix.."["..length(domain.runningGroups).."]: "..key(action))
    elseif action.type == act.TYPE_CHAIN then
      print(prefix.."["..length(domain.runningChains).."]: "..key(action))
    elseif action.type == act.TYPE_LOOP then
      print(prefix.."["..length(domain.runningLoops).."]: "..key(action))
    elseif action.type == act.TYPE_BOOK then
      print(prefix.."["..length(domain.runningBooks).."]: "..key(action))
    end
  end
end

function act.GUI_DOMAIN()
  return {
    animator = gui_animate,
    runningAnims = {}, runningGroups = {}, runningChains = {}, runningLoops = {}, runningBooks = {}
  }
end

function act.GO_DOMAIN()
  return {
    animator = go_animate,
    runningAnims = {}, runningGroups = {}, runningChains = {}, runningLoops = {}, runningBooks = {}
  }
end

function gui_animate(action, complete_func)
  local anim = action.anim

  local playback = (anim.playback == act.PLAYBACK_ONCE) and gui.PLAYBACK_ONCE_FORWARD or anim.playback
  local easing = (anim.playback == act.EASING_LINEAR) and gui.EASING_LINEAR or anim.easing

  local node = anim.actor_id -- string
  local prop = anim.gui.property -- string
  local to = anim.gui.to -- object
  local dur = anim.duration -- number
  local delay = anim.delay -- number

  gui.animate(gui.get_node(node), prop, to, easing, dur, delay, complete_func, playback)
  if LOG_GO_ANIMATE then
    print("gui.animate(gui.get_node(\""..node.."\"),"..prop..","..tostring(to)..","..easing..","..dur..","..delay..",onComplete(),"..playback..")")
  end
  if LOG_ACT_ANIM then
    print("gui: "..node.."["..prop.."] -> "..tostring(to).." ("..dur.." sec)")
  end
end

function go_animate(action, complete_func)
  local anim = action.anim

  local playback = (anim.playback == act.PLAYBACK_ONCE) and go.PLAYBACK_ONCE_FORWARD or anim.playback
  local easing = (anim.playback == act.EASING_LINEAR) and go.EASING_LINEAR or anim.easing

  local url = anim.actor_id -- string
  local prop = anim.go.property -- string
  local to = anim.go.to -- object
  local dur = anim.duration -- number
  local delay = anim.delay -- number

  go.animate(url, prop, playback, to, easing, dur, delay, complete_func)
  if LOG_GUI_ANIMATE then
    print("go.animate(\""..url.."\"),"..prop..","..playback..","..tostring(to)..","..easing..","..dur..","..delay..",onComplete())")
  end
  if LOG_ACT_ANIM then
    print("go: "..url.."["..prop.."] -> "..tostring(to).." ("..dur.." sec)")
  end
end

function length(kvtable)
  local count = 0
  for k,v in pairs(kvtable) do count = count+1 end
  return count
end

function copyToFrom(toAction, fromAction)
  -- print("copyFrom: " .. fromAction.type)
  toAction.type = fromAction.type
  toAction.state = fromAction.state
  toAction.complete = fromAction.complete
  toAction.parentGroup = fromAction.parentGroup
  toAction.parentChain = fromAction.parentChain
  toAction.parentLoop = fromAction.parentLoop
  if fromAction.anim ~= nil then
    toAction.anim = {}
    toAction.anim.go = {}
    toAction.anim.gui = {}
    toAction.anim.actor_id = fromAction.anim.actor_id
    toAction.anim.property = fromAction.anim.property
    toAction.anim.go.property = fromAction.anim.go.property
    toAction.anim.gui.property = fromAction.anim.gui.property
    toAction.anim.to = fromAction.anim.to
    toAction.anim.go.to = fromAction.anim.go.to
    toAction.anim.gui.to = fromAction.anim.gui.to
    toAction.anim.duration = fromAction.anim.duration
    toAction.anim.delay = fromAction.anim.delay
    toAction.anim.playback = fromAction.anim.playback
    toAction.anim.easing = fromAction.anim.easing
  end
  if fromAction.actions ~= nil then -- group or chain
    toAction.actions = {}
    for i = 1, #fromAction.actions do
      toAction.actions[i] = {}
      copyToFrom(toAction.actions[i], fromAction.actions[i])
    end
  end
  if fromAction.loop ~= nil then
    toAction.loop = {}
    toAction.loop.repeats = fromAction.loop.repeats
    toAction.loop.action = {}
    copyToFrom(toAction.loop.action, fromAction.loop.action)
  end
  if fromAction.book ~= nil then
    toAction.book = {}
    toAction.book.actor_id = fromAction.book.actor_id
    toAction.book.anim_id = fromAction.book.anim_id
  end
end

function key(action)
  local k = nil
  if action.key ~= nil then
    k = action.key
  elseif action.type == act.TYPE_ANIM then
    k = action.anim.actor_id .. "[" .. action.anim.property .. "]"
  elseif action.type == act.TYPE_GROUP or action.type == act.TYPE_CHAIN then
    k = key(action.actions[1])
    for i=2, #action.actions do k = k .. " " .. key(action.actions[i]) end
  elseif action.type == act.TYPE_LOOP then
    k = key(action.loop.action)
  elseif action.type == act.TYPE_BOOK then
    k = action.book.actor_id .. "[" .. action.book.anim_id .. "]"
  end
  action.key = hash(k)
  return action.key
end

-- ###########################
-- ### ACTION DECLARATIONS ###
-- ###########################

-- Actions Hierarchy:
--    baseAction
--      groupAction
--      chainAction
--      loopAction
--      bookAction
--      animAction
--        scaleTo
--        rotateTo
--
function baseAction(complete)
  local action = {}
  -- common properties
  action.type = act.TYPE_UNDEFINED
  action.state = act.STATE_WILL_RUN
  action.complete = complete
  -- specific properties
  action.actions = nil -- for groups and chains
  action.loop = nil -- for loops
  action.anim = nil -- for animations
  action.parentGroup = nil -- for actions inside a group
  action.parentChain = nil -- for actions inside a chain
  action.parentLoop = nil -- for actions inside a loop
  return action
end

function act.group(actions, complete)
  local group = baseAction(complete)
  group.type = act.TYPE_GROUP
  group.actions = {}
  for i = 1, #actions do
    group.actions[i] = {}
    copyToFrom(group.actions[i], actions[i])
  end
  local key = key(group)
  for i = 1, #group.actions do group.actions[i].parentGroup = key end
  return group
end

function act.chain(actions, complete)
  local chain = baseAction(complete)
  chain.type = act.TYPE_CHAIN
  chain.actions = {}
  for i = 1, #actions do
    chain.actions[i] = {}
    copyToFrom(chain.actions[i], actions[i])
  end
  local key = key(chain)
  for i = 1, #chain.actions do chain.actions[i].parentChain = key end
  return chain
end

function act.loop(action, repeats, complete)
  -- print("act.loop")
  local loop = baseAction(complete)
  loop.type = act.TYPE_LOOP
  loop.loop = {}
  loop.loop.repeats = repeats
  loop.loop.action = {}
  -- print("copy from:")
  -- pprint(action)
  copyToFrom(loop.loop.action, action)
  loop.loop.action.parentLoop = key(loop)
  return loop
end

function act.book(actor_id, anim_id, complete)
  local action = baseAction(complete)
  action.type = act.TYPE_BOOK
  action.book = {}
  action.book.actor_id = actor_id
  action.book.anim_id = anim_id
  return action
end

function animAction(actor_id, property, to, duration, complete)
  local action = baseAction(complete)
  action.type = act.TYPE_ANIM
  action.anim = {}
  action.anim.actor_id = actor_id
  action.anim.property = property
  action.anim.to = to
  action.anim.go = {}
  action.anim.go.property = property
  action.anim.go.to = nil
  action.anim.gui = {}
  action.anim.gui.property = property
  action.anim.gui.to = nil
  action.anim.duration = duration
  action.anim.delay = 0
  action.anim.playback = act.PLAYBACK_ONCE
  action.anim.easing = act.EASING_LINEAR
  return action
end

function act.scaleTo(actor_id, scale, duration, complete)
  local action = animAction(actor_id, "scale", scale, duration, complete)
  local vec = vmath.vector3(scale, scale, 1)
  action.anim.go.to = vec
  action.anim.gui.to = vec
  return action
end

function act.rotateTo(actor_id, rotate, duration, complete)
  local action = animAction(actor_id, "rotate", rotate, duration, complete)
  action.anim.go.property = "euler.z"
  action.anim.gui.property = "rotation.z"
  action.anim.go.to = rotate
  action.anim.gui.to = vmath.vector3(0, 0, rotate)
  return action
end

function act.moveToXY(actor_id, x, y, duration, complete)
  local xy = "x:"..x..", y:"..y
  local action = animAction(actor_id, "position", xy, duration, complete)
  local vec = vmath.vector3()
  vec.x = x
  vec.y = y
  action.anim.go.to = vec
  action.anim.gui.to = vec
  return action
end

function act.fadeTo(actor_id, alpha, duration, complete)
  local action = animAction(actor_id, "alpha", alpha, duration, complete)
  action.anim.go.property = "tint.w"
  action.anim.gui.property = "color.w"
  action.anim.go.to = alpha
  action.anim.gui.to = alpha
  return action
end

function act.colorToRGBA(actor_id, r,g,b,a, duration, complete)
  local rgba = r..","..g..","..b..","..a
  local action = animAction(actor_id, "color", rgba, duration, complete)
  local vec = vmath.vector4(r, g, b, a)
  action.anim.go.property = "tint"
  action.anim.gui.property = "color"
  action.anim.go.to = vec
  action.anim.gui.to = vec
  return action
end

return act
