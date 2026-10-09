-- =====================================================
-- LIAR'S BAR - CLIENT
-- CC:Tweaked, wireless modem + monitor required
-- Запусти на компьютере каждого игрока
-- =====================================================

local CHANNEL = 1337
local SERVER_ID = nil  -- найдём автоматически

-- =====================================================
-- МОДЕМ И МОНИТОР
-- =====================================================

local modem = peripheral.find("modem")
if not modem then error("No modem! Attach a wireless modem.") end
rednet.open(peripheral.getName(modem))

local monName = nil
local mon = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        monName = name
        mon = peripheral.wrap(name)
        break
    end
end
if not mon then error("No monitor found!") end

-- =====================================================
-- МАСШТАБ
-- =====================================================

local W, H
local function pickScale()
    local scales = {5,4.5,4,3.5,3,2.5,2,1.5,1,0.5}
    for _, s in ipairs(scales) do
        mon.setTextScale(s)
        local w, h = mon.getSize()
        if w >= 26 and h >= 14 then
            W, H = w, h
            return
        end
    end
    mon.setTextScale(0.5)
    W, H = mon.getSize()
end
pickScale()

-- =====================================================
-- DRAW HELPERS
-- =====================================================

local function clearMon()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1,1)
end

local function writeAt(x, y, text, fg, bg)
    if x < 1 or y < 1 or y > H then return end
    mon.setCursorPos(x, y)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.write(text)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
end

