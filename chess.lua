-- =====================================================
-- CHESS for CC:Tweaked
-- 2 monitors, touch only, 2-player or vs AI
-- =====================================================

local EMPTY = 0
local WK=1; local WQ=2; local WR=3; local WB=4; local WN=5; local WP=6
local BK=7; local BQ=8; local BR=9; local BB=10; local BN=11; local BP=12

-- CP437 symbols for pieces:
-- 0x0F = ☼  (sun)   -> King
-- 0x04 = ♦  (diamond) -> Queen
-- 0x05 = ♣  (club)  -> Rook
-- 0x06 = ♠  (spade) -> Bishop
-- 0x0B = ♂  (male)  -> Knight
-- 0x09 = ○  (circle)-> Pawn
local SYM_K = string.char(0x0F)  -- ☼ King
local SYM_Q = string.char(0x04)  -- ♦ Queen
local SYM_R = string.char(0x05)  -- ♣ Rook
local SYM_B = string.char(0x06)  -- ♠ Bishop
local SYM_N = string.char(0x0B)  -- ♂ Knight
local SYM_P = "o"  -- o Pawn

local PIECE_CHAR = {
    [WK]=SYM_K, [WQ]=SYM_Q, [WR]=SYM_R, [WB]=SYM_B, [WN]=SYM_N, [WP]=SYM_P,
    [BK]=SYM_K, [BQ]=SYM_Q, [BR]=SYM_R, [BB]=SYM_B, [BN]=SYM_N, [BP]=SYM_P,
    [EMPTY]=" "
}

local function isWhite(p) return p>=1 and p<=6 end
local function isBlack(p) return p>=7 and p<=12 end
local function isEmpty(p) return p==EMPTY end
local function sameColor(a,b)
    if isEmpty(a) or isEmpty(b) then return false end
    return (isWhite(a) and isWhite(b)) or (isBlack(a) and isBlack(b))
end

-- =====================================================
-- BOARD
-- =====================================================

local function newBoard()
    local b={}
    for r=1,8 do b[r]={} for c=1,8 do b[r][c]=EMPTY end end
    b[1]={WR,WN,WB,WQ,WK,WB,WN,WR}
    b[2]={WP,WP,WP,WP,WP,WP,WP,WP}
    b[7]={BP,BP,BP,BP,BP,BP,BP,BP}
    b[8]={BR,BN,BB,BQ,BK,BB,BN,BR}
    return b
end

local function copyBoard(b)
    local n={}
    for r=1,8 do n[r]={} for c=1,8 do n[r][c]=b[r][c] end end
    return n
end

-- =====================================================
-- MOVE GENERATION
-- =====================================================

local function inBounds(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end

local function addSlide(b,r,c,dr,dc,white,moves)
    local nr,nc=r+dr,c+dc
    while inBounds(nr,nc) do
        local t=b[nr][nc]
        if isEmpty(t) then
            table.insert(moves,{r,c,nr,nc})
        elseif (white and isBlack(t)) or (not white and isWhite(t)) then
            table.insert(moves,{r,c,nr,nc}); break
        else break end
        nr=nr+dr; nc=nc+dc
    end
end

local function getRawMoves(b,r,c,ep,castling)
    local p=b[r][c]
    if p==EMPTY then return {} end
    local white=isWhite(p)
    local moves={}
    local pt=p; if pt>6 then pt=pt-6 end

    if pt==6 then -- pawn
        local dir=white and 1 or -1
        local startRow=white and 2 or 7
        local nr=r+dir
        if inBounds(nr,c) and isEmpty(b[nr][c]) then
            table.insert(moves,{r,c,nr,c})
            if r==startRow and inBounds(r+dir*2,c) and isEmpty(b[r+dir*2][c]) then
                table.insert(moves,{r,c,r+dir*2,c})
            end
        end
        for _,dc in ipairs({-1,1}) do
            local nc2=c+dc
            if inBounds(nr,nc2) then
                local t=b[nr][nc2]
                if (white and isBlack(t)) or (not white and isWhite(t)) then
                    table.insert(moves,{r,c,nr,nc2})
                end
                if ep and nr==ep[1] and nc2==ep[2] then
                    table.insert(moves,{r,c,nr,nc2,ep=true})
                end
            end
        end

    elseif pt==5 then -- knight
        for _,d in ipairs({{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}) do
            local nr,nc=r+d[1],c+d[2]
            if inBounds(nr,nc) and not sameColor(p,b[nr][nc]) then
                table.insert(moves,{r,c,nr,nc})
            end
        end

    elseif pt==4 then -- bishop
        for _,d in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do
            addSlide(b,r,c,d[1],d[2],white,moves)
        end

    elseif pt==3 then -- rook
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            addSlide(b,r,c,d[1],d[2],white,moves)
        end

    elseif pt==2 then -- queen
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}) do
            addSlide(b,r,c,d[1],d[2],white,moves)
        end

    elseif pt==1 then -- king
        for _,d in ipairs({{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}}) do
            local nr,nc=r+d[1],c+d[2]
            if inBounds(nr,nc) and not sameColor(p,b[nr][nc]) then
                table.insert(moves,{r,c,nr,nc})
            end
        end
        if castling then
            local row=white and 1 or 8
            if r==row and c==5 then
                local ks=white and castling.wk or castling.bk
                if ks and isEmpty(b[row][6]) and isEmpty(b[row][7]) then
                    table.insert(moves,{r,c,row,7,castle="k"})
                end
                local qs=white and castling.wq or castling.bq
                if qs and isEmpty(b[row][4]) and isEmpty(b[row][3]) and isEmpty(b[row][2]) then
                    table.insert(moves,{r,c,row,3,castle="q"})
                end
            end
        end
    end
    return moves
