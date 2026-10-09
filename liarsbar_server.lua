-- =====================================================
-- LIAR'S BAR - SERVER
-- CC:Tweaked, wireless modem required
-- Запусти на главном компьютере: lua liarsbar_server.lua
-- =====================================================

local CHANNEL = 1337

-- Открыть модем
local modem = peripheral.find("modem")
if not modem then error("No modem found! Attach a wireless modem.") end
rednet.open(peripheral.getName(modem))

-- =====================================================
-- КАРТЫ
-- =====================================================

local CARD_NAMES = {"A","K","Q","J"}
local JOKER = "Joker"

local function newDeck()
    local deck = {}
    -- 6 карт каждого вида + 2 джокера
    for _, name in ipairs(CARD_NAMES) do
        for i = 1, 6 do table.insert(deck, name) end
    end
    table.insert(deck, JOKER)
    table.insert(deck, JOKER)
    return deck
end

local function shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function dealCards(deck, n)
    local hand = {}
    for i = 1, n do
        if #deck > 0 then
            table.insert(hand, table.remove(deck, 1))
        end
    end
    return hand
end

-- =====================================================
-- СОСТОЯНИЕ ИГРЫ
-- =====================================================

local players = {}       -- {id=compId, name="P1", hand={}, lives=1, alive=true}
local numPlayers = 4
local currentRound = 0
local pile = {}          -- карты на столе (реальные)
local pileClaimed = {}   -- что игроки говорили
local currentCard = ""   -- текущая карта раунда
local turnIdx = 1        -- чья очередь
local phase = "lobby"    -- lobby / deal / turn / challenge / revolver / gameover

local function alivePlayers()
    local t = {}
    for _, p in ipairs(players) do
        if p.alive then table.insert(t, p) end
    end
    return t
end

local function broadcast(msg)
    for _, p in ipairs(players) do
        if p.alive then
            rednet.send(p.id, msg, "liarsbar")
        end
    end
end

local function sendTo(id, msg)
    rednet.send(id, msg, "liarsbar")
end

local function log(msg)
    print("[SERVER] " .. msg)
end

-- =====================================================
-- LOBBY
-- =====================================================

