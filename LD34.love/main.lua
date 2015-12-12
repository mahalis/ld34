require "vectors"

local elapsedTime
local playing
local gameOver
local won

local playStartedTime

local positionHistory
local targets

local canonicalPathDistance
local CANONICAL_DISTANCE_FUDGE_FACTOR = 0.6

-- debugging total distance
local SHOW_CANONICAL_PATH = false
local canonicalPathPositionList

local isTurningLeft
local direction

local SPEED = 100
local TURN_AMOUNT = 0.02

local TARGET_COUNT = 7
local TARGET_MINIMUM_WALL_DISTANCE = 80
local TARGET_MINIMUM_TARGET_DISTANCE = 100
local TARGET_CONSUMPTION_DISTANCE = 23

local GROUND_Y = 60

function love.load()
	math.randomseed(os.time())

	reset()
end

function love.draw()
	
	local w, h = love.window.getDimensions()

	if playing then

		love.graphics.setColor(255, 255, 255, 100)
		love.graphics.rectangle("fill", 20, 20, 100, 20)
		love.graphics.setColor(255, 255, 255, 255)
		love.graphics.rectangle("fill", 20, 20, 100 * progressAmount(), 20)

		love.graphics.setLineWidth(1)
		love.graphics.line(0, GROUND_Y, w, GROUND_Y)

		if SHOW_CANONICAL_PATH then
			love.graphics.setLineWidth(1)
			for i = 2, #canonicalPathPositionList do
				local lastPosition = canonicalPathPositionList[i - 1]
				local thisPosition = canonicalPathPositionList[i]
				love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
			end
		end

		for i = 1, TARGET_COUNT do
			local target = targets[i]
			if target.consumed then
				love.graphics.setColor(50, 180, 20, 255)
			else
				love.graphics.setColor(180, 20, 60, 255)
			end
			love.graphics.circle("fill", target.position.x, target.position.y, 20)
		end

		love.graphics.setColor(255, 255, 255, 255)
		love.graphics.circle("fill", positionHistory[1].x, positionHistory[1].y, 10)
		love.graphics.setLineWidth(6)
		local positionCount = #positionHistory
		if positionCount > 1 then
			for i = 2, positionCount do
				local lastPosition = positionHistory[i - 1]
				local thisPosition = positionHistory[i]
				love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
			end
		end
	else
		if not gameOver then
			-- menu / title screen
		else
			if won then
				love.graphics.setColor(0, 200, 0, 255)
			else
				love.graphics.setColor(200, 0, 0, 255)
			end

			love.graphics.circle("fill", w / 2, h / 2, 100)
		end
	end
end