end

local function isSquareAttacked(b,r,c,byWhite)
    for sr=1,8 do for sc=1,8 do
        local p=b[sr][sc]
        if (byWhite and isWhite(p)) or (not byWhite and isBlack(p)) then
            local moves=getRawMoves(b,sr,sc,nil,nil)
            for _,m in ipairs(moves) do
                if m[3]==r and m[4]==c then return true end
            end
        end
    end end
    return false
end

local function findKing(b,white)
    local king=white and WK or BK
    for r=1,8 do for c=1,8 do
        if b[r][c]==king then return r,c end
    end end
    return nil,nil
end

local function applyMove(b,m,ep,castling)
    local nb=copyBoard(b)
    local p=nb[m[1]][m[2]]
    local nc_ep=nil
    local nc_cast={wk=castling.wk,wq=castling.wq,bk=castling.bk,bq=castling.bq}

    if m.ep then
        local dir=isWhite(p) and -1 or 1
        nb[m[3]+dir][m[4]]=EMPTY
    end

    nb[m[3]][m[4]]=p
    nb[m[1]][m[2]]=EMPTY

    if m.castle then
        local row=m[3]
        if m.castle=="k" then
            nb[row][6]=nb[row][8]; nb[row][8]=EMPTY
        else
            nb[row][4]=nb[row][1]; nb[row][1]=EMPTY
        end
    end

    local pt=p; if pt>6 then pt=pt-6 end
    if pt==6 and math.abs(m[3]-m[1])==2 then
        local dir=isWhite(p) and 1 or -1
        nc_ep={m[1]+dir,m[2]}
    end

    if p==WK then nc_cast.wk=false; nc_cast.wq=false end
    if p==BK then nc_cast.bk=false; nc_cast.bq=false end
    if p==WR then
        if m[1]==1 and m[2]==1 then nc_cast.wq=false end
        if m[1]==1 and m[2]==8 then nc_cast.wk=false end
    end
    if p==BR then
        if m[1]==8 and m[2]==1 then nc_cast.bq=false end
        if m[1]==8 and m[2]==8 then nc_cast.bk=false end
    end

    return nb,nc_ep,nc_cast
end

local function isInCheck(b,white)
    local kr,kc=findKing(b,white)
    if not kr then return false end
    return isSquareAttacked(b,kr,kc,not white)
end

local function getLegalMoves(b,white,ep,castling)
    local legal={}
    for r=1,8 do for c=1,8 do
        local p=b[r][c]
        if (white and isWhite(p)) or (not white and isBlack(p)) then
            local raw=getRawMoves(b,r,c,ep,castling)
            for _,m in ipairs(raw) do
                local ok=true
                if m.castle then
                    local row=m[3]
                    if isSquareAttacked(b,row,5,not white) then ok=false end
                    if ok and m.castle=="k" then
                        if isSquareAttacked(b,row,6,not white) then ok=false end
                        if isSquareAttacked(b,row,7,not white) then ok=false end
                    elseif ok then
                        if isSquareAttacked(b,row,4,not white) then ok=false end
                        if isSquareAttacked(b,row,3,not white) then ok=false end
                    end
                end
                if ok then
                    local nb,_,_=applyMove(b,m,ep,castling)
                    if not isInCheck(nb,white) then
                        table.insert(legal,m)
                    end
                end
            end
        end
    end end
    return legal
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
    -- need: 1(rank label) + 8*2(cells) + margins = ~20 wide, 1(col label)+8(rows)+4(ui) = 13 tall
    local needW=20
    local needH=13
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
local scale1,W1,H1=pickScale(mon1)
local scale2,W2,H2=pickScale(mon2)
print("Mon1: scale="..scale1.." "..W1.."x"..H1)
print("Mon2: scale="..scale2.." "..W2.."x"..H2)
sleep(1)

