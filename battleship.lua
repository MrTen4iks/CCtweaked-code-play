-- =====================================================
-- BATTLESHIP for CC:Tweaked
-- Supports monitors 1x1 up to 9x9
-- Controls: click cells on monitor, on-screen buttons
--           Keyboard: arrows=move, Enter=confirm, R=rotate
-- =====================================================

local BOARD_SIZE = 10

local SYM_EMPTY  = "."
local SYM_SHIP   = "#"
local SYM_HIT    = "X"
local SYM_MISS   = "o"
local SYM_CURSOR = "+"
local SYM_SUNK   = "*"

local SHIPS = {
    {4, 1},
    {3, 2},
    {2, 3},
    {1, 4},
}

-- =====================================================
-- MONITOR AUTO-DETECTION
-- =====================================================

local function findMonitors()
    local monitors = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            table.insert(monitors, name)
        end
    end
    if #monitors < 2 then
        error("Need at least 2 monitors! Found: " .. #monitors)
    end
    if #monitors == 2 then
        print("Found: " .. monitors[1] .. ", " .. monitors[2])
        print("Using them automatically...")
        sleep(1.5)
        return monitors[1], monitors[2]
    end
    print("Found " .. #monitors .. " monitors:")
    for i, name in ipairs(monitors) do print(i .. ") " .. name) end
    print("")
    local idx1, idx2
    repeat
        io.write("Monitor for Player 1 (number): ")
        idx1 = tonumber(read())
    until idx1 and monitors[idx1]
    repeat
        io.write("Monitor for Player 2 (not " .. idx1 .. "): ")
        idx2 = tonumber(read())
    until idx2 and monitors[idx2] and idx2 ~= idx1
    sleep(1)
    return monitors[idx1], monitors[idx2]
end

-- =====================================================
-- SCALE AUTO-FIT
-- =====================================================

local function pickScale(mon)
    local scales = {5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5}
    local needW  = 2 * (BOARD_SIZE + 3) + 5
    local needH  = BOARD_SIZE + 9   -- extra rows for buttons
    for _, s in ipairs(scales) do
        mon.setTextScale(s)
        local w, h = mon.getSize()
        if w >= needW and h >= needH then
            return s, w, h
        end
    end
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    return 0.5, w, h
end

-- =====================================================
-- INIT
-- =====================================================

local mon1Name, mon2Name = findMonitors()
local mon1 = peripheral.wrap(mon1Name)
local mon2 = peripheral.wrap(mon2Name)

local scale1, W1, H1 = pickScale(mon1)
local scale2, W2, H2 = pickScale(mon2)

print("Monitor 1: scale=" .. scale1 .. " size=" .. W1 .. "x" .. H1)
print("Monitor 2: scale=" .. scale2 .. " size=" .. W2 .. "x" .. H2)
sleep(1.5)

local players = {
    {
        mon = mon1, monName = mon1Name, W = W1, H = H1,
        name = "Player 1",
        board = {}, shots = {}, ships = {}, shipCount = 0,
    },
    {
        mon = mon2, monName = mon2Name, W = W2, H = H2,
        name = "Player 2",
        board = {}, shots = {}, ships = {}, shipCount = 0,
    },
}

-- =====================================================
-- HELPERS
-- =====================================================

local function newBoard()
    local b = {}
    for y = 1, BOARD_SIZE do
        b[y] = {}
        for x = 1, BOARD_SIZE do b[y][x] = 0 end
    end
    return b
end

local function clearMon(mon)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function writeAt(mon, x, y, text, fg, bg)
    if x < 1 or y < 1 then return end
    mon.setCursorPos(x, y)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.write(text)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
end

local function centreX(W, text)
    return math.max(1, math.floor((W - #text) / 2) + 1)
end

-- Draw a filled button, returns {x1,y1,x2,y2} for hit testing
local function drawButton(mon, x, y, label, fg, bg)
    local text = " " .. label .. " "
    writeAt(mon, x, y, text, fg, bg)
    return {x1=x, y1=y, x2=x+#text-1, y2=y, label=label}
end

local function hitButton(btn, tx, ty)
    return tx >= btn.x1 and tx <= btn.x2 and ty >= btn.y1 and ty <= btn.y2
end

-- =====================================================
-- DRAWING
-- =====================================================

local function drawGrid(mon, ox, oy)
    for x = 1, BOARD_SIZE do
        writeAt(mon, ox + x, oy, string.char(64 + x), colors.lightGray)
    end
    for y = 1, BOARD_SIZE do
        local label = tostring(y)
        if #label == 1 then label = " " .. label end
        writeAt(mon, ox - 1, oy + y, label, colors.lightGray)
    end
end

local function cellColor(cell, isOwn)
    if cell == 0 then return colors.white,     colors.black end
    if cell == 1 then
        if isOwn then return colors.lime, colors.gray end
        return colors.white, colors.black
    end
    if cell == 2 then return colors.red,       colors.black end
    if cell == 3 then return colors.lightBlue, colors.black end
    if cell == 4 then return colors.orange,    colors.black end
    return colors.white, colors.black
end

local function cellSymbol(cell, isOwn)
    if cell == 0 then return SYM_EMPTY end
    if cell == 1 then return isOwn and SYM_SHIP or SYM_EMPTY end
    if cell == 2 then return SYM_HIT  end
    if cell == 3 then return SYM_MISS end
    if cell == 4 then return SYM_SUNK end
    return SYM_EMPTY
end

local function drawBoard(mon, board, ox, oy, isOwn, curX, curY)
    for y = 1, BOARD_SIZE do
        for x = 1, BOARD_SIZE do
            local cell = board[y][x]
            local sym  = cellSymbol(cell, isOwn)
            local fg, bg = cellColor(cell, isOwn)
            if curX and curY and x == curX and y == curY then
                sym = SYM_CURSOR
                fg  = colors.yellow
                bg  = colors.black
            end
            writeAt(mon, ox + x, oy + y, sym, fg, bg)
        end
    end
end

-- =====================================================
-- LAYOUT HELPERS
-- =====================================================

-- Returns layout for game screen (two boards side by side)
local function gameLayout(p)
    local divX = math.floor(p.W / 2)
    local oy   = 3
    local ox1  = divX - BOARD_SIZE - 2
    local ox2  = divX + 2
    return divX, oy, ox1, ox2
end

-- Returns layout for placement screen (one board centred)
local function placeLayout(p)
    local boardW = BOARD_SIZE + 2
    local ox     = math.floor((p.W - boardW) / 2)
    local oy     = 3
    return ox, oy
end

-- Convert touch on ENEMY board to cell coords
local function touchToEnemyCell(p, tx, ty)
    local _, oy, _, ox2 = gameLayout(p)
    local bx = tx - ox2
    local by = ty - oy
    if bx >= 1 and bx <= BOARD_SIZE and by >= 1 and by <= BOARD_SIZE then
        return bx, by
    end
    return nil, nil
end

-- Convert touch on placement board to cell coords
local function touchToPlaceCell(p, tx, ty)
    local ox, oy = placeLayout(p)
    local bx = tx - ox
    local by = ty - oy
    if bx >= 1 and bx <= BOARD_SIZE and by >= 1 and by <= BOARD_SIZE then
        return bx, by
    end
    return nil, nil
end

-- =====================================================
-- GAME SCREEN
-- =====================================================

-- Draws game screen, returns buttons table {fire=btn, ...}
local function drawPlayerScreen(pIdx, curX, curY, phase)
    local p   = players[pIdx]
    local mon = p.mon
    local W, H = p.W, p.H

    clearMon(mon)

    local divX, oy, ox1, ox2 = gameLayout(p)

    -- Headers
    writeAt(mon, centreX(divX, "MY FLEET"),          1, "MY FLEET", colors.lime)
    writeAt(mon, divX + centreX(W - divX, "ENEMY"),  1, "ENEMY",    colors.red)
    writeAt(mon, centreX(W, p.name),                 2, p.name,     colors.yellow)

    -- Divider
    for row = 1, H do writeAt(mon, divX, row, "|", colors.gray) end

    -- Grids + boards
    drawGrid(mon, ox1, oy)
    drawGrid(mon, ox2, oy)
    drawBoard(mon, p.board, ox1, oy, true, nil, nil)

    local buttons = {}

    if phase == "shoot" then
        drawBoard(mon, p.shots, ox2, oy, false, curX, curY)

        -- FIRE button (right side, below enemy board)
        local btnY = oy + BOARD_SIZE + 2
        local fireX = ox2 + math.floor(BOARD_SIZE / 2) - 2
        buttons.fire = drawButton(mon, fireX, btnY, "[ FIRE ]", colors.black, colors.red)

        -- Hint
        writeAt(mon, 1, H, "Click enemy cell to aim, FIRE to shoot", colors.lightGray)
    else
        drawBoard(mon, p.shots, ox2, oy, false, nil, nil)
        writeAt(mon, centreX(W, "Waiting..."), math.floor(H/2) + 6, "Waiting...", colors.lightGray)
    end

    return buttons
end

-- =====================================================
-- PLACEMENT SCREEN
-- =====================================================

-- Draws placement screen, returns buttons {rotate=btn, place=btn}
local function drawPlaceScreen(pIdx, shipSize, horiz, tempCells, curX, curY)
    local p   = players[pIdx]
    local mon = p.mon
    local W, H = p.W, p.H

    clearMon(mon)

    local ox, oy = placeLayout(p)
    local boardW = BOARD_SIZE + 2

    -- Title
    local title = p.name .. " - place your ships"
    writeAt(mon, centreX(W, title), 1, title, colors.yellow)

    -- Ship checklist (right of board if room)
    local listX = ox + boardW + 3
    if listX + 14 <= W then
        writeAt(mon, listX, 3, "Ships:", colors.lightGray)
        local names = {"[ ] x1 (4sq)", "[ ] x2 (3sq)", "[ ] x3 (2sq)", "[ ] x4 (1sq)"}
        local marks = {"[X] x1 (4sq)", "[X] x2 (3sq)", "[X] x3 (2sq)", "[X] x4 (1sq)"}
        local maxC  = {1, 2, 3, 4}
        local placed = {0, 0, 0, 0}
        for _, ship in ipairs(p.ships) do
            if     ship.size == 4 then placed[1] = placed[1] + 1
            elseif ship.size == 3 then placed[2] = placed[2] + 1
            elseif ship.size == 2 then placed[3] = placed[3] + 1
            elseif ship.size == 1 then placed[4] = placed[4] + 1
            end
        end
        for i = 1, 4 do
            if placed[i] >= maxC[i] then
                writeAt(mon, listX, 3 + i, marks[i], colors.gray)
            else
                writeAt(mon, listX, 3 + i, names[i], colors.white)
            end
        end
    end

    -- Draw board + grid
    drawGrid(mon, ox, oy)
    drawBoard(mon, p.board, ox, oy, true, nil, nil)

    -- Preview ship
    if tempCells then
        for _, cell in ipairs(tempCells) do
            local fg = cell[3] and colors.lime or colors.red
            writeAt(mon, ox + cell[1], oy + cell[2], SYM_SHIP, fg)
        end
    end

    -- Buttons row at bottom
    local btnY   = oy + BOARD_SIZE + 2
    local dir    = horiz and "HORIZ" or "VERT"
    local valid  = tempCells and tempCells[1] and tempCells[1][3]

    -- ROTATE button
    local rotBtn = drawButton(mon, ox, btnY,
        "[ ROTATE: " .. dir .. " ]", colors.black, colors.orange)

    -- PLACE button (greyed if invalid)
    local placeCol = valid and colors.lime or colors.gray
    local placeBtn = drawButton(mon, ox + 18, btnY,
        "[ PLACE ]", colors.black, placeCol)

    -- Current ship info
    if shipSize > 0 then
        writeAt(mon, 1, H, "Ship: " .. shipSize .. " sq  |  Click cell to aim, PLACE to confirm", colors.lightGray)
    end

    return {rotate = rotBtn, place = placeBtn}
end

-- =====================================================
-- PLACEMENT LOGIC
-- =====================================================

local function getShipCells(x, y, size, horiz)
    local cells = {}
    for i = 0, size - 1 do
        if horiz then table.insert(cells, {x + i, y})
        else          table.insert(cells, {x, y + i}) end
    end
    return cells
end

local function canPlace(board, cells)
    for _, cell in ipairs(cells) do
        local cx, cy = cell[1], cell[2]
        if cx < 1 or cx > BOARD_SIZE or cy < 1 or cy > BOARD_SIZE then
            return false
        end
        for dy = -1, 1 do
            for dx = -1, 1 do
                local nx, ny = cx + dx, cy + dy
                if nx >= 1 and nx <= BOARD_SIZE and ny >= 1 and ny <= BOARD_SIZE then
                    if board[ny][nx] == 1 then return false end
                end
            end
        end
    end
    return true
end

local function placeShipOnBoard(p, cells)
    local entry = {cells = {}, sunk = false, hitCount = 0, size = #cells}
    for _, cell in ipairs(cells) do
        p.board[cell[2]][cell[1]] = 1
        table.insert(entry.cells, {cell[1], cell[2]})
        p.shipCount = p.shipCount + 1
    end
    table.insert(p.ships, entry)
end

local function placeShipsForPlayer(pIdx)
    local p       = players[pIdx]
    local monName = p.monName
    p.board     = newBoard()
    p.ships     = {}
    p.shipCount = 0

    local cx, cy = 1, 1
    local horiz  = true

    for _, shipDef in ipairs(SHIPS) do
        local shipSize, count = shipDef[1], shipDef[2]
        for _ = 1, count do
            local placed = false
            while not placed do
                local tempCells    = getShipCells(cx, cy, shipSize, horiz)
                local valid        = canPlace(p.board, tempCells)
                local displayCells = {}
                for _, tc in ipairs(tempCells) do
                    table.insert(displayCells, {tc[1], tc[2], valid})
                end

                local btns = drawPlaceScreen(pIdx, shipSize, horiz, displayCells, cx, cy)

                local ev    = {os.pullEvent()}
                local etype = ev[1]

                if etype == "key" then
                    local key = ev[2]
                    if     key == keys.up    and cy > 1          then cy = cy - 1
                    elseif key == keys.down  and cy < BOARD_SIZE then cy = cy + 1
                    elseif key == keys.left  and cx > 1          then cx = cx - 1
                    elseif key == keys.right and cx < BOARD_SIZE then cx = cx + 1
                    elseif key == keys.r then horiz = not horiz
                    elseif key == keys.enter and valid then
                        placeShipOnBoard(p, tempCells)
                        placed = true
                    end

                elseif etype == "monitor_touch" and ev[2] == monName then
                    local tx, ty = ev[3], ev[4]

                    if hitButton(btns.rotate, tx, ty) then
                        -- ROTATE button clicked
                        horiz = not horiz

                    elseif hitButton(btns.place, tx, ty) and valid then
                        -- PLACE button clicked
                        placeShipOnBoard(p, tempCells)
                        placed = true

                    else
                        -- Click on board cell = move cursor
                        local bx, by = touchToPlaceCell(p, tx, ty)
                        if bx and by then
                            cx, cy = bx, by
                        end
                    end
                end
            end
        end
    end

    -- Done screen
    drawPlaceScreen(pIdx, 0, horiz, nil, 0, 0)
    writeAt(p.mon, 1, p.H, "All ships placed! Press Enter or tap to continue.", colors.yellow)
    local done = false
    while not done do
        local ev = {os.pullEvent()}
        if ev[1] == "key" and ev[2] == keys.enter then
            done = true
        elseif ev[1] == "monitor_touch" and ev[2] == monName then
            done = true
        end
    end
end

-- =====================================================
-- SHOOTING
-- =====================================================

local function markSunk(enemy, ship)
    for _, c in ipairs(ship.cells) do
        enemy.board[c[2]][c[1]] = 4
    end
end

local function shoot(pIdx, tx, ty)
    local attacker = players[pIdx]
    local defender = players[pIdx == 1 and 2 or 1]

    if attacker.shots[ty][tx] ~= 0 then return "already" end

    local cell = defender.board[ty][tx]

    if cell == 0 then
        attacker.shots[ty][tx] = 3
        defender.board[ty][tx] = 3
        return "miss"
    elseif cell == 1 then
        attacker.shots[ty][tx] = 2
        defender.board[ty][tx] = 2
        defender.shipCount = defender.shipCount - 1

        for _, ship in ipairs(defender.ships) do
            for _, sc in ipairs(ship.cells) do
                if sc[1] == tx and sc[2] == ty then
                    ship.hitCount = ship.hitCount + 1
                    if ship.hitCount >= ship.size then
                        ship.sunk = true
                        markSunk(defender, ship)
                        for _, sc2 in ipairs(ship.cells) do
                            attacker.shots[sc2[2]][sc2[1]] = 4
                        end
                        return defender.shipCount <= 0 and "win" or "sunk"
                    end
                    break
                end
            end
        end
        return "hit"
    end
    return "miss"
end

local function takeTurn(pIdx)
    local p       = players[pIdx]
    local monName = p.monName
    local cx, cy  = 1, 1
    local result  = nil

    while not result do
        local btns = drawPlayerScreen(pIdx, cx, cy, "shoot")

        local ev    = {os.pullEvent()}
        local etype = ev[1]

        if etype == "key" then
            local key = ev[2]
            if     key == keys.up    and cy > 1          then cy = cy - 1
            elseif key == keys.down  and cy < BOARD_SIZE then cy = cy + 1
            elseif key == keys.left  and cx > 1          then cx = cx - 1
            elseif key == keys.right and cx < BOARD_SIZE then cx = cx + 1
            elseif key == keys.enter then
                local r = shoot(pIdx, cx, cy)
                if r ~= "already" then result = r end
            end

        elseif etype == "monitor_touch" and ev[2] == monName then
            local tx, ty = ev[3], ev[4]

            if hitButton(btns.fire, tx, ty) then
                -- FIRE button — shoot at current cursor
                local r = shoot(pIdx, cx, cy)
                if r ~= "already" then result = r end

            else
                -- Click on enemy board = move cursor
                local bx, by = touchToEnemyCell(p, tx, ty)
                if bx and by then
                    cx, cy = bx, by
                end
            end
        end
    end

    return result
end

-- =====================================================
-- WAIT / RESULT SCREENS
-- =====================================================

local function waitScreen(p, text)
    clearMon(p.mon)
    writeAt(p.mon, centreX(p.W, text), math.floor(p.H / 2), text, colors.yellow)
end

local function showResult(winnerIdx)
    local w     = players[winnerIdx]
    local loser = players[winnerIdx == 1 and 2 or 1]

    clearMon(w.mon)
    clearMon(loser.mon)

    local wy = math.floor(w.H / 2)
    writeAt(w.mon, centreX(w.W, "=== YOU WIN! ==="),           wy-2, "=== YOU WIN! ===",           colors.yellow)
    writeAt(w.mon, centreX(w.W, w.name .. " wins!"),           wy,   w.name .. " wins!",            colors.lime)
    writeAt(w.mon, centreX(w.W, "All enemy ships destroyed!"), wy+2, "All enemy ships destroyed!",  colors.white)
    writeAt(w.mon, centreX(w.W, "Press Enter to exit"),        wy+4, "Press Enter to exit",         colors.lightGray)

    local ly = math.floor(loser.H / 2)
    writeAt(loser.mon, centreX(loser.W, "=== GAME OVER ==="),        ly-2, "=== GAME OVER ===",        colors.red)
    writeAt(loser.mon, centreX(loser.W, w.name .. " wins!"),         ly,   w.name .. " wins!",          colors.orange)
    writeAt(loser.mon, centreX(loser.W, "All your ships destroyed!"),ly+2, "All your ships destroyed!", colors.white)
    writeAt(loser.mon, centreX(loser.W, "Press Enter to exit"),      ly+4, "Press Enter to exit",       colors.lightGray)

    os.pullEvent("key")
end

-- =====================================================
-- MAIN
-- =====================================================

local function main()
    players[1].shots = newBoard()
    players[2].shots = newBoard()

    -- Placement phase
    waitScreen(players[2], "Please wait - Player 1 is placing ships...")
    placeShipsForPlayer(1)

    waitScreen(players[1], "Please wait - Player 2 is placing ships...")
    placeShipsForPlayer(2)

    -- Game start
    drawPlayerScreen(1, nil, nil, "wait")
    drawPlayerScreen(2, nil, nil, "wait")
    writeAt(mon1, 1, H1, "Game start! Player 1 goes first.", colors.yellow)
    writeAt(mon2, 1, H2, "Game start! Player 1 goes first.", colors.yellow)
    sleep(2)

    local currentPlayer = 1
    local gameOver      = false
    local winner        = nil

    while not gameOver do
        local other = currentPlayer == 1 and 2 or 1
        local cp    = players[currentPlayer]
        local op    = players[other]

        waitScreen(op, "Please wait - " .. cp.name .. " is firing...")

        local result = takeTurn(currentPlayer)
        drawPlayerScreen(currentPlayer, nil, nil, "wait")

        if result == "win" then
            gameOver = true
            winner   = currentPlayer
        elseif result == "sunk" then
            writeAt(cp.mon, 1, cp.H, "Ship sunk! Fire again!", colors.orange)
            sleep(1.5)
        elseif result == "hit" then
            writeAt(cp.mon, 1, cp.H, "Hit! Fire again!", colors.red)
            sleep(1.5)
        else
            writeAt(cp.mon, 1, cp.H, "Miss! Next player's turn.", colors.lightBlue)
            sleep(1.5)
            currentPlayer = other
        end
    end

    showResult(winner)
end

main()
