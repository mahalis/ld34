require "vectors"

local elapsedTime
local playing
local gameOver
local won
local winStreak

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
local TARGET_CONSUMPTION_DISTANCE = 30

local GROUND_Y = 60

local TIME_BAR_WIDTH = 106

local backgroundImage
local budImage, budDeadImage
local foodImages, foodHoleImages
local FOOD_IMAGE_COUNT = 2

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

	local fontPath = "font/notperfect regular.ttf"
	titleFont = love.graphics.newFont(fontPath, 64)
	headerFont = love.graphics.newFont(fontPath, 40)
	bodyFont = love.graphics.newFont(fontPath, 32)
	footerFont = love.graphics.newFont(fontPath, 24)

	winStreak = 0

	reset()
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
			love.graphics.draw(foodImage, target.position.x, target.position.y, target.tilt * 0.2, scaleMultiplier, scaleMultiplier, foodImageOriginX, foodImageOriginY)
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
				drawShadowedText("congratulations", w / 2, -150, headerFont, gameOverBlendFactor, shadowColor)
				drawShadowedText("you have succeeded " .. winStreakDescription(winStreak), w / 2, -90, bodyFont, gameOverBlendFactor, shadowColor)
				drawShadowedText("try once more?", w / 2, -30, bodyFont, gameOverBlendFactor, shadowColor)
			else
				drawShadowedText("alas", w / 2, 580, headerFont, gameOverBlendFactor)
				drawShadowedText("this time, you remain in the ground", w / 2, 640, bodyFont, gameOverBlendFactor)
				drawShadowedText("try once more?", w / 2, 700, bodyFont, gameOverBlendFactor)
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
	local startingPosition = v(w * .5, h * .85)
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
	target.imageIndex = math.random(FOOD_IMAGE_COUNT)
	target.tilt = math.random() * 2 - 1
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
		if key == "2" or key == "left" or key == "right" and (gameOver == false or elapsedTime > gameOverTime + GAME_OVER_TRANSITION_DURATION * 1.2) then
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
