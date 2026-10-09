-- =====================================================
-- CHECKERS (Russian rules) for CC:Tweaked
-- 2 monitors, touch only, 2-player or vs AI
-- Russian rules: 8x8, mandatory capture, kings slide
-- =====================================================

local EMPTY=0
local WP=1  -- white pawn
local WK=2  -- white king (dama)
local BP=3  -- black pawn
local BK=4  -- black king (dama)

local function isWhite(p) return p==WP or p==WK end
local function isBlack(p) return p==BP or p==BK end
local function isEmpty(p) return p==EMPTY end
local function isKing(p)  return p==WK or p==BK end

local SYM_WP = string.char(7)   -- • bullet = белая шашка
local SYM_WK = string.char(4)   -- ♦ diamond = белая дамка
local SYM_BP = string.char(7)   -- • bullet = чёрная шашка
local SYM_BK = string.char(4)   -- ♦ diamond = чёрная дамка

local function pieceChar(p)
    if p==WP then return SYM_WP
    elseif p==WK then return SYM_WK
    elseif p==BP then return SYM_BP
    elseif p==BK then return SYM_BK
    end
    return " "
end

local function pieceFg(p)
    if isWhite(p) then return colors.white end
    if isBlack(p) then return colors.orange end
    return colors.white
end

-- =====================================================
-- BOARD
-- =====================================================

local function newBoard()
    local b={}
    for r=1,8 do b[r]={} for c=1,8 do b[r][c]=EMPTY end end
    -- White pieces on rows 1-3 (dark squares)
    for r=1,3 do
        for c=1,8 do
            if (r+c)%2==1 then b[r][c]=WP end
        end
    end
    -- Black pieces on rows 6-8 (dark squares)
    for r=6,8 do
        for c=1,8 do
            if (r+c)%2==1 then b[r][c]=BP end
        end
    end
    return b
end

local function copyBoard(b)
    local n={}
    for r=1,8 do n[r]={} for c=1,8 do n[r][c]=b[r][c] end end
    return n
end

