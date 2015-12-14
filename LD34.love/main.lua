require "vectors"

local elapsedTime
local playing
local gameOver
local won
local winStreak

local playStartedTime
local gameOverTime

local GAME_OVER_TRANSITION_DURATION = 1.5
local GAME_OVER_GROWTH_TIME = 1

local positionHistory
local branchHistory
local targets

local BRANCH_LENGTH_MIN = 30
local BRANCH_LENGTH_MAX = 60
local BRANCH_CURVATURE = 0.01

local currentTimeLimit
local timeBonusPerTarget
local TIME_LIMIT_BONUS_MULTIPLIER = 0.5 -- targets give this much; base time is the rest plus the below amount
local TIME_LIMIT_BASE_MULTIPLIER = 0.7

local OFF_SCREEN_EDGE_THRESHOLD = 40

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
local TARGET_CONSUMPTION_DISTANCE = 30

local GROUND_Y = 60

local TIME_BAR_WIDTH = 106

local backgroundImage
local budImage, budDeadImage
local foodImages, foodHoleImages
local FOOD_IMAGE_COUNT = 2

local flowerCoreImage
local flowerPetalImages
local flowerPetalImageOrigins
local flowerPetalOffsets
local flowerPetalSequenceIndices

local titleFont, headerFont, bodyFont, footerFont

function love.load()
	math.randomseed(os.time())

	local isHighDPI = (love.window.getPixelScale() > 1)
	backgroundImage = loadImage("background", isHighDPI)
	budImage = loadImage("bud", isHighDPI)
	budDeadImage = loadImage("bud-dead", isHighDPI)
	foodImages = {}
	foodHoleImages = {}
	for i = 1, FOOD_IMAGE_COUNT do
		foodImages[i] = loadImage("food-" .. tostring(i), isHighDPI)
		foodHoleImages[i] = loadImage("food-" .. tostring(i) .. "-hole", isHighDPI)
	end

	local flowerPetalImageNames = { "back", "back left", "back right", "front left", "front right", "front" } -- draw order
	local relativePetalOrigins = { v(.44, .88), v(.82, .7), v(.15, .77), v(.85, .3), v(.1, .22), v(.46, .12) } 
	flowerPetalImages = {}
	flowerPetalImageOrigins = {}
	for i = 1, #flowerPetalImageNames do
		local petalImage = loadImage("flower " .. flowerPetalImageNames[i], isHighDPI)
		flowerPetalImages[i] = petalImage
		local petalWidth, petalHeight = petalImage:getWidth(), petalImage:getHeight()
		local relativeOrigin = relativePetalOrigins[i]
		flowerPetalImageOrigins[i] = v(relativeOrigin.x * petalWidth, relativeOrigin.y * petalHeight)
	end
	flowerCoreImage = loadImage("flower core", isHighDPI)

	flowerPetalOffsets = { v(0, 3), nil, v(5, 3), nil, v(5, 0), v(2, 0) }
	flowerPetalSequenceIndices = { 2, 1, 3, 0, 4, 5 }

	local fontPath = "font/notperfect regular.ttf"
	titleFont = love.graphics.newFont(fontPath, 64)
	headerFont = love.graphics.newFont(fontPath, 40)
	bodyFont = love.graphics.newFont(fontPath, 32)
	footerFont = love.graphics.newFont(fontPath, 24)

	winStreak = 0

	reset(false)
end

