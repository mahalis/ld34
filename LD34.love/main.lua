require "vectors"

local elapsedTime
local playing
local gameOver

local positionHistory
local targets

local isTurningLeft
local direction

local SPEED = 80
local TURN_AMOUNT = 0.02

local TARGET_COUNT = 7
local TARGET_MINIMUM_WALL_DISTANCE = 80
local TARGET_MINIMUM_TARGET_DISTANCE = 100
local TARGET_CONSUMPTION_DISTANCE = 15

function love.load()
	math.randomseed(os.time())

	reset()
end

function love.draw()
	
	local w, h = love.window.getDimensions()

	for i = 1, TARGET_COUNT do
		local target = targets[i]
		if target.consumed then
			love.graphics.setColor(50, 180, 20, 255)
		else
			love.graphics.setColor(180, 20, 60, 255)
		end
		love.graphics.circle("fill", target.position.x, target.position.y, 10)
	end

	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.setLineWidth(6)
	local positionCount = #positionHistory
	if positionCount > 1 then
		for i = 2, positionCount do
			local lastPosition = positionHistory[i - 1]
			local thisPosition = positionHistory[i]
			love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
		end
	end
end

function love.update(dt)
	elapsedTime = elapsedTime + dt

	local position = positionHistory[#positionHistory]
	direction = vNorm(vAdd(direction, vMul(vRight(direction), (isTurningLeft and 1 or -1) * (TURN_AMOUNT * SPEED) * dt)))
	position = vAdd(position, vMul(direction, SPEED * dt))

	for i = 1, TARGET_COUNT do
		local target = targets[i]
		if not target.consumed and vDist(position, target.position) < TARGET_CONSUMPTION_DISTANCE then
			target.consumed = true
		end
	end

	addNewPosition(position)
end

function reset()
	playing = false
	gameOver = false
	elapsedTime = 0
	isTurningLeft = (math.random() > 0.5) and true or false

	positionHistory = {}
	local w, h = love.window.getDimensions()
	addNewPosition(v(w * .5, h * .9))
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
end

function addTarget(position)
	local target = {}
	target.position = position
	target.consumed = false
	targets[#targets + 1] = target
end

function addNewPosition(position)
	positionHistory[#positionHistory + 1] = position
end

function start()
	playing = true
end

function endGame()
	playing = false
	gameOver = true
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