local function inBounds(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end

-- =====================================================
-- MOVE GENERATION (Russian rules)
-- =====================================================

-- Get all capture sequences starting from (r,c) on board b
-- Returns list of {cells visited, pieces captured}
local function getCaptures(b,r,c,visited,capturedSet)
    local p=b[r][c]
    local white=isWhite(p)
    local king=isKing(p)
    local results={}

    local dirs={{-1,-1},{-1,1},{1,-1},{1,1}}

    for _,d in ipairs(dirs) do
        local dr,dc=d[1],d[2]
        if king then
            -- king slides: scan for enemy, then continue past
            local nr,nc=r+dr,c+dc
            while inBounds(nr,nc) and isEmpty(b[nr][nc]) do
                nr=nr+dr; nc=nc+dc
            end
            if inBounds(nr,nc) then
                local target=b[nr][nc]
                local isEnemy=(white and isBlack(target)) or (not white and isWhite(target))
                local capKey=nr..","..nc
                if isEnemy and not capturedSet[capKey] then
                    -- land on any empty square beyond
                    local lr,lc=nr+dr,nc+dc
                    while inBounds(lr,lc) and isEmpty(b[lr][lc]) do
                        -- make capture
                        local nb=copyBoard(b)
                        nb[r][c]=EMPTY
                        nb[nr][nc]=EMPTY
                        nb[lr][lc]=p
                        local newCap={}
                        for k,v in pairs(capturedSet) do newCap[k]=v end
                        newCap[capKey]=true
                        -- recurse
                        local sub=getCaptures(nb,lr,lc,{},newCap)
                        if #sub==0 then
                            table.insert(results,{fr=r,fc=c,tr=lr,tc=lc,cap={{nr,nc}},board=nb,capSet=newCap})
                        else
                            for _,s in ipairs(sub) do
                                local capList={{nr,nc}}
                                for _,cc in ipairs(s.cap) do table.insert(capList,cc) end
                                table.insert(results,{fr=r,fc=c,tr=s.tr,tc=s.tc,cap=capList,board=s.board,capSet=s.capSet})
                            end
                        end
                        lr=lr+dr; lc=lc+dc
                    end
                end
            end
        else
            -- pawn captures in all 4 diagonals
            local nr,nc=r+dr,c+dc
            local lr,lc=r+dr*2,c+dc*2
            if inBounds(nr,nc) and inBounds(lr,lc) then
                local target=b[nr][nc]
                local isEnemy=(white and isBlack(target)) or (not white and isWhite(target))
                local capKey=nr..","..nc
                if isEnemy and not capturedSet[capKey] and isEmpty(b[lr][lc]) then
                    local nb=copyBoard(b)
                    nb[r][c]=EMPTY
                    nb[nr][nc]=EMPTY
                    -- promotion check
                    local promRow=white and 8 or 1
                    nb[lr][lc]=(lr==promRow) and (white and WK or BK) or p
                    local newCap={}
                    for k,v in pairs(capturedSet) do newCap[k]=v end
                    newCap[capKey]=true
                    -- if promoted, no further captures
                    local sub={}
                    if lr~=promRow then
                        sub=getCaptures(nb,lr,lc,{},newCap)
                    end
                    if #sub==0 then
                        table.insert(results,{fr=r,fc=c,tr=lr,tc=lc,cap={{nr,nc}},board=nb,capSet=newCap})
                    else
                        for _,s in ipairs(sub) do
                            local capList={{nr,nc}}
                            for _,cc in ipairs(s.cap) do table.insert(capList,cc) end
                            table.insert(results,{fr=r,fc=c,tr=s.tr,tc=s.tc,cap=capList,board=s.board,capSet=s.capSet})
                        end
                    end
                end
            end
        end
    end
    return results
end

-- Get all simple (non-capture) moves
local function getSimpleMoves(b,r,c)
    local p=b[r][c]
    local white=isWhite(p)
    local king=isKing(p)
    local moves={}
    local dirs
    if king then
        dirs={{-1,-1},{-1,1},{1,-1},{1,1}}
    elseif white then
        dirs={{1,-1},{1,1}}   -- white moves up (increasing rank)
    else
        dirs={{-1,-1},{-1,1}} -- black moves down (decreasing rank)
    end
    for _,d in ipairs(dirs) do
        if king then
            local nr,nc=r+d[1],c+d[2]
            while inBounds(nr,nc) and isEmpty(b[nr][nc]) do
                table.insert(moves,{fr=r,fc=c,tr=nr,tc=nc,cap={}})
                nr=nr+d[1]; nc=nc+d[2]
            end
        else
            local nr,nc=r+d[1],c+d[2]
            if inBounds(nr,nc) and isEmpty(b[nr][nc]) then
                table.insert(moves,{fr=r,fc=c,tr=nr,tc=nc,cap={}})
            end
        end
    end
    return moves
end

-- Get all legal moves for a side (mandatory capture)
local function getAllMoves(b,white)
    local captures={}
    local simples={}
    for r=1,8 do for c=1,8 do
        local p=b[r][c]
        if (white and isWhite(p)) or (not white and isBlack(p)) then
            local caps=getCaptures(b,r,c,{},{})
            for _,m in ipairs(caps) do table.insert(captures,m) end
            if #caps==0 then
                local sims=getSimpleMoves(b,r,c)
                for _,m in ipairs(sims) do table.insert(simples,m) end
            end
        end
    end end
    -- без обязательного взятия: можно ходить и бить по желанию
    if #captures>0 then
        for _,m in ipairs(captures) do table.insert(simples,m) end
    end
    return simples,false
end

-- Get moves for specific piece (mandatory capture applies to whole board)
local function getPieceMoves(allMoves,r,c)
    local result={}
    for _,m in ipairs(allMoves) do
        if m.fr==r and m.fc==c then
            table.insert(result,m)
        end
    end
    return result
end

local function applyMove(b,m)
    -- m.board already has the result if it came from getCaptures
    if m.board then return m.board end
    local nb=copyBoard(b)
    local p=nb[m.fr][m.fc]
    nb[m.fr][m.fc]=EMPTY
    -- promotion
    local white=isWhite(p)
    local promRow=white and 8 or 1
    if m.tr==promRow and not isKing(p) then
        nb[m.tr][m.tc]=white and WK or BK
    else
        nb[m.tr][m.tc]=p
    end
    return nb
end

-- =====================================================
-- MONITOR SETUP
-- =====================================================

local function findMonitors()
    local monitors={}
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name)=="monitor" then
            table.insert(monitors,name)
        end
    end
    if #monitors<2 then error("Need at least 2 monitors! Found: "..#monitors) end
    if #monitors==2 then
        print("Found: "..monitors[1]..", "..monitors[2])
        sleep(1)
        return monitors[1],monitors[2]
    end
    print("Found "..#monitors.." monitors:")
    for i,name in ipairs(monitors) do print(i..") "..name) end
    local i1,i2
    repeat io.write("Monitor P1: "); i1=tonumber(read()) until i1 and monitors[i1]
    repeat io.write("Monitor P2 (not "..i1.."): "); i2=tonumber(read()) until i2 and monitors[i2] and i2~=i1
    return monitors[i1],monitors[i2]
end

local function pickScale(mon)
    local scales={5,4.5,4,3.5,3,2.5,2,1.5,1,0.5}
    local needW=20; local needH=13
    for _,s in ipairs(scales) do
        mon.setTextScale(s)
        local w,h=mon.getSize()
        if w>=needW and h>=needH then return s,w,h end
    end
    mon.setTextScale(0.5)
    local w,h=mon.getSize()
    return 0.5,w,h
end

local mon1Name,mon2Name=findMonitors()
local mon1=peripheral.wrap(mon1Name)
local mon2=peripheral.wrap(mon2Name)
local s1,W1,H1=pickScale(mon1)
local s2,W2,H2=pickScale(mon2)
print("Mon1: "..W1.."x"..H1.." Mon2: "..W2.."x"..H2)
sleep(1)

-- =====================================================
-- DRAW HELPERS
-- =====================================================

local function clearMon(mon)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear(); mon.setCursorPos(1,1)
end

local function writeAt(mon,x,y,text,fg,bg)
    if x<1 or y<1 then return end
    mon.setCursorPos(x,y)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.write(text)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
end

local function centreX(W,text)
    return math.max(1,math.floor((W-#text)/2)+1)
end

local function drawButton(mon,x,y,label,fg,bg)
    local t=" "..label.." "
    writeAt(mon,x,y,t,fg,bg)
    return {x1=x,y1=y,x2=x+#t-1,y2=y}
end

local function hitBtn(b,tx,ty)
    return tx>=b.x1 and tx<=b.x2 and ty>=b.y1 and ty<=b.y2
end

-- =====================================================
-- BOARD DRAWING
-- =====================================================

local LIGHT_BG=colors.white
local DARK_BG =colors.brown
local SEL_BG  =colors.yellow
local HINT_BG =colors.lime
local LAST_BG =colors.cyan
local CAP_BG  =colors.red

local function boardOrigin(W,H)
    local bw=1+8*2
    local bh=1+8
    local ox=math.max(1,math.floor((W-bw)/2)+1)
    local oy=math.max(2,math.floor((H-bh)/2)+1)
    return ox,oy
end

local function touchToCell(tx,ty,ox,oy,flipped)
    local sr=ty-oy
    local sc=math.ceil((tx-ox)/2)
    if sr<1 or sr>8 or sc<1 or sc>8 then return nil,nil end
    local rank,file
    if flipped then
        rank=sr; file=9-sc
    else
        rank=9-sr; file=sc
    end
    return rank,file
end

local function drawBoard(mon,W,H,board,flipped,selected,hintMoves,lastMove,capturePath)
    local ox,oy=boardOrigin(W,H)
    local cols={"a","b","c","d","e","f","g","h"}

    -- build hint set (destination squares)
    local hintSet={}
    if hintMoves then
        for _,m in ipairs(hintMoves) do
            if not hintSet[m.tr] then hintSet[m.tr]={} end
            hintSet[m.tr][m.tc]=true
        end
    end
    -- build capture set
    local capSet={}
    if capturePath then
        for _,c in ipairs(capturePath) do
            if not capSet[c[1]] then capSet[c[1]]={} end
            capSet[c[1]][c[2]]=true
        end
    end

    -- col labels
    for sc=1,8 do
        local file=flipped and (9-sc) or sc
        writeAt(mon,ox+1+(sc-1)*2,oy,cols[file],colors.lightGray,colors.black)
        writeAt(mon,ox+2+(sc-1)*2,oy," ",colors.lightGray,colors.black)
    end

    for sr=1,8 do
        local rank=flipped and sr or (9-sr)
        writeAt(mon,ox,oy+sr,tostring(rank),colors.lightGray,colors.black)
        for sc=1,8 do
            local file=flipped and (9-sc) or sc
            local p=board[rank][file]
            local isDark=(rank+file)%2==1
            local bg=isDark and DARK_BG or LIGHT_BG
            local fg=pieceFg(p)
            local sym=pieceChar(p)

            if selected and selected[1]==rank and selected[2]==file then
                bg=SEL_BG
            elseif hintSet[rank] and hintSet[rank][file] then
                bg=HINT_BG
            elseif capSet[rank] and capSet[rank][file] then
                bg=CAP_BG
            elseif lastMove and (
                (lastMove.fr==rank and lastMove.fc==file) or
                (lastMove.tr==rank and lastMove.tc==file)) then
                bg=LAST_BG
            end

            local cx=ox+1+(sc-1)*2
            writeAt(mon,cx,oy+sr,sym,fg,bg)
            writeAt(mon,cx+1,oy+sr," ",fg,bg)
        end
    end
end

-- =====================================================
-- MODE SELECT
-- =====================================================

local function modeSelect()
    clearMon(mon1); clearMon(mon2)
    local function draw(mon,W,H)
        writeAt(mon,centreX(W,"CHECKERS"),2,"CHECKERS",colors.yellow)
        writeAt(mon,centreX(W,"Russian rules"),3,"Russian rules",colors.lightGray)
        local mid=math.floor(H/2)
        local bAI=drawButton(mon,centreX(W,"[ vs AI ]"),    mid-1,"vs AI",    colors.black,colors.lime)
        local b2P=drawButton(mon,centreX(W,"[ 2 Players ]"),mid+1,"2 Players",colors.black,colors.cyan)
        return bAI,b2P
    end
    local b1ai,b12p=draw(mon1,W1,H1)
    local b2ai,b22p=draw(mon2,W2,H2)
    while true do
        local ev={os.pullEvent("monitor_touch")}
        local mname,tx,ty=ev[2],ev[3],ev[4]
        local bai,b2p
        if mname==mon1Name then bai=b1ai; b2p=b12p
        elseif mname==mon2Name then bai=b2ai; b2p=b22p end
        if bai then
            if hitBtn(bai,tx,ty) then return "ai"
            elseif hitBtn(b2p,tx,ty) then return "2p" end
        end
    end
end

-- =====================================================
-- AI (minimax)
-- =====================================================

local function countPieces(b,white)
    local pawns,kings=0,0
    for r=1,8 do for c=1,8 do
        local p=b[r][c]
        if (white and isWhite(p)) or (not white and isBlack(p)) then
            if isKing(p) then kings=kings+1 else pawns=pawns+1 end
        end
    end end
    return pawns,kings
end

local function evaluate(b)
    local wp,wk=countPieces(b,true)
    local bp,bk=countPieces(b,false)
    return (wp*100+wk*300)-(bp*100+bk*300)
end

local aiNodes=0

local function aiMinimax(b,depth,alpha,beta,white)
    aiNodes=aiNodes+1
    if aiNodes%200==0 then sleep(0) end
    local moves,_=getAllMoves(b,white)
    if depth==0 or #moves==0 then return evaluate(b),nil end
    local best=white and -math.huge or math.huge
    local bestMove=nil
    for _,m in ipairs(moves) do
        local nb=applyMove(b,m)
        local val,_=aiMinimax(nb,depth-1,alpha,beta,not white)
        if white then
            if val>best then best=val; bestMove=m end
            alpha=math.max(alpha,val)
        else
            if val<best then best=val; bestMove=m end
            beta=math.min(beta,val)
        end
        if beta<=alpha then break end
    end
    return best,bestMove
end

local AI_DEPTH=6

-- =====================================================
-- GAME
-- =====================================================

local function game(mode)
    local board=newBoard()
    local whiteToMove=true
    local selected=nil
    local selectedMoves={}
    local lastMove=nil
    local allMoves,mustCapture=getAllMoves(board,true)

    local function countAll(white)
        local p,k=countPieces(board,white)
        return p+k
    end

    local function redraw(aiThinking)
        local status
        if aiThinking then status="AI thinking..."
        elseif mustCapture then status=(whiteToMove and "White" or "Black").." must capture!"
        else status=(whiteToMove and "White" or "Black").."'s turn" end

        -- capture path highlight for selected
        local capPath=nil
        -- (no mid-path highlight needed for simple version)

        clearMon(mon1)
        drawBoard(mon1,W1,H1,board,false,
            whiteToMove and selected or nil,
            whiteToMove and selectedMoves or {},
            lastMove,nil)
        if whiteToMove and not aiThinking then
            writeAt(mon1,centreX(W1,"YOUR TURN"),1,"YOUR TURN",colors.lime)
        else
            writeAt(mon1,centreX(W1,"Waiting..."),1,"Waiting...",colors.lightGray)
        end
        writeAt(mon1,centreX(W1,status),H1,status,mustCapture and colors.orange or colors.yellow)

        clearMon(mon2)
        drawBoard(mon2,W2,H2,board,true,
            not whiteToMove and selected or nil,
            not whiteToMove and selectedMoves or {},
            lastMove,nil)
        if not whiteToMove and not aiThinking then
            writeAt(mon2,centreX(W2,"YOUR TURN"),1,"YOUR TURN",colors.lime)
        elseif aiThinking then
            writeAt(mon2,centreX(W2,"AI thinking..."),1,"AI thinking...",colors.orange)
        else
            writeAt(mon2,centreX(W2,"Waiting..."),1,"Waiting...",colors.lightGray)
        end
        writeAt(mon2,centreX(W2,status),H2,status,mustCapture and colors.orange or colors.yellow)

        -- piece counts
        local wc=countAll(true); local bc=countAll(false)
        writeAt(mon1,1,H1-1,"W:"..wc.." B:"..bc,colors.lightGray)
        writeAt(mon2,1,H2-1,"W:"..wc.." B:"..bc,colors.lightGray)
    end

    redraw(false)

    while true do
        -- game over?
        if #allMoves==0 then
            local msg=whiteToMove and "Black wins!" or "White wins!"
            clearMon(mon1); clearMon(mon2)
            writeAt(mon1,centreX(W1,msg),math.floor(H1/2),msg,colors.yellow)
            writeAt(mon2,centreX(W2,msg),math.floor(H2/2),msg,colors.yellow)
            writeAt(mon1,centreX(W1,"Tap to restart"),math.floor(H1/2)+2,"Tap to restart",colors.lightGray)
            writeAt(mon2,centreX(W2,"Tap to restart"),math.floor(H2/2)+2,"Tap to restart",colors.lightGray)
            os.pullEvent("monitor_touch")
            return
        end

        -- AI turn
        if mode=="ai" and not whiteToMove then
            redraw(true)
            sleep(0)
            aiNodes=0
            local _,aiMove=aiMinimax(board,AI_DEPTH,-math.huge,math.huge,false)
            if aiMove then
                board=applyMove(board,aiMove)
                lastMove=aiMove; selected=nil; selectedMoves={}
                whiteToMove=true
                allMoves,mustCapture=getAllMoves(board,true)
                redraw(false)
            end
        else
            local ev={os.pullEvent("monitor_touch")}
            local mname,tx,ty=ev[2],ev[3],ev[4]
            local activeMonName=whiteToMove and mon1Name or mon2Name
            if mname==activeMonName then
                local W=whiteToMove and W1 or W2
                local H=whiteToMove and H1 or H2
                local flipped=not whiteToMove
                local ox,oy=boardOrigin(W,H)
                local rank,file=touchToCell(tx,ty,ox,oy,flipped)
                if rank then
                    -- check if tapped a hint square (make move)
                    local moved=false
                    if selected then
                        for _,m in ipairs(selectedMoves) do
                            if m.tr==rank and m.tc==file then
                                board=applyMove(board,m)
                                lastMove=m; selected=nil; selectedMoves={}
                                whiteToMove=not whiteToMove
                                allMoves,mustCapture=getAllMoves(board,whiteToMove)
                                moved=true
                                break
                            end
                        end
                    end
                    if not moved then
                        -- try to select piece
                        local p=board[rank][file]
                        if (whiteToMove and isWhite(p)) or (not whiteToMove and isBlack(p)) then
                            local pMoves=getPieceMoves(allMoves,rank,file)
                            if #pMoves>0 then
                                selected={rank,file}
                                selectedMoves=pMoves
                            else
                                selected=nil; selectedMoves={}
                            end
                        else
                            selected=nil; selectedMoves={}
                        end
                    end
                    redraw(false)
                end
            end
        end
    end
end

-- =====================================================
-- MAIN
-- =====================================================

while true do
    local mode=modeSelect()
    game(mode)
end