function loadImage(pathName, isHighDPI) -- omit “graphics/” and “.png”
	local desiredPath = "graphics/" .. pathName .. (isHighDPI and "@2x" or "") .. ".png"

	return love.graphics.newImage(desiredPath)
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
		gameOverBlendFactor = 1 - math.pow(.5 + .5 * math.cos(math.pi * math.min(1, (elapsedTime - gameOverTime) / GAME_OVER_TRANSITION_DURATION)), 2)
		if not won then
			local deadLineEdgeColor = { 60, 70, 70 }
			local deadLineCoreColor = { 150, 150, 160 }
			lineEdgeColor = mixColorTables(lineEdgeColor, deadLineEdgeColor, gameOverBlendFactor)
			lineCoreColor = mixColorTables(lineCoreColor, deadLineCoreColor, gameOverBlendFactor)
		end

		love.graphics.translate(0, 200 * gameOverBlendFactor * (won and 1 or -1))
	end
	love.graphics.setColor(255, 255, 255, 255)
	love.graphics.draw(backgroundImage, 0, -200, 0, scaleMultiplier, scaleMultiplier)

	if playing or gameOver then
		-- foods
		love.graphics.setColor(255, 255, 255, 255)
		for i = 1, TARGET_COUNT do
			local target = targets[i]
			local foodImage = (target.consumed and foodHoleImages or foodImages)[target.imageIndex]
			local foodImageOriginX, foodImageOriginY = foodImage:getWidth() * .5, foodImage:getHeight() * .6
			local foodScale = (target.consumed and 1 or (1 + math.max(0, math.sin(math.pi * (elapsedTime * 2 + target.pulsePhase))) * 0.05))
			love.graphics.draw(foodImage, target.position.x, target.position.y, target.tilt * 0.2, scaleMultiplier * foodScale, scaleMultiplier * foodScale, foodImageOriginX, foodImageOriginY)
		end

		-- TODO: switch both main path and branches to draw full thick line before thin line (avoid visible segmentation)

		-- branches
		for i = 1, #branchHistory do
			local branch = branchHistory[i]
			local branchPath = branch.path
			local branchSegmentCount = #branchPath
			local branchTime = 1 - math.pow(1 - math.min(1, (elapsedTime - branch.time) / 1.2), 3)
			for j = 2, branchSegmentCount do
				local baseWidth = 7 * (branchTime - (j / branchSegmentCount))
				if baseWidth > 0.1 then
					local lastPosition = branchPath[j - 1]
					local thisPosition = branchPath[j]

					love.graphics.setLineWidth(baseWidth)
					love.graphics.setColor(lineEdgeColor[1], lineEdgeColor[2], lineEdgeColor[3], 255)
					love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
					love.graphics.setColor(lineCoreColor[1], lineCoreColor[2], lineCoreColor[3], 255)
					love.graphics.setLineWidth(baseWidth * .5)
					love.graphics.line(lastPosition.x, lastPosition.y, thisPosition.x, thisPosition.y)
				end
			end
		end

		-- main line
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

		-- time bar
		love.graphics.push()
		love.graphics.translate((w - TIME_BAR_WIDTH) / 2, h - 16)
		love.graphics.setColor(100, 110, 120, 255 * (1 - gameOverBlendFactor))
		love.graphics.rectangle("fill", 0, 0, TIME_BAR_WIDTH, 6)
		love.graphics.setColor(110, 210, 60, 255 * (1 - gameOverBlendFactor))
		love.graphics.rectangle("fill", 0, 0, TIME_BAR_WIDTH * (1 - progressAmount()), 6)
		love.graphics.pop()

		if gameOver then
			if won then
				local shadowColor = { 0, 30, 50 }
				drawShadowedText("congratulations", w / 2, -160, headerFont, gameOverBlendFactor, shadowColor)
				drawShadowedText("you have succeeded " .. winStreakDescription(winStreak), w / 2, -90, bodyFont, gameOverBlendFactor, shadowColor)
				drawShadowedText("try once more?", w / 2, -30, bodyFont, gameOverBlendFactor, shadowColor)

				-- flower!
				love.graphics.setColor(255, 255, 255, 255)
				love.graphics.push()
				local endPosition = positionHistory[#positionHistory]
				love.graphics.translate(endPosition.x, endPosition.y)
				local flowerGrowthTime = math.max(0, math.min(1, (elapsedTime - gameOverTime) / 1.5))
				love.graphics.rotate(-0.4 * math.pow(1 - flowerGrowthTime, 4))
				for i = 1, #flowerPetalImages do
					local origin = flowerPetalImageOrigins[i]
					local offset = flowerPetalOffsets[i] or v(0, 0)
					local petalScale = bounceLerp(0, 1.1, 1, flowerGrowthTime, 0.1 + .05 * flowerPetalSequenceIndices[i], 0.15, 0.1)
					love.graphics.draw(flowerPetalImages[i], offset.x - 2, offset.y + 6, 0, scaleMultiplier * petalScale, scaleMultiplier * petalScale, origin.x, origin.y)
				end
				local coreImageOriginX, coreImageOriginY = flowerCoreImage:getWidth() / 2, flowerCoreImage:getHeight() / 2
				local coreScale = bounceLerp(0, 1.1, 1, flowerGrowthTime, 0, 0.3, 0.1)
				love.graphics.draw(flowerCoreImage, 0, 0, 0, scaleMultiplier * coreScale, scaleMultiplier * coreScale, coreImageOriginX, coreImageOriginY)
				love.graphics.pop()
			else
				drawShadowedText("alas", w / 2, 580, headerFont, gameOverBlendFactor)
				drawShadowedText("this time, you remain in the ground", w / 2, 640, bodyFont, gameOverBlendFactor)
				drawShadowedText("press left to retry this level, or right for a new one", w / 2, 700, footerFont, gameOverBlendFactor)
			end
		end
	else
		-- introductory text
		local titleText = "sprout"
		local bodyLines = { "you are the tiny, frail beginnings of a plant", "you have strength to begin with, but it will fade", "feed yourself, reach the surface, and thrive" }
		local footerText = "press left, right, or 2 to play"

		drawShadowedText(titleText, w / 2, 100, titleFont)

		love.graphics.setFont(bodyFont)
		for i = 1, #bodyLines do
			local line = bodyLines[i]
			drawShadowedText(line, w / 2, 200 + 60 * (i - 1))
		end

		drawShadowedText(footerText, w / 2, 400, footerFont)
	end

	love.graphics.setColor(255, 255, 255, 255)
	local budImageOriginX, budImageOriginY = budImage:getWidth() * .5, budImage:getHeight() * .2
	love.graphics.draw(budImage, positionHistory[1].x, positionHistory[1].y, 0, scaleMultiplier - .01 * gameOverBlendFactor, scaleMultiplier - .01 * gameOverBlendFactor, budImageOriginX, budImageOriginY)
	if gameOver and not won then
		love.graphics.setColor(255, 255, 255, 255 * gameOverBlendFactor)
		love.graphics.draw(budDeadImage, positionHistory[1].x, positionHistory[1].y, 0, scaleMultiplier, scaleMultiplier, budImageOriginX, budImageOriginY)
	end
end

function bounceLerp(startValue, midValue, endValue, time, startTime, midDuration, endDuration)
	if time < startTime then return startValue end
	if time > startTime + midDuration + endDuration then return endValue end
	if time < startTime + midDuration then
		return slerp(startValue, midValue, (time - startTime) / midDuration)
	else
		return slerp(midValue, endValue, (time - (startTime + midDuration)) / endDuration)
	end
end

function winStreakDescription(n)
	if n > 99 then return tostring(n) .. " times in a row" end -- this would be straightforward but I would be astonished if anyone played enough to get that far

	local numberWords = { "once", "twice", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
	local tenWords = { "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" }

	local base = nil
	if n < 20 then
		base = numberWords[n]
	else
		local ones = n % 10
		local tens = (n - ones) / 10
		base = tenWords[tens - 1] .. "-" .. numberWords[ones]
	end

	if n > 2 then base = base .. " times" end
	if n > 1 then base = base .. " in a row" end
	return base
end

function drawShadowedText(text, x, y, font, alphaMultiplier, shadowColor)
	alphaMultiplier = alphaMultiplier or 1
	shadowColor = shadowColor or { 0, 0, 0 }
	if font then
		love.graphics.setFont(font)
	else
		font = love.graphics.getFont()
	end
	local textHalfWidth = font:getWidth(text) / 2
	love.graphics.setColor(shadowColor[1], shadowColor[2], shadowColor[3], 180 * math.pow(alphaMultiplier, 2))
	love.graphics.print(text, x, y + 2, 0, 1, 1, textHalfWidth)
	love.graphics.setColor(255, 255, 255, 255 * alphaMultiplier)
	love.graphics.print(text, x, y, 0, 1, 1, textHalfWidth)
end

function love.update(dt)
	elapsedTime = elapsedTime + dt

	local finalMovementAmount = 0
	if not playing and won then
		finalMovementAmount = (elapsedTime - gameOverTime) / GAME_OVER_GROWTH_TIME
	end
	if (playing or (gameOver and won)) and finalMovementAmount < 1 then
		local position = positionHistory[#positionHistory]
		local speed = SPEED * (1 - finalMovementAmount)

		direction = vNorm(vAdd(direction, vMul(vRight(direction), (isTurningLeft and 1 or -1) * (TURN_AMOUNT * speed) * dt)))
		position = vAdd(position, vMul(direction, speed * dt))
		addNewPosition(position)

		if playing then
			local allTargetsConsumed = true
			for i = 1, TARGET_COUNT do
				local target = targets[i]
				if not target.consumed and vDist(position, target.position) < TARGET_CONSUMPTION_DISTANCE then
					target.consumed = true
					currentTimeLimit = currentTimeLimit + timeBonusPerTarget
				end
				allTargetsConsumed = allTargetsConsumed and target.consumed
			end

			if allTargetsConsumed == true and position.y < GROUND_Y then
				endGame(true)
			elseif progressAmount() > 1 or position.x < -OFF_SCREEN_EDGE_THRESHOLD or position.x > love.window.getWidth() + OFF_SCREEN_EDGE_THRESHOLD or position.y > love.window.getHeight() + OFF_SCREEN_EDGE_THRESHOLD then
				endGame(false)
			end
		else
			if direction.y > -.5 then isTurningLeft = not isTurningLeft end
		end
	end
end

function progressAmount()
	return (elapsedTime - playStartedTime) / currentTimeLimit
end

function reset(keepCurrentTargets)
	playing = false
	gameOver = false
	elapsedTime = 0
	isTurningLeft = (math.random() > 0.5) and true or false

	positionHistory = {}
	branchHistory = {}
	local w, h = love.window.getDimensions()
	local startingPosition = v(w * .5, h * .85)
	addNewPosition(startingPosition)
	direction = v(0,-1)

	if not keepCurrentTargets then
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
				local newPosition = originalPosition
				if closestOtherDistance < TARGET_MINIMUM_TARGET_DISTANCE then
					local awayMovementAmount = vNorm(vSub(originalPosition, closestOtherTarget.position), TARGET_MINIMUM_TARGET_DISTANCE - closestOtherDistance)
					newPosition = vAdd(newPosition, awayMovementAmount)
				end
				newPosition.x = math.max(TARGET_MINIMUM_WALL_DISTANCE, math.min(w - TARGET_MINIMUM_WALL_DISTANCE, newPosition.x))
				newPosition.y = math.max(TARGET_MINIMUM_WALL_DISTANCE + GROUND_Y, math.min(startingPosition.y - TARGET_MINIMUM_WALL_DISTANCE, newPosition.y))
				targets[i].position = newPosition
			end
		end
	else
		for i = 1, TARGET_COUNT do
			targets[i].setupVisited = false
			targets[i].consumed = false
		end
	end

	-- we don’t really have to recalculate all of this if we’re keeping the current targets, but we don’t hang on to the original time limit
	local totalTargetDistance = 0
	local lastPathPosition = startingPosition
	local lastTargetIndex = nil
	canonicalPathPositionList = {startingPosition}
	for i = 1, TARGET_COUNT do
		local index = closestUnvisitedTargetIndex(lastPathPosition, lastTargetIndex)
		local targetPosition = targets[index].position
		totalTargetDistance = totalTargetDistance + vDist(lastPathPosition, targetPosition)
		lastPathPosition = targetPosition
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
	target.imageIndex = math.random(FOOD_IMAGE_COUNT)
	target.tilt = math.random() * 2 - 1
	target.pulsePhase = math.random()
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
	if won then
		winStreak = winStreak + 1
	else
		winStreak = 0
	end
end

function changeTurn(newTurn)
	if newTurn ~= isTurningLeft then
		local branchInfo = {}
		branchInfo.time = elapsedTime

		local branchSegmentLength = 1
		local branchLength = BRANCH_LENGTH_MIN + math.random() * (BRANCH_LENGTH_MAX - BRANCH_LENGTH_MIN)
		local branchDirection = direction
		local branchPath = { positionHistory[#positionHistory] }

		for i = 2, math.ceil(branchLength / branchSegmentLength) do
			branchDirection = vNorm(vAdd(branchDirection, vMul(vRight(branchDirection), (isTurningLeft and 1 or -1) * (BRANCH_CURVATURE * branchSegmentLength))))
			branchPath[i] = vAdd(branchPath[i - 1], vMul(branchDirection, branchSegmentLength))
		end
		branchInfo.path = branchPath

		branchHistory[#branchHistory + 1] = branchInfo


		isTurningLeft = newTurn
	end
end

function love.keypressed(key)
	if playing then
		if key == "2" then
			changeTurn(not isTurningLeft)
		elseif key == "left" then
			changeTurn(true)
		elseif key == "right" then
			changeTurn(false)
		end
	else
		if key == "2" or key == "left" or key == "right" then
			if not gameOver then
				start()
			elseif elapsedTime > gameOverTime + GAME_OVER_TRANSITION_DURATION * 1.2 then
				reset(key == "left")
			end
		end
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