function love.update(dt)
	elapsedTime = elapsedTime + dt

	if playing then
		local position = positionHistory[#positionHistory]
		direction = vNorm(vAdd(direction, vMul(vRight(direction), (isTurningLeft and 1 or -1) * (TURN_AMOUNT * SPEED) * dt)))
		position = vAdd(position, vMul(direction, SPEED * dt))

		local allTargetsConsumed = true
		for i = 1, TARGET_COUNT do
			local target = targets[i]
			if not target.consumed and vDist(position, target.position) < TARGET_CONSUMPTION_DISTANCE then
				target.consumed = true
			end
			allTargetsConsumed = allTargetsConsumed and target.consumed
		end

		addNewPosition(position)
		if allTargetsConsumed == true and position.y < GROUND_Y then
			endGame(true)
		elseif progressAmount() > 1 then
			endGame(false)
		end
	end
end

function progressAmount()
	return (elapsedTime - playStartedTime) / (canonicalPathDistance / SPEED)
end

function reset()
	playing = false
	gameOver = false
	elapsedTime = 0
	isTurningLeft = (math.random() > 0.5) and true or false

	positionHistory = {}
	local w, h = love.window.getDimensions()
	local startingPosition = v(w * .5, h * .9)
	addNewPosition(startingPosition)
	direction = v(0,-1)

	targets = {}
	for i = 1, TARGET_COUNT do
		addTarget(v(TARGET_MINIMUM_TARGET_DISTANCE + math.random() * (w - 2 * TARGET_MINIMUM_WALL_DISTANCE), TARGET_MINIMUM_TARGET_DISTANCE + math.random() * (h - 2 * TARGET_MINIMUM_WALL_DISTANCE)))
	end
	for relaxationStep = 1, 5 do
		for i = 1, TARGET_COUNT do
			local originalPosition = targets[i].position

			local closestOtherTargetIndex = nil
			local closestOtherDistance = 0
			for j = 1, TARGET_COUNT do
				if i ~= j then
					local distance = vDist(originalPosition, targets[j].position)
					if closestOtherTargetIndex == nil or distance < closestOtherDistance then
						closestOtherTargetIndex = j
						closestOtherDistance = distance
					end
				end
			end

			local closestOtherTarget = targets[closestOtherTargetIndex]
			if closestOtherDistance < TARGET_MINIMUM_TARGET_DISTANCE then
				local awayMovementAmount = vNorm(vSub(originalPosition, closestOtherTarget.position), TARGET_MINIMUM_TARGET_DISTANCE - closestOtherDistance)
				local newPosition = vAdd(originalPosition, awayMovementAmount)
				newPosition.x = math.max(TARGET_MINIMUM_WALL_DISTANCE, math.min(w - TARGET_MINIMUM_WALL_DISTANCE, newPosition.x))
				newPosition.y = math.max(TARGET_MINIMUM_WALL_DISTANCE, math.min(h - TARGET_MINIMUM_WALL_DISTANCE, newPosition.y))
				targets[i].position = newPosition
			end
		end
	end

	local totalTargetDistance = 0
	local lastPathPosition = startingPosition
	local lastTargetIndex = nil
	canonicalPathPositionList = {startingPosition}
	for i = 1, TARGET_COUNT do
		local index = closestUnvisitedTargetIndex(lastPathPosition, lastTargetIndex)
		totalTargetDistance = totalTargetDistance + vDist(lastPathPosition, targets[index].position)
		lastPathPosition = targets[index].position
		targets[index].setupVisited = true
		canonicalPathPositionList[#canonicalPathPositionList + 1] = lastPathPosition
	end
	canonicalPathDistance = totalTargetDistance * (1.0 + CANONICAL_DISTANCE_FUDGE_FACTOR)
end

function closestUnvisitedTargetIndex(position, existingTargetIndex)
	local index = nil
	local closestDistance = 0
	for i = 1, #targets do
		if (existingTargetIndex == nil or i ~= existingTargetIndex) and targets[i].setupVisited == false then
			local distance = vDist(position, targets[i].position)
			if index == nil or distance < closestDistance then
				index = i
				closestDistance = distance
			end
		end
	end

	return index
end

function addTarget(position)
	local target = {}
	target.position = position
	target.consumed = false
	target.setupVisited = false -- used to calculate total distance between targets
	targets[#targets + 1] = target
end

function addNewPosition(position)
	positionHistory[#positionHistory + 1] = position
end

function start()
	playing = true
	playStartedTime = elapsedTime
end

function endGame(didWin)
	playing = false
	gameOver = true
	won = didWin
end

function love.keypressed(key)
	if key == "2" then
		isTurningLeft = not isTurningLeft
	elseif key == "left" then
		isTurningLeft = true
	elseif key == "right" then
		isTurningLeft = false
	end
end

function love.mousepressed(x, y, button)
	if not playing then
		if gameOver then
			reset()
		else
			start()
		end
	else
		
	end
end

function love.mousereleased(x, y, button)
	if playing then
		
	end
end

function mixColorTables(a, b, f)
	return {a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), a[3] + f * (b[3] - a[3])}
end

-- sine-curve interpolation
function slerp(a, b, f)
	f = math.max(math.min(f, 1), 0)

	return a + (b - a) * (1 - math.cos(f * math.pi)) / 2
end
