require "vectors"

local elapsedTime
local playing
local gameOver

local positionHistory
local isTurningLeft
local direction

local SPEED = 80
local TURN_AMOUNT = 0.02

function love.load()
	math.randomseed(os.time())

	reset()
end

function love.draw()
	love.graphics.setColor(255, 255, 255, 255)
	local w, h = love.window.getDimensions()

	love.graphics.setLineWidth(6)
	local positionCount = #positionHistory
	if positionCount > 1 then
		for j = 2, positionCount do
			local lastPosition = positionHistory[j - 1]
			local thisPosition = positionHistory[j]
			love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
		end
	end
end

function love.update(dt)
	elapsedTime = elapsedTime + dt

	local position = positionHistory[#positionHistory]
	direction = vNorm(vAdd(direction, vMul(vRight(direction), (isTurningLeft and 1 or -1) * (TURN_AMOUNT * SPEED) * dt)))
	position = vAdd(position, vMul(direction, SPEED * dt))
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