local function lobby()
    print("=== LIAR'S BAR SERVER ===")
    print("Waiting for " .. numPlayers .. " players to connect...")
    print("Each player: run liarsbar_client.lua on their computer")
    print("")

    players = {}
    while #players < numPlayers do
        local id, msg = rednet.receive("liarsbar", 60)
        if id and msg and msg.type == "join" then
            -- check not already joined
            local already = false
            for _, p in ipairs(players) do
                if p.id == id then already = true end
            end
            if not already then
                local pNum = #players + 1
                local nick = (msg.nick and #msg.nick > 0) and msg.nick or ("Player "..pNum)
                local p = {id=id, name=nick, hand={}, lives=1, alive=true, hasMoved=false}
                table.insert(players, p)
                sendTo(id, {type="joined", playerNum=pNum, total=numPlayers, nick=nick})
                log("Player " .. pNum .. " joined as '" .. nick .. "' (ID: " .. id .. ")")
                print("Players: " .. #players .. "/" .. numPlayers)
                -- notify all current players about count
                broadcast({type="lobby", count=#players, total=numPlayers})
            end
        end
    end
    log("All players joined! Starting game...")
    broadcast({type="start", total=numPlayers})
    sleep(1)
end

-- =====================================================
-- РАУНД
-- =====================================================

local ROUND_CARDS = {"A","K","Q","J"}

local function startRound()
    currentRound = currentRound + 1
    local alive = alivePlayers()
    if #alive <= 1 then return end

    -- выбрать карту раунда
    currentCard = ROUND_CARDS[((currentRound - 1) % 4) + 1]

    -- раздать карты
    local deck = newDeck()
    shuffle(deck)
    for _, p in ipairs(players) do
        if p.alive then
            p.hand = dealCards(deck, 5)
            p.hasMoved = false
        end
    end

    pile = {}
    pileClaimed = {}

    log("Round " .. currentRound .. " | Card: " .. currentCard)

    -- сообщить всем карту раунда и их руку
    for _, p in ipairs(players) do
        if p.alive then
            sendTo(p.id, {
                type = "round_start",
                round = currentRound,
                card = currentCard,
                hand = p.hand,
                turnPlayer = alive[turnIdx] and alive[turnIdx].name or "?"
            })
        end
    end
    sleep(0.5)
end

-- Найти игрока по id
local function findPlayer(id)
    for _, p in ipairs(players) do
        if p.id == id then return p end
    end
    return nil
end

-- Найти индекс в alive list
local function aliveIndex(p)
    local alive = alivePlayers()
    for i, ap in ipairs(alive) do
        if ap.id == p.id then return i end
    end
    return 1
end

-- Следующий живой игрок
local function nextTurn()
    local alive = alivePlayers()
    if #alive == 0 then return end
    turnIdx = (turnIdx % #alive) + 1
end

-- =====================================================
-- РУЛЕТКА
-- =====================================================

local function pullTrigger(p)
    log(p.name .. " pulls the trigger...")
    broadcast({type="trigger", player=p.name})
    sleep(1)
    local roll = math.random(6)
    log(p.name .. " rolled: " .. roll)
    if roll == 1 then
        -- BANG
        p.alive = false
        log(p.name .. " is DEAD!")
        broadcast({type="bang", player=p.name, roll=roll})
        sleep(2)
        return true
    else
        broadcast({type="click", player=p.name, roll=roll})
        sleep(2)
        return false
    end
end

-- =====================================================
-- ХОД ИГРЫ
-- =====================================================

local function gameLoop()
    while true do
        local alive = alivePlayers()
        if #alive <= 1 then
            local winner = alive[1] and alive[1].name or "Nobody"
            log("Game over! Winner: " .. winner)
            broadcast({type="gameover", winner=winner})
            break
        end

        startRound()
        alive = alivePlayers()
        if turnIdx > #alive then turnIdx = 1 end

        -- Каждый игрок по очереди кладёт карту
        local roundOver = false
        local playersThisTurn = 0
        local maxTurns = #alive

        while playersThisTurn < maxTurns and not roundOver do
            alive = alivePlayers()
            if turnIdx > #alive then turnIdx = 1 end
            local currentP = alive[turnIdx]

            -- Сообщить всем чья очередь
            broadcast({type="your_turn", player=currentP.name})
            sendTo(currentP.id, {type="act", card=currentCard, pile_count=#pile})

            -- Ждём действия
            local acted = false
            while not acted do
                local id, msg = rednet.receive("liarsbar", 60)
                if id and msg then
                    if msg.type == "play" and id == currentP.id then
                        -- Игрок кладёт карту(ы) и называет их
                        local played = msg.cards   -- {индексы в руке}
                        local claimed = msg.claimed -- сколько заявил

                        -- убрать карты из руки
                        local realCards = {}
                        table.sort(played, function(a,b) return a>b end)
                        for _, idx in ipairs(played) do
                            if currentP.hand[idx] then
                                table.insert(realCards, table.remove(currentP.hand, idx))
                            end
                        end

                        for _, c in ipairs(realCards) do
                            table.insert(pile, c)
                        end
                        table.insert(pileClaimed, {player=currentP.name, count=claimed, real=#realCards})

                        log(currentP.name .. " played " .. #realCards .. " card(s), claimed " .. claimed .. " x " .. currentCard)

                        -- отправить игроку обновлённую руку
                        sendTo(currentP.id, {type="hand_update", hand=currentP.hand})

                        broadcast({type="played",
                            player = currentP.name,
                            claimed = claimed,
                            card = currentCard,
                            pile_count = #pile
                        })

                        acted = true

                    elseif msg.type == "challenge" and id ~= currentP.id then
                        -- Кто-то усомнился во время хода (не должно быть — вызов только после хода)
                        -- игнорируем
                    end
                end
            end

            -- После хода: предложить следующему игроку усомниться или продолжить
            nextTurn()
            alive = alivePlayers()
            if turnIdx > #alive then turnIdx = 1 end
            local nextP = alive[turnIdx]

            broadcast({type="challenge_prompt", player=nextP.name, pile_count=#pile})
            sendTo(nextP.id, {type="challenge_or_continue", pile_count=#pile, card=currentCard})

            -- Ждём решения следующего игрока
            local decided = false
            while not decided do
                local id, msg = rednet.receive("liarsbar", 30)
                if id and msg then
                    if msg.type == "continue" and id == nextP.id then
                        log(nextP.name .. " believes.")
                        broadcast({type="continues", player=nextP.name})
                        decided = true
                        playersThisTurn = playersThisTurn + 1

                    elseif msg.type == "doubt" and id == nextP.id then
                        log(nextP.name .. " doubts!")
                        broadcast({type="doubt", player=nextP.name})
                        sleep(1)

                        -- Проверить последний ход
                        local last = pileClaimed[#pileClaimed]
                        local lastRealCards = {}
                        local pileSize = #pile
                        -- собрать последние реальные карты
                        local realCount = last.real
                        local correct = 0
                        for i = pileSize - realCount + 1, pileSize do
                            if pile[i] == currentCard or pile[i] == JOKER then
                                correct = correct + 1
                            end
                        end

                        broadcast({type="reveal",
                            player = last.player,
                            claimed = last.count,
                            actual = correct,
                            real = realCount,
                            card = currentCard
                        })
                        sleep(2)

                        local liar = (correct < last.count)
                        if liar then
                            log(last.player .. " was LYING!")
                            broadcast({type="caught", liar=last.player, doubter=nextP.name})
                            -- лжец нажимает курок
                            local liarP = findPlayer(nil)
                            for _, p in ipairs(players) do
                                if p.name == last.player then liarP = p end
                            end
                            sleep(1)
                            if liarP then pullTrigger(liarP) end
                        else
                            log(last.player .. " was HONEST! " .. nextP.name .. " doubted wrongly.")
                            broadcast({type="honest", liar=last.player, doubter=nextP.name})
                            -- усомнившийся нажимает курок
                            pullTrigger(nextP)
                        end

                        decided = true
                        roundOver = true
                    end
                end
            end
        end

        -- Если раунд кончился без вызова — все выжили, новый раунд
        if not roundOver then
            broadcast({type="round_end", message="No one doubted! New round."})
            sleep(2)
        end

        -- обновить turnIdx для следующего раунда
        alive = alivePlayers()
        if #alive > 0 then
            turnIdx = (turnIdx % #alive) + 1
        end
    end
end

-- =====================================================
-- MAIN
-- =====================================================

math.randomseed(os.time())
lobby()
gameLoop()
rednet.close()