local function centreX(text)
    return math.max(1, math.floor((W - #text) / 2) + 1)
end

local function drawButton(x, y, label, fg, bg)
    local text = " " .. label .. " "
    writeAt(x, y, text, fg, bg)
    return {x1=x, y1=y, x2=x+#text-1, y2=y, label=label}
end

local function hitBtn(b, tx, ty)
    return tx >= b.x1 and tx <= b.x2 and ty >= b.y1 and ty <= b.y2
end

local function drawBox(x, y, w, h, fg, bg)
    for row = y, y+h-1 do
        writeAt(x, row, string.rep(" ", w), fg, bg)
    end
end

-- =====================================================
-- КАРТЫ
-- =====================================================

local CARD_COLORS = {
    A      = colors.yellow,
    K      = colors.orange,
    Q      = colors.pink,
    J      = colors.cyan,
    Joker  = colors.lime,
}

local function cardColor(name)
    return CARD_COLORS[name] or colors.white
end

-- Нарисовать карту в позиции x,y (3x3 символа)
local function drawCard(x, y, name, selected)
    local bg = selected and colors.yellow or colors.white
    local fg = cardColor(name)
    local short = name == "Joker" and "Jo" or name
    drawBox(x, y, 4, 3, fg, bg)
    writeAt(x+1, y+1, short, fg, bg)
end

-- =====================================================
-- СОСТОЯНИЕ КЛИЕНТА
-- =====================================================

local playerNum = 0
local playerNick = ""
local hand = {}
local selectedCards = {}  -- индексы выбранных карт
local currentCard = ""
local pileCount = 0
local phase = "lobby"    -- lobby/wait/act/challenge_or_continue/result/gameover
local isDead = false
local statusMsg = ""
local statusColor = colors.white
local turnPlayer = ""
local claimedCount = 1   -- сколько заявляем

-- =====================================================
-- ОТРИСОВКА ЭКРАНА
-- =====================================================

local actBtns = {}

local function drawLobby(count, total)
    clearMon()
    writeAt(centreX("LIAR'S BAR"), 2, "LIAR'S BAR", colors.yellow)
    writeAt(centreX("Waiting for players..."), 4, "Waiting for players...", colors.lightGray)
    local s = count .. " / " .. total .. " connected"
    writeAt(centreX(s), 6, s, colors.lime)
    writeAt(centreX("You are: " .. playerNick), 8, "You are: " .. playerNick, colors.cyan)
end

local function drawDead()
    clearMon()
    drawBox(1, 1, W, H, colors.white, colors.black)
    writeAt(centreX("YOU ARE DEAD"), math.floor(H/2)-2, "YOU ARE DEAD", colors.red)
    writeAt(centreX("*** BANG ***"), math.floor(H/2),   "*** BANG ***", colors.red)
    writeAt(centreX("Watching the game..."), math.floor(H/2)+2, "Watching the game...", colors.lightGray)
end

local function drawWait()
    clearMon()
    writeAt(centreX("LIAR'S BAR"), 1, "LIAR'S BAR", colors.yellow)
    -- рука
    writeAt(1, 3, "Your hand:", colors.lightGray)
    for i, card in ipairs(hand) do
        local x = 1 + (i-1) * 5
        if x + 4 <= W then
            drawCard(x, 4, card, false)
        end
    end
    writeAt(1, 8, "Round card: " .. currentCard, colors.orange)
    writeAt(1, 9, "Pile: " .. pileCount .. " cards", colors.lightGray)
    writeAt(centreX("Waiting for: " .. turnPlayer), 11, "Waiting for: " .. turnPlayer, colors.lightGray)
    writeAt(centreX(statusMsg), H, statusMsg, statusColor)
end

local function drawAct()
    clearMon()
    actBtns = {}
    writeAt(centreX("YOUR TURN"), 1, "YOUR TURN", colors.lime)
    writeAt(1, 2, "Round card: " .. currentCard, colors.orange)
    writeAt(1, 3, "Pile: " .. pileCount .. " cards", colors.lightGray)

    -- Карты в руке
    writeAt(1, 4, "Your hand (tap to select):", colors.white)
    for i, card in ipairs(hand) do
        local x = 1 + (i-1) * 5
        if x + 4 <= W then
            local sel = selectedCards[i] or false
            drawCard(x, 5, card, sel)
            -- кнопка-зона для каждой карты
            table.insert(actBtns, {x1=x, y1=5, x2=x+3, y2=7, type="card", idx=i})
        end
    end

    -- Счётчик заявки
    writeAt(1, 9, "Claim count:", colors.white)
    local minusBtn = drawButton(14, 9, "-", colors.black, colors.red)
    minusBtn.type = "minus"
    writeAt(18, 9, tostring(claimedCount), colors.yellow)
    local plusBtn  = drawButton(20, 9, "+", colors.black, colors.lime)
    plusBtn.type = "plus"
    table.insert(actBtns, minusBtn)
    table.insert(actBtns, plusBtn)

    -- Сколько выбрано
    local selCount = 0
    for _, v in pairs(selectedCards) do if v then selCount = selCount + 1 end end
    writeAt(1, 10, "Selected: " .. selCount .. " card(s)", colors.lightGray)

    -- Кнопка PLAY
    local playCol = selCount > 0 and colors.lime or colors.gray
    local playBtn = drawButton(centreX("[ PLAY ]"), 12, "PLAY", colors.black, playCol)
    playBtn.type = "play"
    table.insert(actBtns, playBtn)

    writeAt(centreX(statusMsg), H, statusMsg, statusColor)
end

local function drawChallengeOrContinue()
    clearMon()
    actBtns = {}
    writeAt(centreX("LIAR'S BAR"), 1, "LIAR'S BAR", colors.yellow)
    writeAt(1, 3, "Round card: " .. currentCard, colors.orange)
    writeAt(1, 4, "Pile: " .. pileCount .. " cards", colors.lightGray)

    local msg = "Believe or Doubt?"
    writeAt(centreX(msg), 6, msg, colors.white)

    local continueBtn = drawButton(centreX("[ BELIEVE ]"), 8, "BELIEVE", colors.black, colors.lime)
    continueBtn.type = "continue"
    local doubtBtn   = drawButton(centreX("[ DOUBT! ]"),  10, "DOUBT!", colors.black, colors.red)
    doubtBtn.type = "doubt"
    table.insert(actBtns, continueBtn)
    table.insert(actBtns, doubtBtn)

    writeAt(centreX(statusMsg), H, statusMsg, statusColor)
end

local function drawRevolver(player, result)
    clearMon()
    writeAt(centreX("*** REVOLVER ***"), 2, "*** REVOLVER ***", colors.red)
    writeAt(centreX(player .. " pulls trigger..."), 4, player .. " pulls trigger...", colors.orange)
    if result == "bang" then
        writeAt(centreX("*** BANG! ***"), 6, "*** BANG! ***", colors.red)
        writeAt(centreX(player .. " is DEAD!"), 8, player .. " is DEAD!", colors.gray)
    elseif result == "click" then
        writeAt(centreX("...click."), 6, "...click.", colors.lightGray)
        writeAt(centreX(player .. " survives!"), 8, player .. " survives!", colors.lime)
    end
    writeAt(centreX(statusMsg), H, statusMsg, statusColor)
end

local function drawGameOver(winner)
    clearMon()
    writeAt(centreX("GAME OVER"), 3, "GAME OVER", colors.red)
    writeAt(centreX("Winner: " .. winner), 5, "Winner: " .. winner, colors.yellow)
    writeAt(centreX("Tap to restart"), H, "Tap to restart", colors.lightGray)
end

local function drawResult(msg, col)
    clearMon()
    writeAt(centreX("LIAR'S BAR"), 1, "LIAR'S BAR", colors.yellow)
    -- рука
    writeAt(1, 3, "Your hand:", colors.lightGray)
    for i, card in ipairs(hand) do
        local x = 1 + (i-1) * 5
        if x + 4 <= W then drawCard(x, 4, card, false) end
    end
    local lines = {}
    -- split msg by \n
    local s = msg
    for line in (s.."\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    for i, line in ipairs(lines) do
        writeAt(centreX(line), 8+i, line, col)
    end
    writeAt(centreX(statusMsg), H, statusMsg, statusColor)
end

-- =====================================================
-- СЕТЕВЫЕ СООБЩЕНИЯ → СЕРВЕР
-- =====================================================

local function sendServer(msg)
    if SERVER_ID then
        rednet.send(SERVER_ID, msg, "liarsbar")
    end
end

-- =====================================================
-- ГЛАВНЫЙ ЦИКЛ
-- =====================================================

-- Ввод ника
clearMon()
writeAt(centreX("LIAR'S BAR"), 2, "LIAR'S BAR", colors.yellow)
writeAt(centreX("Enter your name:"), 4, "Enter your name:", colors.white)
writeAt(centreX("(type below, press Enter)"), 5, "(type below, press Enter)", colors.lightGray)
print("Enter your name:")
repeat
    playerNick = read()
    playerNick = playerNick:match("^%s*(.-)%s*$")  -- trim spaces
until #playerNick >= 1 and #playerNick <= 12
clearMon()
writeAt(centreX("Hi, " .. playerNick .. "!"), 4, "Hi, " .. playerNick .. "!", colors.lime)
sleep(0.5)

-- Найти сервер — повторные попытки
print("Looking for server...")
local sid, smsg = nil, nil
for attempt = 1, 10 do
    print("Attempt " .. attempt .. "/10...")
    clearMon()
    writeAt(centreX("LIAR'S BAR"), 2, "LIAR'S BAR", colors.yellow)
    writeAt(centreX("Connecting to server..."), 4, "Connecting to server...", colors.lightGray)
    writeAt(centreX("Attempt " .. attempt .. "/10"), 6, "Attempt " .. attempt .. "/10", colors.white)
    rednet.broadcast({type="join", nick=playerNick}, "liarsbar")
    local deadline = os.clock() + 3
    while os.clock() < deadline do
        local id, msg = rednet.receive("liarsbar", 3)
        if id and type(msg) == "table" and msg.type == "joined" and msg.playerNum then
            sid = id
            smsg = msg
            break
        end
    end
    if sid then break end
    sleep(0.5)
end
if not sid or not smsg then
    clearMon()
    writeAt(centreX("CONNECTION FAILED"), 3, "CONNECTION FAILED", colors.red)
    writeAt(centreX("Start server first!"), 5, "Start server first!", colors.orange)
    writeAt(centreX("Then restart client."), 7, "Then restart client.", colors.lightGray)
    error("Could not find server after 10 attempts!")
end

SERVER_ID = sid
playerNum = smsg.playerNum
if smsg.nick then playerNick = smsg.nick end
print("Connected! You are " .. playerNick)
statusMsg = "Connected as " .. playerNick
statusColor = colors.lime
drawLobby(1, smsg.total)

-- Основной цикл событий
while true do
    -- Проверяем сеть и монитор одновременно через os.pullEvent
    local ev = {os.pullEvent()}
    local etype = ev[1]

    if etype == "rednet_message" then
        local senderId, msg = ev[2], ev[3]
        if senderId == SERVER_ID and type(msg) == "table" then

            if msg.type == "lobby" then
                drawLobby(msg.count, msg.total)

            elseif msg.type == "start" then
                statusMsg = "Game started!"
                statusColor = colors.lime

            elseif msg.type == "round_start" then
                currentCard = msg.card
                hand = msg.hand
                pileCount = 0
                selectedCards = {}
                claimedCount = 1
                turnPlayer = msg.turnPlayer
                phase = "wait"
                statusMsg = "Round " .. msg.round .. " | Card: " .. currentCard
                statusColor = colors.orange
                drawWait()

            elseif msg.type == "your_turn" then
                turnPlayer = msg.player
                if phase ~= "act" and phase ~= "challenge_or_continue" then
                    statusMsg = msg.player .. "'s turn"
                    statusColor = colors.white
                    if phase == "wait" then drawWait() end
                end

            elseif msg.type == "act" then
                currentCard = msg.card
                pileCount = msg.pile_count
                phase = "act"
                selectedCards = {}
                claimedCount = 1
                statusMsg = "Your turn! Select cards to play."
                statusColor = colors.lime
                drawAct()

            elseif msg.type == "played" then
                pileCount = msg.pile_count
                statusMsg = msg.player .. " played " .. msg.claimed .. "x " .. msg.card
                statusColor = colors.white
                if phase == "wait" then drawWait() end

            elseif msg.type == "challenge_or_continue" then
                currentCard = msg.card
                pileCount = msg.pile_count
                phase = "challenge_or_continue"
                statusMsg = "Believe or Doubt?"
                statusColor = colors.yellow
                drawChallengeOrContinue()

            elseif msg.type == "challenge_prompt" then
                turnPlayer = msg.player
                if phase ~= "challenge_or_continue" then
                    statusMsg = msg.player .. " deciding..."
                    statusColor = colors.lightGray
                    if phase == "wait" then drawWait() end
                end

            elseif msg.type == "trigger" then
                phase = "wait"
                statusMsg = msg.player .. " pulls the trigger..."
                statusColor = colors.red
                drawRevolver(msg.player, "pending")

            elseif msg.type == "bang" then
                drawRevolver(msg.player, "bang")
                sleep(2)
                -- если умер этот игрок — показать экран смерти
                local myName = playerNick
                if msg.player == myName then
                    isDead = true
                    phase = "dead"
                    drawDead()
                else
                    -- чужая смерть — показать на экране ожидания
                    statusMsg = msg.player .. " is DEAD!"
                    statusColor = colors.red
                    if phase == "wait" then drawWait() end
                end

            elseif msg.type == "click" then
                drawRevolver(msg.player, "click")
                sleep(2)

            elseif msg.type == "reveal" then
                local s = msg.player .. " claimed " .. msg.claimed .. "x " .. msg.card ..
                    "\nActual: " .. msg.actual .. "/" .. msg.real .. " were " .. msg.card
                statusMsg = s
                statusColor = colors.orange
                drawResult(s, colors.orange)
                sleep(2)

            elseif msg.type == "caught" then
                local s = msg.liar .. " was LYING!\n" .. msg.doubter .. " caught them!"
                drawResult(s, colors.red)
                sleep(2)

            elseif msg.type == "honest" then
                local s = msg.liar .. " was HONEST!\n" .. msg.doubter .. " doubted wrongly!"
                drawResult(s, colors.orange)
                sleep(2)

            elseif msg.type == "continues" then
                statusMsg = msg.player .. " believes."
                statusColor = colors.lightGray

            elseif msg.type == "doubt" then
                statusMsg = msg.player .. " DOUBTS!"
                statusColor = colors.red

            elseif msg.type == "hand_update" then
                hand = msg.hand
                selectedCards = {}
                if phase == "wait" then drawWait() end

            elseif msg.type == "round_end" then
                statusMsg = msg.message
                statusColor = colors.lightGray
                phase = "wait"

            elseif msg.type == "gameover" then
                phase = "gameover"
                drawGameOver(msg.winner)
                os.pullEvent("monitor_touch")
                -- переподключиться
                rednet.broadcast({type="join"}, "liarsbar")
                sid, smsg = rednet.receive("liarsbar", 30)
                if sid and smsg and smsg.type == "joined" then
                    SERVER_ID = sid
                    playerNum = smsg.playerNum
                    drawLobby(1, smsg.total)
                    phase = "lobby"
                end
            end
        end

    elseif etype == "monitor_touch" and ev[2] == monName then
        local tx, ty = ev[3], ev[4]

        if phase == "act" then
            for _, btn in ipairs(actBtns) do
                if hitBtn(btn, tx, ty) then
                    if btn.type == "card" then
                        selectedCards[btn.idx] = not selectedCards[btn.idx]
                        drawAct()

                    elseif btn.type == "minus" then
                        if claimedCount > 1 then claimedCount = claimedCount - 1 end
                        drawAct()

                    elseif btn.type == "plus" then
                        if claimedCount < 8 then claimedCount = claimedCount + 1 end
                        drawAct()

                    elseif btn.type == "play" then
                        local indices = {}
                        for i, v in pairs(selectedCards) do
                            if v then table.insert(indices, i) end
                        end
                        if #indices > 0 then
                            sendServer({type="play", cards=indices, claimed=claimedCount})
                            phase = "wait"
                            statusMsg = "Waiting..."
                            statusColor = colors.lightGray
                            drawWait()
                        end
                    end
                end
            end

        elseif phase == "challenge_or_continue" then
            for _, btn in ipairs(actBtns) do
                if hitBtn(btn, tx, ty) then
                    if btn.type == "continue" then
                        sendServer({type="continue"})
                        phase = "wait"
                        statusMsg = "You believe."
                        statusColor = colors.lightGray
                        drawWait()
                    elseif btn.type == "doubt" then
                        sendServer({type="doubt"})
                        phase = "wait"
                        statusMsg = "You doubted!"
                        statusColor = colors.red
                        drawWait()
                    end
                end
            end
        end
    end
end
