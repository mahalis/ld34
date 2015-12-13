require "vectors"

local elapsedTime
local playing
local gameOver
local won

local playStartedTime
local gameOverTime

local GAME_OVER_TRANSITION_DURATION = 1.5

local positionHistory
local targets

local currentTimeLimit
local timeBonusPerTarget
local TIME_LIMIT_BONUS_MULTIPLIER = 0.5 -- targets give this much; base time is the rest plus the below amount
local TIME_LIMIT_BASE_MULTIPLIER = 0.7

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

local TIME_BAR_WIDTH = 200

local backgroundImage
local budImage, budDeadImage

function love.load()
	math.randomseed(os.time())

	local isHighDPI = (love.window.getPixelScale() > 1)
	backgroundImage = loadImage("background", isHighDPI)
	budImage = loadImage("bud", isHighDPI)
	budDeadImage = loadImage("bud-dead", isHighDPI)

	reset()
end

function loadImage(pathName, isHighDPI) -- omit “graphics/” and “.png”
	local desiredPath = "graphics/" .. pathName .. (isHighDPI and "@2x" or "") .. ".png"

	local image = nil
	if love.filesystem.isFile(desiredPath) then
		image = love.graphics.newImage(desiredPath)
	end

	return image or love.graphics.newImage("graphics/" .. pathName .. ".png")
end

function love.draw()
	
	local w, h = love.window.getDimensions()

	local pixelScale = love.window.getPixelScale()
	love.graphics.scale(pixelScale)

	local scaleMultiplier = 1 / pixelScale

	local lineEdgeColor = { 70, 180, 50 }
	local lineCoreColor = { 190, 230, 60 }

	local gameOverBlendFactor = 0
	if gameOver then
		gameOverBlendFactor = math.min(1, (elapsedTime - gameOverTime) / GAME_OVER_TRANSITION_DURATION)
		if not won then
			local deadLineEdgeColor = { 60, 70, 70 }
			local deadLineCoreColor = { 150, 150, 160 }
			lineEdgeColor = mixColorTables(lineEdgeColor, deadLineEdgeColor, gameOverBlendFactor)
			lineCoreColor = mixColorTables(lineCoreColor, deadLineCoreColor, gameOverBlendFactor)
		end

		love.graphics.translate(0, 200 * math.pow(.5 - .5 * math.cos(math.pi * gameOverBlendFactor), 2) * (won and 1 or -1))
	end
	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.draw(backgroundImage, 0, 0, 0, scaleMultiplier, scaleMultiplier)
	if playing or gameOver then
		local positionCount = #positionHistory
		if positionCount > 1 then
			-- TODO: add rhythmic pulse along whole length. thickness + color?
			local taperSegments = 50
			for i = 2, positionCount do
				local taperAmount = math.max(0, (i - (positionCount - taperSegments)) / taperSegments)
				local baseWidth = 8
				if taperAmount > 0 then
					baseWidth = 2 + 6 * (1.0 - taperAmount)
				end
				local lastPosition = positionHistory[i - 1]
				local thisPosition = positionHistory[i]
				love.graphics.setLineWidth(baseWidth)
				love.graphics.setColor(lineEdgeColor[1], lineEdgeColor[2], lineEdgeColor[3], 255)
				love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
				love.graphics.setColor(lineCoreColor[1], lineCoreColor[2], lineCoreColor[3], 255)
				love.graphics.setLineWidth(baseWidth * .5)
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

		local budImageOriginX, budImageOriginY = budImage:getWidth() * .5, budImage:getHeight() * .2
		love.graphics.setColor(255, 255, 255, 255)
		love.graphics.draw(budImage, positionHistory[1].x, positionHistory[1].y, 0, scaleMultiplier - .01 * gameOverBlendFactor, scaleMultiplier - .01 * gameOverBlendFactor, budImageOriginX, budImageOriginY)
		if gameOver and not won then
			love.graphics.setColor(255, 255, 255, 255 * gameOverBlendFactor)
			love.graphics.draw(budDeadImage, positionHistory[1].x, positionHistory[1].y, 0, scaleMultiplier, scaleMultiplier, budImageOriginX, budImageOriginY)
		end

		-- time bar
		if not gameOver then
			love.graphics.push()
			love.graphics.translate((w - TIME_BAR_WIDTH) / 2, h * 0.95)
			love.graphics.setColor(0, 200, 0, 100)
			love.graphics.rectangle("fill", 0, 0, TIME_BAR_WIDTH, 10)
			love.graphics.setColor(0, 200, 0, 255)
			love.graphics.rectangle("fill", 0, 0, TIME_BAR_WIDTH * (1 - progressAmount()), 10)
			love.graphics.pop()
		end
	else
		-- introductory text
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
				currentTimeLimit = currentTimeLimit + timeBonusPerTarget
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
	return (elapsedTime - playStartedTime) / currentTimeLimit
end

function reset()
	playing = false
	gameOver = false
	elapsedTime = 0
	isTurningLeft = (math.random() > 0.5) and true or false

	positionHistory = {}
	local w, h = love.window.getDimensions()
	local startingPosition = v(w * .5, h * .8)
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
				newPosition.y = math.max(TARGET_MINIMUM_WALL_DISTANCE + GROUND_Y, math.min(startingPosition.y - TARGET_MINIMUM_WALL_DISTANCE, newPosition.y))
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

	local totalTravelTime = totalTargetDistance / SPEED
	timeBonusPerTarget = (totalTravelTime / TARGET_COUNT) * (TIME_LIMIT_BONUS_MULTIPLIER)
	currentTimeLimit = totalTravelTime * ((1 - TIME_LIMIT_BONUS_MULTIPLIER) + TIME_LIMIT_BASE_MULTIPLIER)
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
	gameOverTime = elapsedTime
	won = didWin
end

function love.keypressed(key)
	if playing then
		if key == "2" then
			isTurningLeft = not isTurningLeft
		elseif key == "left" then
			isTurningLeft = true
		elseif key == "right" then
			isTurningLeft = false
		end
	else
		if key == "2" or key == "left" or key == "right" then
			-- TODO: don't allow resetting immediately after an end-game, it's too easy to miss the end-game screen
			handleNotPlayingInteraction()
		end
	end
end

function handleNotPlayingInteraction()
	-- TODO: allow retrying the same level, keep track of streak, etc. keyboard will do this via left/right, mouse via clicking the button or whatever
	if gameOver then
		reset()
	else
		start()
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