-- =====================================================
-- DRAW HELPERS
-- =====================================================

local function clearMon(mon)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1,1)
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
    local text=" "..label.." "
    writeAt(mon,x,y,text,fg,bg)
    return {x1=x,y1=y,x2=x+#text-1,y2=y}
end

local function hitBtn(btn,tx,ty)
    return tx>=btn.x1 and tx<=btn.x2 and ty>=btn.y1 and ty<=btn.y2
end

-- =====================================================
-- BOARD LAYOUT & DRAWING
-- =====================================================
-- Layout:
--   Row oy   = column labels (a-h or h-a)
--   Rows oy+1..oy+8 = board rows
--   Col ox   = rank label (1 char)
--   Cols ox+1..ox+16 = cells (2 chars each)

local function boardOrigin(W,H)
    local bw=1+8*2   -- 1 rank label + 8 cells * 2 chars
    local bh=1+8     -- 1 col label row + 8 rows
    local ox=math.max(1,math.floor((W-bw)/2)+1)
    local oy=math.max(2,math.floor((H-bh)/2)+1)
    return ox,oy
end

-- touchToCell: ox,oy are board origin, flipped=black's view
local function touchToCell(tx,ty,ox,oy,flipped)
    -- board rows: oy+1 to oy+8 (screen rows)
    -- board cols: ox+1 to ox+16 (cells are 2 wide each)
    local screenRow=ty-oy   -- 1..8
    local screenCol=math.ceil((tx-ox)/2)  -- 1..8  (ox+1,ox+2 -> col1; ox+3,ox+4 -> col2 etc)
    if screenRow<1 or screenRow>8 then return nil,nil end
    if screenCol<1 or screenCol>8 then return nil,nil end
    -- convert screen position to board (rank,file)
    local rank,file
    if flipped then
        rank=screenRow          -- screen row 1 = rank 1 (black's view: rank 1 at top)
        file=9-screenCol        -- screen col 1 = file 8
    else
        rank=9-screenRow        -- screen row 1 = rank 8, screen row 8 = rank 1
        file=screenCol          -- screen col 1 = file 1
    end
    return rank,file
end

local LIGHT_BG=colors.white
local DARK_BG =colors.gray
local SEL_BG  =colors.yellow
local HINT_BG =colors.lime
local LAST_BG =colors.cyan
local CHK_BG  =colors.red

local function pieceColors(p)
    if isWhite(p) then return colors.orange,nil end
    if isBlack(p) then return colors.blue,nil end
    return colors.white,nil
end

local function drawBoard(mon,W,H,board,flipped,selected,hints,lastMove,checkKing)
    local ox,oy=boardOrigin(W,H)
    local cols={"a","b","c","d","e","f","g","h"}

    -- column labels
    for sc=1,8 do
        local file=flipped and (9-sc) or sc
        writeAt(mon,ox+1+(sc-1)*2,oy,cols[file],colors.lightGray,colors.black)
        writeAt(mon,ox+1+(sc-1)*2+1,oy," ",colors.lightGray,colors.black)
    end

    -- rows
    for sr=1,8 do
        local rank=flipped and sr or (9-sr)
        writeAt(mon,ox,oy+sr,tostring(rank),colors.lightGray,colors.black)

        for sc=1,8 do
            local file=flipped and (9-sc) or sc
            local p=board[rank][file]
            local sym=PIECE_CHAR[p]
            local isLight=((rank+file)%2==0)
            local bg=isLight and LIGHT_BG or DARK_BG
            local fg=pieceColors(p)

            if selected and selected[1]==rank and selected[2]==file then
                bg=SEL_BG
            elseif hints and hints[rank] and hints[rank][file] then
                bg=HINT_BG
            elseif lastMove and (
                (lastMove[1]==rank and lastMove[2]==file) or
                (lastMove[3]==rank and lastMove[4]==file)) then
                bg=LAST_BG
            end
            if checkKing and checkKing[1]==rank and checkKing[2]==file then
                bg=CHK_BG
            end

            local cx=ox+1+(sc-1)*2
            writeAt(mon,cx,oy+sr,sym,fg,bg)
            writeAt(mon,cx+1,oy+sr," ",fg,bg)
        end
    end
end

-- =====================================================
-- MODE SELECTION
-- =====================================================

local function drawModeScreen(mon,W,H)
    clearMon(mon)
    writeAt(mon,centreX(W,"CHESS"),2,"CHESS",colors.yellow)
    writeAt(mon,centreX(W,"Choose mode:"),3,"Choose mode:",colors.white)
    local mid=math.floor(H/2)
    local bAI =drawButton(mon,centreX(W,"[ vs AI ]"),    mid-1,"vs AI",    colors.black,colors.lime)
    local b2P =drawButton(mon,centreX(W,"[ 2 Players ]"),mid+1,"2 Players",colors.black,colors.cyan)
    return bAI,b2P
end

local function modeSelect()
    local b1ai,b1two=drawModeScreen(mon1,W1,H1)
    local b2ai,b2two=drawModeScreen(mon2,W2,H2)
    while true do
        local ev={os.pullEvent("monitor_touch")}
        local mname,tx,ty=ev[2],ev[3],ev[4]
        local bai,b2p
        if mname==mon1Name then bai=b1ai; b2p=b1two
        elseif mname==mon2Name then bai=b2ai; b2p=b2two end
        if bai then
            if hitBtn(bai,tx,ty) then return "ai"
            elseif hitBtn(b2p,tx,ty) then return "2p" end
        end
    end
end

-- =====================================================
-- AI (minimax + alpha-beta)
-- =====================================================

local PIECE_VAL={[1]=20000,[2]=900,[3]=500,[4]=330,[5]=320,[6]=100}
local function pieceVal(p)
    local pt=p; if pt>6 then pt=pt-6 end
    return PIECE_VAL[pt] or 0
end

local function evaluate(b)
    local s=0
    for r=1,8 do for c=1,8 do
        local p=b[r][c]
        if not isEmpty(p) then
            local v=pieceVal(p)
            if isWhite(p) then s=s+v else s=s-v end
        end
    end end
    return s
end

local aiNodes=0

local function minimax(b,depth,alpha,beta,white,ep,castling)
    aiNodes=aiNodes+1
    if aiNodes%200==0 then sleep(0) end  -- yield to prevent "too long without yielding"

    local moves=getLegalMoves(b,white,ep,castling)
    if depth==0 or #moves==0 then return evaluate(b),nil end
    local best=white and -math.huge or math.huge
    local bestMove=nil
    for _,m in ipairs(moves) do
        local nb,nep,ncast=applyMove(b,m,ep,castling)
        local pt=b[m[1]][m[2]]; if pt>6 then pt=pt-6 end
        if pt==6 then
            if white and m[3]==8 then nb[m[3]][m[4]]=WQ end
            if not white and m[3]==1 then nb[m[3]][m[4]]=BQ end
        end
        local val,_=minimax(nb,depth-1,alpha,beta,not white,nep,ncast)
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

local AI_DEPTH=2

-- =====================================================
-- PROMOTION
-- =====================================================

local function doPromotion(monName,mon,W,H,white)
    clearMon(mon)
    writeAt(mon,centreX(W,"Promote pawn:"),2,"Promote pawn:",colors.yellow)
    local pieces=white and {WQ,WR,WB,WN} or {BQ,BR,BB,BN}
    local names={"Queen","Rook","Bishop","Knight"}
    local btns={}
    local mid=math.floor(H/2)-1
    for i=1,4 do
        local lbl=PIECE_CHAR[pieces[i]].." "..names[i]
        local x=centreX(W,"[ "..lbl.." ]")
        local b=drawButton(mon,x,mid+(i-1)*2,lbl,colors.black,colors.lime)
        b.piece=pieces[i]
        btns[i]=b
    end
    while true do
        local ev={os.pullEvent("monitor_touch")}
        if ev[2]==monName then
            local tx,ty=ev[3],ev[4]
            for _,btn in ipairs(btns) do
                if hitBtn(btn,tx,ty) then return btn.piece end
            end
        end
    end
end

-- =====================================================
-- GAME
-- =====================================================

local function buildHints(moves,rank,file)
    local h={}
    for _,m in ipairs(moves) do
        if m[1]==rank and m[2]==file then
            if not h[m[3]] then h[m[3]]={} end
            h[m[3]][m[4]]=true
        end
    end
    return h
end

local function game(mode)
    local board=newBoard()
    local ep=nil
    local castling={wk=true,wq=true,bk=true,bq=true}
    local whiteToMove=true
    local selected=nil
    local hints={}
    local lastMove=nil
    local legalMoves=getLegalMoves(board,true,ep,castling)

    local function redraw(aiThinking)
        local inCheck=isInCheck(board,whiteToMove)
        local ck=nil
        if inCheck then
            local kr,kc=findKing(board,whiteToMove)
            ck={kr,kc}
        end

        -- status line text
        local status
        if aiThinking then status="AI thinking..."
        elseif inCheck then status=(whiteToMove and "White" or "Black").." CHECK!"
        else status=(whiteToMove and "White" or "Black").."'s turn" end

        -- Mon1 = White side (not flipped), Mon2 = Black side (flipped)
        clearMon(mon1)
        drawBoard(mon1,W1,H1,board,false,
            whiteToMove and selected or nil,
            whiteToMove and hints or {},
            lastMove,ck)
        -- header
        if whiteToMove and not aiThinking then
            writeAt(mon1,centreX(W1,"YOUR TURN"),1,"YOUR TURN",colors.lime)
        else
            writeAt(mon1,centreX(W1,"Waiting..."),1,"Waiting...",colors.lightGray)
        end
        writeAt(mon1,centreX(W1,status),H1,status,inCheck and colors.red or colors.yellow)

        clearMon(mon2)
        drawBoard(mon2,W2,H2,board,true,
            not whiteToMove and selected or nil,
            not whiteToMove and hints or {},
            lastMove,ck)
        if not whiteToMove and not aiThinking then
            writeAt(mon2,centreX(W2,"YOUR TURN"),1,"YOUR TURN",colors.lime)
        elseif aiThinking then
            writeAt(mon2,centreX(W2,"AI thinking..."),1,"AI thinking...",colors.orange)
        else
            writeAt(mon2,centreX(W2,"Waiting..."),1,"Waiting...",colors.lightGray)
        end
        writeAt(mon2,centreX(W2,status),H2,status,inCheck and colors.red or colors.yellow)
    end

    redraw(false)

    while true do
        -- game over?
        if #legalMoves==0 then
            local inCheck=isInCheck(board,whiteToMove)
            local msg=inCheck
                and (whiteToMove and "Black wins!" or "White wins!")
                or "Stalemate! Draw."
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
            local _,aiMove=minimax(board,AI_DEPTH,-math.huge,math.huge,false,ep,castling)
            if aiMove then
                local nb,nep,ncast=applyMove(board,aiMove,ep,castling)
                local pt=board[aiMove[1]][aiMove[2]]; if pt>6 then pt=pt-6 end
                if pt==6 and aiMove[3]==1 then nb[aiMove[3]][aiMove[4]]=BQ end
                board=nb; ep=nep; castling=ncast
                lastMove=aiMove; selected=nil; hints={}
                whiteToMove=true
                legalMoves=getLegalMoves(board,true,ep,castling)
                redraw(false)
            end
        else
            -- human turn
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
                    if selected then
                        local moved=false
                        for _,m in ipairs(legalMoves) do
                            if m[1]==selected[1] and m[2]==selected[2] and m[3]==rank and m[4]==file then
                                local nb,nep,ncast=applyMove(board,m,ep,castling)
                                local pt=board[m[1]][m[2]]; if pt>6 then pt=pt-6 end
                                if pt==6 then
                                    local promRow=whiteToMove and 8 or 1
                                    if m[3]==promRow then
                                        local pmon=whiteToMove and mon1 or mon2
                                        local pmonName=whiteToMove and mon1Name or mon2Name
                                        local pW=whiteToMove and W1 or W2
                                        local pH=whiteToMove and H1 or H2
                                        local piece=doPromotion(pmonName,pmon,pW,pH,whiteToMove)
                                        nb[m[3]][m[4]]=piece
                                    end
                                end
                                board=nb; ep=nep; castling=ncast
                                lastMove=m; selected=nil; hints={}
                                whiteToMove=not whiteToMove
                                legalMoves=getLegalMoves(board,whiteToMove,ep,castling)
                                moved=true
                                break
                            end
                        end
                        if not moved then
                            local p=board[rank][file]
                            if (whiteToMove and isWhite(p)) or (not whiteToMove and isBlack(p)) then
                                selected={rank,file}
                                hints=buildHints(legalMoves,rank,file)
                            else
                                selected=nil; hints={}
                            end
                        end
                    else
                        local p=board[rank][file]
                        if (whiteToMove and isWhite(p)) or (not whiteToMove and isBlack(p)) then
                            selected={rank,file}
                            hints=buildHints(legalMoves,rank,file)
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
