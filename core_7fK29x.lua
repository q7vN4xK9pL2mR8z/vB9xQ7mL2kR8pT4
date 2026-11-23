setDefaultTab("Main")
BossFarm = BossFarm or {}
BossFarm.VERSAO = "2.9"

if bossFarmWindow then
    bossFarmWindow:destroy()
    bossFarmWindow = nil
end

BossFarm.ativo = macro(1000, "Boss Farm", function()
end)
if BossFarm.ativo.switch then BossFarm.ativo.switch:hide() end

BossFarm.currentBoss = nil
BossFarm.entrou = false
BossFarm.derrotou = false
BossFarm.teleportado = false
BossFarm.tentativaEntrada = 0
BossFarm.esperandoEntrada = false
BossFarm.tempoPasso = 0
BossFarm.passagem = {}
BossFarm.pendente = {}
BossFarm.buscandoPendente = false
BossFarm.pendenteAtual = nil
BossFarm.jaDerrotadoDetectado = false
BossFarm.estado = "AGUARDANDO"
BossFarm.ultimoEvento = "-"
BossFarm.ultimoEventoTime = "-"
BossFarm.lastNpcCheck = 0
BossFarm.lastLabel = nil

BossFarm.dentroDaSala = nil
BossFarm.ultimoBossVisto = nil
BossFarm.ultimoBossVistoTime = 0

BossFarm.lastHarvestableCheck = 0
BossFarm.cachedHarvestableCount = 0
BossFarm.lastHwWarn = 0
BossFarm.lastVipWarn = 0

BossFarm.resetBtnTimer = 0
BossFarm.saveBtnTimer = 0

BossFarm.NPC = BossFarm.NPC or {
    modo = "AUTO",
    etapa = 0,
    ativo = false,
    concluido = false,
    timer = 0,
    queue = {}
}

storage.BossFarmHorario = storage.BossFarmHorario or {}
storage.BossFarmRotationType = storage.BossFarmRotationType or "FULL"
storage.BossFarmNPCList = storage.BossFarmNPCList or {}
storage.BossFarmCustomList = storage.BossFarmCustomList or {}
storage.BossFarmVipExpiration = storage.BossFarmVipExpiration or 0

storage.BossFarmModeCount = storage.BossFarmModeCount or "3X"
storage.BossFarmExecutionMode = storage.BossFarmExecutionMode or "SCHEDULE"
storage.BossFarmAvisoNome = storage.BossFarmAvisoNome or false
storage.BossFarmModoCave = storage.BossFarmModoCave or "UNICO"
storage.BossFarmDelayEntrada = storage.BossFarmDelayEntrada or 1
storage.BossAntiTrapTPEnabled = false

-- CONFIG POR PERSONAGEM: arquivo /BossFarm/<personagem>.json (fora da pasta bot e do storage do vBot).
-- O storage do vBot e por config e pode falhar ao salvar (ai apos SS/relog voltava horario vazio e rotacoes
-- desativadas). O arquivo e lido ao carregar o script e tem prioridade; e regravado a cada 1 min se mudar e no SALVAR.
BossFarm.CAMPOS_HORARIO_ARQ = {"horariosConfigurados", "rotacoesAtivas", "ativasSalvas", "labelConfigurado", "labelPosNpc"}
BossFarm.CAMPOS_STORAGE_ARQ = {"BossFarmRotationType", "BossFarmModeCount", "BossFarmExecutionMode", "BossFarmCustomList", "BossFarmAvisoNome", "BossFarmModoCave", "BossFarmDelayEntrada", "BossFarmCaveHunt"}
function BossFarm.arquivoConfig()
    local ok, nome = pcall(function() return player:getName() end)
    if not ok or type(nome) ~= "string" or nome == "" then return nil end
    nome = nome:gsub("%s*%[%d+%]%s*$", "")   -- neste servidor o nome vem com o nivel: "Fulano [30]"
    return "/BossFarm/" .. nome:lower():gsub("[^%w]+", "_"):gsub("_+$", "") .. ".json"
end
function BossFarm.textoConfig()
    local dados = {horario = {}}
    for _, k in ipairs(BossFarm.CAMPOS_HORARIO_ARQ) do dados.horario[k] = storage.BossFarmHorario[k] end
    for _, k in ipairs(BossFarm.CAMPOS_STORAGE_ARQ) do dados[k] = storage[k] end
    local ok, txt = pcall(function() return json.encode(dados) end)
    return ok and txt or nil
end
do
    local arq = BossFarm.arquivoConfig()
    local ok, dados = pcall(function()
        if not (arq and g_resources and g_resources.fileExists(arq)) then return nil end
        return json.decode(g_resources.readFileContents(arq))
    end)
    if ok and type(dados) == "table" and type(dados.horario) == "table" then
        -- copia ate o nil (ex.: ativasSalvas velho no storage nao pode sobrescrever as rotacoes do arquivo)
        for _, k in ipairs(BossFarm.CAMPOS_HORARIO_ARQ) do storage.BossFarmHorario[k] = dados.horario[k] end
        for _, k in ipairs(BossFarm.CAMPOS_STORAGE_ARQ) do
            if dados[k] ~= nil then storage[k] = dados[k] end
        end
        print("[BossFarm] Horarios/config carregados de " .. arq)
    elseif arq then
        print("[BossFarm] Criando " .. arq .. " (horarios valem pra qualquer config deste personagem)")
    end
end
BossFarm.ultimoArquivo = nil
function BossFarm.gravarArquivo()
    local arq = BossFarm.arquivoConfig()
    if not (arq and g_resources and g_resources.writeFileContents) then return end
    local txt = BossFarm.textoConfig()
    if not txt or txt == BossFarm.ultimoArquivo then return end
    if g_resources.makeDir and g_resources.directoryExists and not g_resources.directoryExists("/BossFarm") then
        pcall(g_resources.makeDir, "/BossFarm")
    end
    local ok, err = pcall(g_resources.writeFileContents, arq, txt)
    if ok then
        BossFarm.ultimoArquivo = txt
    elseif not BossFarm.avisouErroArquivo then
        BossFarm.avisouErroArquivo = true
        print("[BossFarm] ERRO ao salvar " .. arq .. ": " .. tostring(err))
    end
end
macro(60000, BossFarm.gravarArquivo)   -- a cada 1 min (so grava se mudou); o botao SALVAR grava na hora

BossFarm.HorariosPadrao ={"05:00", "21:20", "22:20"}

function BossFarm.modoGratis()
    return storage.BossFarmExecutionMode == "ONCE"
end

function BossFarm.irParaSaidaGratis()
    if BossFarm.finalizarRotacao then BossFarm.finalizarRotacao() end
    BossFarm.buscandoPendente = false
    BossFarm.pendenteAtual = nil
    local cfg = storage.BossFarmHorario
    local labelSaida = (cfg and cfg.labelPosNpc) or "saida cave"
    BossFarm.estado = "ROTACAO GRATIS CONCLUIDA"
    BossFarm.logEvento("Rotacao Gratis concluida! Sem NPC. Indo para: " .. labelSaida)
    BossFarm.irPara(labelSaida)
end

function BossFarm.iniciarStart()
    storage.BossAntiTrapTPEnabled = true
    BossFarm.estado = "CACANDO (START)"

    BossFarm.currentBoss = nil
    BossFarm.resetBoss()
    BossFarm.dentroDaSala = nil

    local proximo = BossFarm.proximoPendente()

    if proximo then
        BossFarm.logEvento("Retomada/Inicio: Indo direto para o Boss " .. proximo .. " (os anteriores ja estao feitos).")
        BossFarm.irPara(BossFarm.label[proximo])
    else
        if BossFarm.modoGratis() then
            BossFarm.logEvento("Todos os bosses ja marcados! (Rotacao Gratis: sem NPC)")
            BossFarm.irParaSaidaGratis()
        else
            BossFarm.logEvento("Todos os bosses ja marcados! Indo para o NPC limpar.")
            BossFarm.irPara("npc")
        end
    end

    if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
    return true
end

function BossFarm.desligarAntiTrap()
    storage.BossAntiTrapTPEnabled = false
    storage.BossFarmStartForcado = false
    storage.autoPartyEnabled = false
    local okS, shield = pcall(function() return player:getShield() end)
    if okS and (shield or 0) >= 3 and g_game.partyLeave then
        g_game.partyLeave()
        BossFarm.logEvento("Saiu da party.")
    end
    BossFarm.lastLabel = nil
    BossFarm.logEvento("Saindo da rotacao: Anti-TP DESATIVADO via CaveBot e memoria de labels limpa.")
    if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
    return true
end

function BossFarm.limparMemoria() return BossFarm.desligarAntiTrap() end

function BossFarm.irPara(label)
    BossFarm.lastLabel = label
    if label == "start" or string.find(label, "boss") then
        storage.BossAntiTrapTPEnabled = true
    end
    if BossFarm.modoSeparado() then
        local destino = BossFarm.labelDaRota(label) and BossFarm.CAVE_BOSS or storage.BossFarmCaveHunt
        local atual = BossFarm.caveAtual()
        if destino and destino ~= "" and atual ~= destino then
            if destino == BossFarm.CAVE_BOSS and atual then storage.BossFarmCaveHunt = atual BossFarm.gravarArquivo() end
            if BossFarm.trocarCave(destino) then
                BossFarm.labelAposTroca = label
                BossFarm.labelAposTrocaAte = os.time() + 5
                return
            end
        end
    end
    CaveBot.gotoLabel(label)
end

BossFarm.CAVE_BOSS = "farmboss"

BossFarm.ROTA_CAVE_BOSS = [==[
label:start
goto:7668,1051,3
goto:7670,1051,3
goto:7676,1051,3
delaysec:5
function:return BossFarm.aguardarMinuto27()
delaysec:1,5
function:[[
BossFarm.iniciarNovaRotacao()
return true
]]
delaysec:1,5
function:[[
BossFarm.checarProximoCustom()
return true
]]
delaysec:1,5
goto:7673,1051,3
goto:7677,1051,3
goto:7680,1051,3
goto:7684,1051,3
goto:7686,1051,3
goto:7687,1051,3
goto:7687,1052,3
goto:7687,1053,3
goto:7686,1056,3
goto:7686,1061,3
goto:7686,1066,3
goto:7688,1066,3
goto:7688,1070,3
goto:7688,1072,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(1)
local p = pos()
if p.x == 7688 and p.z == 3 and p.y >= 1066 and p.y <= 1074 then
    return BossFarm.tentarEntrada(p.y - 1065, South)
end
return true
]]
label:boss1
goto:7688,1074,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(1)
local p = pos()
if p.x == 7688 and p.y == 1074 and p.z == 3 then
    return BossFarm.tentarEntrada(1, South)
end
return true
]]
goto:7774,1433,3
goto:7774,1428,3
goto:7774,1423,3
goto:7775,1419,3
goto:7775,1414,3
goto:7774,1412,3
label:spawn1
function:return BossFarm.waitBossDead(1)
label:boss2
goto:7687,1069,3
goto:7687,1065,3
goto:7687,1063,3
goto:7687,1061,3
goto:7691,1061,3
goto:7694,1061,3
goto:7696,1061,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(2)
local p = pos()
if p.x == 7696 and p.y == 1061 and p.z == 3 then
    return BossFarm.tentarEntrada(2, East)
end
return true
]]
goto:7699,1278,5
goto:7699,1273,5
goto:7703,1273,5
goto:7706,1269,5
goto:7707,1266,5
goto:7704,1265,5
goto:7700,1265,5
goto:7700,1263,5
goto:7700,1258,6
goto:7695,1254,6
goto:7690,1255,6
label:spawn2
function:return BossFarm.waitBossDead(2)
label:boss3
goto:7690,1061,3
goto:7688,1061,3
goto:7687,1058,3
goto:7687,1056,3
goto:7687,1052,3
goto:7687,1050,3
goto:7691,1049,3
goto:7695,1049,3
goto:7696,1049,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(3)
local p = pos()
if p.x == 7696 and p.y == 1049 and p.z == 3 then
    return BossFarm.tentarEntrada(3, East)
end
return true
]]
goto:7943,1295,2
goto:7946,1295,2
goto:7948,1295,2
goto:7949,1295,2
goto:7951,1295,3,0
goto:7956,1295,4
goto:7960,1300,4
goto:7965,1302,4
goto:7970,1301,4
goto:7970,1298,4
goto:7970,1297,4
goto:7970,1295,4
label:spawn3
function:return BossFarm.waitBossDead(3)
label:boss4
goto:7690,1049,3
goto:7687,1049,3
goto:7687,1044,3
goto:7687,1042,3
goto:7687,1038,3
goto:7690,1037,3
goto:7693,1035,3
goto:7695,1033,3
goto:7696,1033,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(4)
local p = pos()
if p.x == 7696 and p.y == 1033 and p.z == 3 then
    return BossFarm.tentarEntrada(4, East)
end
return true
]]
goto:7934,1144,4
goto:7934,1141,4
goto:7934,1140,4
goto:7934,1135,5
goto:7938,1130,5
goto:7938,1125,5
goto:7933,1123,5
label:spawn4
function:return BossFarm.waitBossDead(4)
label:boss5
goto:7690,1036,3
goto:7686,1037,3
goto:7683,1037,3
goto:7681,1034,3
goto:7681,1030,3
goto:7681,1027,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(5)
local p = pos()
if p.x == 7681 and p.y == 1027 and p.z == 3 then
    return BossFarm.tentarEntrada(5, North)
end
return true
]]
goto:7935,1205,4
goto:7935,1208,4
goto:7935,1212,4
goto:7935,1214,4
goto:7935,1215,4
goto:7935,1220,5
goto:7935,1225,5
goto:7935,1228,5
label:spawn5
function:return BossFarm.waitBossDead(5)
label:boss6
goto:7681,1034,3
goto:7679,1036,3
goto:7674,1037,3
goto:7671,1037,3
goto:7670,1033,3
goto:7670,1030,3
goto:7670,1027,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(6)
local p = pos()
if p.x == 7670 and p.y == 1027 and p.z == 3 then
    return BossFarm.tentarEntrada(6, North)
end
return true
]]
goto:7774,1362,2
goto:7777,1362,2
goto:7778,1362,2
goto:7783,1362,3
goto:7788,1360,3
goto:7793,1360,3
goto:7798,1356,3
goto:7799,1351,3
goto:7799,1348,3
label:spawn6
function:return BossFarm.waitBossDead(6)
label:boss7
goto:7670,1034,3
goto:7667,1034,3
goto:7663,1034,3
goto:7658,1034,3
goto:7658,1030,3
goto:7658,1027,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(7)
local p = pos()
if p.x == 7658 and p.y == 1027 and p.z == 3 then
    return BossFarm.tentarEntrada(7, North)
end
return true
]]
goto:7699,1203,4
goto:7699,1199,4
goto:7699,1194,4
goto:7699,1191,4
goto:7698,1188,4
goto:7698,1183,4
goto:7698,1179,4
label:spawn7
function:return BossFarm.waitBossDead(7)
label:boss8
goto:7658,1034,3
goto:7655,1036,3
goto:7649,1036,3
goto:7645,1036,3
goto:7645,1033,3
goto:7644,1030,3
goto:7644,1026,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(8)
local p = pos()
if p.x == 7644 and p.y == 1026 and p.z == 3 then
    return BossFarm.tentarEntrada(8, North)
end
return true
]]
goto:7844,1116,5
goto:7844,1120,5
goto:7844,1126,5
goto:7844,1130,5
goto:7844,1133,5
label:spawn8
function:return BossFarm.waitBossDead(8)
label:boss9
goto:7644,1035,3
goto:7644,1036,3
goto:7644,1037,3
goto:7639,1038,3
goto:7636,1038,3
goto:7632,1038,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(9)
local p = pos()
if p.x == 7632 and p.y == 1038 and p.z == 3 then
    return BossFarm.tentarEntrada(9, West)
end
return true
]]
goto:7805,1229,3
goto:7805,1225,3
goto:7805,1222,3
goto:7805,1221,3
goto:7810,1218,4
goto:7815,1218,4
goto:7816,1216,4,0
goto:7821,1212,3
goto:7822,1207,3
goto:7824,1202,3
goto:7825,1197,3
goto:7825,1192,3
goto:7823,1187,3
goto:7819,1187,3,0
goto:7814,1186,2
label:spawn9
function:return BossFarm.waitBossDead(9)
label:boss10
goto:7640,1038,3
goto:7643,1038,3
goto:7644,1041,3
goto:7644,1045,3
goto:7644,1049,3
goto:7644,1053,3
goto:7641,1053,3
goto:7637,1052,3
goto:7634,1052,3
goto:7632,1052,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(10)
local p = pos()
if p.x == 7632 and p.y == 1052 and p.z == 3 then
    return BossFarm.tentarEntrada(10, West)
end
return true
]]
goto:7638,1130,3
goto:7639,1134,3
goto:7640,1137,3
goto:7642,1140,3
goto:7639,1140,3
goto:7638,1140,3
goto:7636,1140,3,0
goto:7631,1140,2
goto:7630,1135,2
goto:7627,1130,2
goto:7627,1125,2
goto:7622,1125,2
goto:7617,1123,2
goto:7612,1123,2
goto:7612,1126,2,0
goto:7615,1131,3
goto:7615,1136,3
goto:7612,1136,3
label:spawn10
function:return BossFarm.waitBossDead(10)
label:boss11
goto:7638,1052,3
goto:7640,1052,3
goto:7643,1052,3
goto:7643,1057,3
goto:7643,1063,3
goto:7640,1064,3
goto:7636,1064,3
goto:7633,1064,3
goto:7631,1064,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(11)
local p = pos()
if p.x == 7631 and p.y == 1064 and p.z == 3 then
    return BossFarm.tentarEntrada(11, West)
end
return true
]]
goto:7799,1116,4
goto:7794,1118,4
goto:7790,1118,4
goto:7786,1118,4
goto:7786,1127,4
goto:7783,1127,4
label:spawn11
function:return BossFarm.waitBossDead(11)
label:boss12
goto:7639,1065,3
goto:7643,1065,3
goto:7644,1067,3
goto:7644,1071,3
goto:7644,1074,3
goto:7644,1075,3
goto:7644,1077,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(12)
local p = pos()
if p.x == 7644 and p.y == 1077 and p.z == 3 then
    return BossFarm.tentarEntrada(12, South)
end
return true
]]
goto:7936,1386,4
goto:7938,1390,4
goto:7942,1388,4
goto:7942,1381,4
goto:7944,1378,4
label:spawn12
function:return BossFarm.waitBossDead(12)
label:boss13
goto:7645,1070,3
goto:7645,1068,3
goto:7648,1068,3
goto:7651,1067,3
goto:7656,1067,3
goto:7658,1073,3
goto:7657,1074,3
goto:7657,1075,3
goto:7657,1077,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(13)
local p = pos()
if p.x == 7657 and p.y == 1077 and p.z == 3 then
    return BossFarm.tentarEntrada(13, South)
end
return true
]]
goto:7704,1153,4
goto:7704,1149,4
goto:7704,1143,4
goto:7704,1137,4
goto:7704,1132,4
goto:7704,1128,4
label:spawn13
function:return BossFarm.waitBossDead(13)
label:boss14
goto:7658,1070,3
goto:7660,1067,3
goto:7664,1067,3
goto:7667,1067,3
goto:7669,1071,3
goto:7668,1073,3
goto:7668,1075,3
goto:7668,1077,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(14)
local p = pos()
if p.x == 7668 and p.y == 1077 and p.z == 3 then
    return BossFarm.tentarEntrada(14, South)
end
return true
]]
goto:7791,1277,4
goto:7791,1283,4
goto:7791,1287,4
goto:7791,1292,4
label:spawn14
function:return BossFarm.waitBossDead(14)
label:boss15
goto:7668,1069,3
goto:7672,1068,3
goto:7677,1068,3
goto:7678,1071,3
goto:7678,1075,3
goto:7678,1077,3
function:return BossFarm.esperaEntrada()
function:[[
BossFarm.setCurrent(15)
local p = pos()
if p.x == 7678 and p.y == 1077 and p.z == 3 then
    return BossFarm.tentarEntrada(15, South)
end
return true
]]
goto:7697,1348,5
goto:7697,1349,5
goto:7697,1349,5
goto:7697,1354,5
goto:7697,1358,5
goto:7697,1363,5
goto:7695,1366,5
goto:7696,1368,5
goto:7696,1372,5
goto:7696,1374,5
goto:7696,1374,5
label:spawn15
function:return BossFarm.waitBossDead(15)
delaysec:2
function:return BossFarm.checarPendentesFinal()
label:npc
delaysec:3
goto:7678,1069,3
goto:7674,1068,3
goto:7670,1068,3
goto:7665,1068,3
goto:7665,1065,3
goto:7665,1061,3
goto:7665,1051,3
goto:7665,1051,3
delaysec:1
function:return BossFarm.fazerNPC()
]==]

function BossFarm.arquivoCaveBoss()
    local nomeConfig = nil
    pcall(function() nomeConfig = modules.game_bot.contentsPanel.config:getCurrentOption().text end)
    if not nomeConfig then return nil end
    return "/bot/" .. nomeConfig .. "/cavebot_configs/" .. BossFarm.CAVE_BOSS .. ".cfg"
end

function BossFarm.instalarCaveBoss()
    local arq = BossFarm.arquivoCaveBoss()
    if not (arq and g_resources and g_resources.writeFileContents) then return false end
    local okL, atual = pcall(function()
        if not g_resources.fileExists(arq) then return nil end
        return g_resources.readFileContents(arq)
    end)
    if okL and atual == BossFarm.ROTA_CAVE_BOSS then return true end
    local ok, err = pcall(g_resources.writeFileContents, arq, BossFarm.ROTA_CAVE_BOSS)
    if ok then
        BossFarm.logEvento("CaveBot '" .. BossFarm.CAVE_BOSS .. "' criado/atualizado em " .. arq)
    else
        BossFarm.logEvento("ERRO ao criar " .. arq .. ": " .. tostring(err))
    end
    return ok
end

function BossFarm.modoSeparado()
    return storage.BossFarmModoCave == "SEPARADO"
end

function BossFarm.labelDaRota(label)
    label = tostring(label or ""):lower()
    return label == "start" or label == "npc" or label:match("^boss%d+$") ~= nil or label:match("^spawn%d+$") ~= nil
end

function BossFarm.caveAtual()
    if not (CaveBot and CaveBot.getCurrentProfile) then return nil end
    local ok, nome = pcall(CaveBot.getCurrentProfile)
    if ok and nome then return nome end
    return nil
end

function BossFarm.trocarCave(nome)
    if not (CaveBot and CaveBot.setCurrentProfile) then
        BossFarm.logEvento("Seu vBot nao permite trocar o CaveBot por script (falta setCurrentProfile).")
        return false
    end
    if nome == BossFarm.CAVE_BOSS then BossFarm.instalarCaveBoss() end
    local ok, err = pcall(CaveBot.setCurrentProfile, nome)
    if not ok or BossFarm.caveAtual() ~= nome then
        BossFarm.logEvento("Erro ao trocar para o CaveBot '" .. tostring(nome) .. "': " .. tostring(err or "perfil nao existe"))
        return false
    end
    BossFarm.logEvento("CaveBot trocado para '" .. nome .. "'.")
    return true
end

function BossFarm.esperaEntrada()
    local seg = tonumber(storage.BossFarmDelayEntrada) or 1
    if seg > 0 then CaveBot.delay(math.floor(seg * 1000)) end
    return true
end

macro(100, function()
    local label = BossFarm.labelAposTroca
    if not label then return end
    if CaveBot.gotoLabel(label) then
        BossFarm.labelAposTroca = nil
    elseif os.time() > (BossFarm.labelAposTrocaAte or 0) then
        BossFarm.labelAposTroca = nil
        BossFarm.logEvento("Label '" .. label .. "' nao existe no CaveBot '" .. tostring(BossFarm.caveAtual()) .. "'.")
    end
end)

function BossFarm.naZonaBoss(p)
    return p and p.x >= 7550 and p.x <= 8050 and p.y >= 1000 and p.y <= 1500
end

BossFarm.foraDaZonaDesde = nil
macro(1000, function()
    if not BossFarm.modoSeparado() or BossFarm.caveAtual() ~= BossFarm.CAVE_BOSS then
        BossFarm.foraDaZonaDesde = nil
        return
    end
    if BossFarm.naZonaBoss(player:getPosition()) then
        BossFarm.foraDaZonaDesde = nil
        return
    end
    BossFarm.foraDaZonaDesde = BossFarm.foraDaZonaDesde or os.time()
    if os.time() - BossFarm.foraDaZonaDesde < 20 then return end
    BossFarm.foraDaZonaDesde = nil
    local hunt = storage.BossFarmCaveHunt
    if not hunt or hunt == "" then
        BossFarm.logEvento("Vigia: fora da area dos bosses no CaveBot '" .. BossFarm.CAVE_BOSS .. "', mas o CaveBot da hunt nao e conhecido. Troque manualmente.")
        return
    end
    BossFarm.logEvento("Vigia: 20s fora da area dos bosses (morte/queda/relog). Voltando para o CaveBot da hunt '" .. hunt .. "'.")
    BossFarm.trocarCave(hunt)
end)

BossFarm.PASSE_SEG = 600
BossFarm.passeAte = 0

function BossFarm.darPasse()
    BossFarm.passeAte = os.time() + BossFarm.PASSE_SEG
end

function BossFarm.primeiraLabel()
    local lista = CaveBot.actionList
    if not lista then return nil end
    for _, child in ipairs(lista:getChildren()) do
        if child.action == "label" then return child.value end
    end
    return nil
end

function BossFarm.travaFarmboss()
    if os.time() <= (BossFarm.passeAte or 0) then return true end
    BossFarm.estado = "FARMBOSS SEM PASSE"
    local volta = BossFarm.primeiraLabel()
    if volta and CaveBot.gotoLabel(volta) then
        BossFarm.lastLabel = volta
        BossFarm.logEvento("Farmboss sem passe! Voltando para a 1a label: " .. volta)
        return "retry"
    end
    if os.time() - (BossFarm.lastTravaWarn or 0) >= 5 then
        BossFarm.lastTravaWarn = os.time()
        BossFarm.logEvento("Farmboss sem passe! Nenhuma label achada na CaveBot, parado antes do TP.")
    end
    delay(1000)
    return "retry"
end

macro(500, function()
    if BossFarm.ativo.isOff() then return end
    for _, spec in ipairs(getSpectators()) do
        if spec:isMonster() then
            local mName = spec:getName():lower()
            if BossFarm.nomeMap[mName] then
                for i, bName in ipairs(BossFarm.nome) do
                    if bName:lower() == mName then
                        if BossFarm.currentBoss ~= i then
                            BossFarm.setCurrent(i)
                            BossFarm.entrou = true
                            BossFarm.estado = "DENTRO DA BOSS ROOM"
                            BossFarm.logEvento("Auto-Detect: Identificou o Boss " .. i .. " (" .. bName .. ") na tela (Entrada Manual).")
                            if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
                        end
                        return
                    end
                end
            end
        end
    end
end)

function BossFarm.noLobby(p)
    return p and p.z == 3 and p.x >= 7610 and p.x <= 7700 and p.y >= 1020 and p.y <= 1084
end

macro(1000, function()
    if BossFarm.ativo.isOff() then return end

    local myPos = player:getPosition()
    if not myPos then return end

    local inBossArea = BossFarm.noLobby(myPos)

    if inBossArea then
        local comPasse = os.time() <= (BossFarm.passeAte or 0)
        BossFarm.passeAte = 0
        if comPasse and BossFarm.modoSeparado() and BossFarm.caveAtual() ~= BossFarm.CAVE_BOSS then
            storage.BossFarmStartForcado = true
            BossFarm.logEvento("Chegou na sala dos TPs: trocando para o CaveBot '" .. BossFarm.CAVE_BOSS .. "'.")
            BossFarm.irPara("start")
        end

        if not storage.BossAntiTrapTPEnabled then
            storage.BossAntiTrapTPEnabled = true
            BossFarm.logEvento("Auto-Deteccao: Personagem nas salas dos bosses. Anti-TP LIGADO automaticamente.")
            if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
        end

        if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
            TargetBot.setOn()
            BossFarm.logEvento("Auto-Deteccao: TargetBot estava desligado. Forcando para LIGADO.")
        end

        if not storage.autoPartyEnabled then
            storage.autoPartyEnabled = true
            BossFarm.logEvento("Auto-Deteccao: Auto Party Leader LIGADO automaticamente.")
            if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
        end

        local naEntrada = myPos.x >= 7663 and myPos.x <= 7667 and myPos.y >= 1049 and myPos.y <= 1053
        local ocupado = BossFarm.esperandoEntrada or (BossFarm.tentativaEntrada or 0) > 0
            or BossFarm.entrou or BossFarm.buscandoPendente or BossFarm.NPC.ativo
        if naEntrada and not ocupado and not storage.BossFarmStartForcado then
            storage.BossFarmStartForcado = true
            BossFarm.logEvento("Auto-Deteccao: entrou nas salas dos bosses. Indo para a label 'start' (1x).")
            BossFarm.irPara("start")
        end
    end
end)

macro(1000, function()
    if BossFarm.ativo.isOff() then return end
    if not storage.BossAntiTrapTPEnabled then return end

    local myPos = player:getPosition()
    if not myPos then return end

    if myPos.z == 6 and math.abs(myPos.x - 32343) <= 5 and math.abs(myPos.y - 32234) <= 5 then

        if BossFarm.estado ~= "INDO PARA O NPC" and not BossFarm.NPC.ativo and not BossFarm.NPC.concluido then
            BossFarm.logEvento("ALERTA: Caiu no TP acidental! Saindo para a esquerda e retomando rota.")
            BossFarm.estado = "SAINDO DO TP ACIDENTAL"

            g_game.walk(West)
            delay(1500)

            -- farmboss nao conta como "ultima label" aqui: voltar pra ela passava de novo pelo TP (loop).
            -- Sem ultima label valida, vai direto pro 'start' (que retoma do proximo boss pendente).
            local farmboss = storage.BossFarmHorario.labelConfigurado or "farmboss"
            local volta = BossFarm.lastLabel
            if not volta or volta == farmboss then volta = "start" end
            BossFarm.irPara(volta)
        end
    end
end)

function BossFarm.contarTime()
    local party = storage.autoParty or {}
    local meuNome = BossFarm.normalizarNomePlayer(player:getName())
    local nomes, vistos = {}, {}
    local function adicionar(nome)
        nome = BossFarm.normalizarNomePlayer(nome)
        local chave = nome:lower()
        if nome ~= "" and chave ~= "leader" and not vistos[chave] and not BossFarm.nomePlayerIgual(nome, meuNome) then
            vistos[chave] = true
            table.insert(nomes, nome)
        end
    end
    adicionar(party.leaderName)
    for _, nome in ipairs(party.autoPartyList or {}) do adicionar(nome) end
    if #nomes == 0 then return 0, 0 end

    local naParty = (player:getShield() or 0) >= 3
    local juntos = 0
    for _, nome in ipairs(nomes) do
        for _, spec in ipairs(getSpectators()) do
            if spec:isPlayer() and BossFarm.nomePlayerIgual(spec:getName(), nome) then
                if naParty and (spec:getShield() or 0) >= 3 then juntos = juntos + 1 end
                break
            end
        end
    end
    return juntos, #nomes
end

BossFarm.timerNome = ""
function BossFarm.mostrarTimerNome(texto)
    if BossFarm.timerNome == texto then return end
    BossFarm.timerNome = texto
    pcall(function()
        if texto == "" then
            if player.clearTitle then player:clearTitle() else player:setTitle("", "verdana-11px-rounded", "#FFFF00") end
        else
            player:setTitle(texto, "verdana-11px-rounded", "#FFFF00")
        end
    end)
end

macro(1000, function()
    if BossFarm.timerNome ~= "" and os.time() - (BossFarm.esperaTimeUltima or 0) > 3 then
        BossFarm.mostrarTimerNome("")
    end
end)

function BossFarm.aguardarTime()
    local minutos = tonumber((storage.autoParty or {}).esperaTime) or 0
    if minutos <= 0 then return true end
    local juntos, total = BossFarm.contarTime()
    if total == 0 then return true end

    if os.time() - (BossFarm.esperaTimeUltima or 0) > 10 then BossFarm.esperaTimeDesde = nil end
    BossFarm.esperaTimeUltima = os.time()
    BossFarm.esperaTimeDesde = BossFarm.esperaTimeDesde or os.time()
    local passou = os.time() - BossFarm.esperaTimeDesde
    if juntos >= total then
        BossFarm.esperaTimeDesde = nil
        BossFarm.mostrarTimerNome("")
        BossFarm.estado = "TIME REUNIDO! AVANCANDO"
        BossFarm.logEvento("Time reunido (" .. juntos .. "/" .. total .. "). Indo para a rotacao.")
        return true
    end
    if passou >= minutos * 60 then
        BossFarm.esperaTimeDesde = nil
        BossFarm.mostrarTimerNome("")
        BossFarm.estado = "TIME INCOMPLETO! INDO SOZINHO"
        BossFarm.logEvento("Time incompleto (" .. juntos .. "/" .. total .. ") apos " .. minutos .. " min. Fazendo a rotacao sem eles.")
        return true
    end

    local falta = minutos * 60 - passou
    BossFarm.estado = string.format("AGUARDANDO TIME (%d/%d) %02d:%02d", juntos, total, math.floor(falta / 60), falta % 60)
    BossFarm.mostrarTimerNome(string.format("PARTY %02d:%02d (%d/%d)", math.floor(falta / 60), falta % 60, juntos, total))
    delay(1000)
    return "retry"
end

function BossFarm.aguardarMinuto27()
    if storage.BossFarmModeCount == "1X" then return BossFarm.aguardarTime() end

    local min = tonumber(os.date("%M"))
    local sec = tonumber(os.date("%S"))

    if min > 28 or (min == 28 and sec >= 10) then
        BossFarm.estado = "HORARIO 3X ATINGIDO! AVANCANDO"
        return true
    end

    local faltaMin = 28 - min
    local faltaSec = 10 - sec

    if faltaSec < 0 then
        faltaSec = faltaSec + 60
        faltaMin = faltaMin - 1
    end

    BossFarm.estado = string.format("AGUARDANDO 3X (%02dm %02ds)", faltaMin, faltaSec)
    delay(1000)
    return "retry"
end

-- Bank reader embedded in BossFarm. Reuses the client's Bank session and receiver.
-- It neither registers opcode 236 again nor performs financial operations.
function BossFarm.contarHarvestableBank()
    local native = modules and modules.game_bank
    local protocol = g_game.getProtocolGame()
    if not native or not protocol or not g_game.isOnline() then return nil end

    local bridge = native.bossFarmBalanceReader
    if not bridge then
        bridge = {serial = 0}
        native.bossFarmBalanceReader = bridge

        local function validDecimal(value)
            return type(value) == "string" and #value <= 20 and value:match("^%d+$") ~= nil
        end
        local function clean(value)
            value = value:gsub("^0+", "")
            return value == "" and "0" or value
        end
        local function older(a, b)
            a, b = clean(a), clean(b)
            if #a ~= #b then return #a < #b end
            return a < b
        end
        local function add(a, b)
            local out, carry = {}, 0
            for i = 1, math.max(#a, #b) do
                local n = (tonumber(a:sub(-i, -i)) or 0) + (tonumber(b:sub(-i, -i)) or 0) + carry
                table.insert(out, 1, tostring(n % 10))
                carry = math.floor(n / 10)
            end
            if carry > 0 then table.insert(out, 1, tostring(carry)) end
            return clean(table.concat(out))
        end

        function bridge.receive(p, opcode, buffer)
            if p ~= bridge.protocol or opcode ~= 236 or type(buffer) ~= "string" or #buffer > 12000 then return end
            local ok, packet = pcall(json.decode, buffer)
            if not ok or type(packet) ~= "table" or packet.v ~= 1 then return end
            if packet.a == "error" then
                if packet.code == "session" and packet.rid == bridge.requestId then
                    bridge.session, bridge.total, bridge.updated = nil, nil, nil
                    bridge.requestId = nil
                end
                return
            end
            if packet.a ~= "hello" and packet.a ~= "state" and packet.a ~= "operation" and packet.a ~= "status" then return end
            local session = packet.session
            if type(session) ~= "string" or #session > 48 or not session:match("^[%w_-]+$") then return end
            if packet.a == "hello" then
                if bridge.session ~= session then bridge.total, bridge.revision, bridge.updated = nil, nil, nil end
                bridge.session = session
            elseif bridge.session and session ~= bridge.session then
                return
            end
            local state = packet.state
            if type(state) == "table" and state.ready == false then
                bridge.total, bridge.updated, bridge.revision = nil, nil, nil
                return
            end
            if type(state) ~= "table" or state.ready ~= true or state.crystalCid ~= 13201
                or not validDecimal(state.crystal) or not validDecimal(state.cashCrystal)
                or not validDecimal(state.revision) then return end
            if bridge.revision and older(state.revision, bridge.revision) then return end
            bridge.session = session
            local nuggets = add(state.crystal, state.cashCrystal)
            local crystals = #nuggets > 2 and nuggets:sub(1, -3) or "0"
            bridge.total = tonumber(crystals)
            bridge.revision, bridge.updated = state.revision, os.time()
            if packet.rid == bridge.requestId then bridge.requestId = nil end
        end

        function bridge.bind(p)
            if bridge.protocol == p then return true end
            local core = modules and modules.corelib
            local connector = connect or native.connect or (core and core.connect)
            local disconnector = disconnect or native.disconnect or (core and core.disconnect)
            if type(connector) ~= "function" then return false end
            if bridge.protocol and bridge.listener and type(disconnector) == "function" then
                pcall(disconnector, bridge.protocol, {onExtendedOpcode = bridge.listener})
            end
            bridge.protocol = p
            bridge.session, bridge.total, bridge.updated, bridge.revision = nil, nil, nil, nil
            bridge.lastRead, bridge.requestId = nil, nil
            bridge.listener = function(receiver, opcode, buffer)
                pcall(bridge.receive, receiver, opcode, buffer)
            end
            local ok = pcall(connector, p, {onExtendedOpcode = bridge.listener})
            if not ok then bridge.protocol = nil end
            return ok
        end

        function bridge.read()
            local now = os.time()
            if not bridge.lastRead or now < bridge.lastRead or now - bridge.lastRead >= 5 then
                bridge.lastRead = now
                if bridge.session then
                    bridge.serial = bridge.serial + 1
                    bridge.requestId = "BF_" .. tostring(now) .. "_" .. tostring(bridge.serial)
                    local payload = {v = 1, a = "state", session = bridge.session, rid = bridge.requestId}
                    pcall(function() bridge.protocol:sendExtendedOpcode(236, json.encode(payload)) end)
                elseif type(native.show) == "function" and type(native.hide) == "function" then
                    -- Bootstrap through the native module so its private session stays valid.
                    -- Restore the previous visibility immediately, before the next render frame.
                    local root = g_ui.getRootWidget()
                    local window = root and root:getChildById("bankWindow")
                    local visible = window and window:isVisible()
                    pcall(native.show)
                    if not visible then pcall(native.hide) end
                end
            end
            if bridge.session and bridge.updated and now >= bridge.updated and now - bridge.updated <= 10 then
                return bridge.total
            end
            return nil
        end
    end

    if not bridge.bind(protocol) then return nil end
    return bridge.read()
end

function BossFarm.countItem(id)
    local count = 0
    for _, container in pairs(getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item:getId() == id then
                count = count + item:getCount()
            end
        end
    end
    if id == 13201 then
        local ok, total = pcall(BossFarm.contarHarvestableBank)
        if ok and type(total) == "number" and total >= 0 then
            -- O servidor ja soma mochila + banco. Nao somar a mochila duas vezes.
            return math.max(count, total)
        end
        -- Mochila suficiente continua funcionando mesmo enquanto o Bank consulta.
        local precisa = BossFarm.harvNecessario and BossFarm.harvNecessario() or 150
        if count < precisa then return nil end
    end
    return count
end

function BossFarm.horaParaMinutos(hora)
    if type(hora) ~= "string" then return nil end
    local h, m = hora:match("^(%d%d?):(%d%d)$")
    h = tonumber(h)
    m = tonumber(m)
    if not h or not m then return nil end
    if h < 0 or h > 23 or m < 0 or m > 59 then return nil end
    return h * 60 + m
end

function BossFarm.validarHorario(hora)
    return BossFarm.horaParaMinutos(hora) ~= nil
end

BossFarm.VIRADA_DIA = 6 * 60 + 15

function BossFarm.minRel(minutos)
    return (minutos - BossFarm.VIRADA_DIA) % 1440
end

function BossFarm.horaRel(hora)
    local m = BossFarm.horaParaMinutos(hora)
    if not m then return nil end
    return BossFarm.minRel(m)
end

function BossFarm.dataDoDia()
    return os.date("%Y-%m-%d", os.time() - BossFarm.VIRADA_DIA * 60)
end

function BossFarm.horarioNoSS(hora)
    local m = BossFarm.horaParaMinutos(hora)
    if not m then return false end
    return m >= (5 * 60 + 50) and m <= (6 * 60 + 14)
end

function BossFarm.modoHorarioUnico()
    return storage.BossFarmExecutionMode == "ONCE" or storage.BossFarmExecutionMode == "LOOP"
end

function BossFarm.lista3(t, padrao)
    local r = {}
    for i = 1, 3 do
        local v = nil
        if type(t) == "table" then
            v = t[i]
            if v == nil then v = t[tostring(i)] end
        end
        if v == nil then v = padrao end
        r[i] = v
    end
    return r
end

function BossFarm.normalizarStorage()
    local cfg = storage.BossFarmHorario
    cfg.rotacoesAtivas = BossFarm.lista3(cfg.rotacoesAtivas, true)
    for i = 1, 3 do cfg.rotacoesAtivas[i] = cfg.rotacoesAtivas[i] ~= false end
    cfg.horariosUsados = BossFarm.lista3(cfg.horariosUsados, false)
    for i = 1, 3 do cfg.horariosUsados[i] = cfg.horariosUsados[i] == true end
    cfg.janelasPerdidas = BossFarm.lista3(cfg.janelasPerdidas, false)
    for i = 1, 3 do cfg.janelasPerdidas[i] = cfg.janelasPerdidas[i] == true end
    local hor = BossFarm.lista3(cfg.horariosConfigurados, "")
    for i = 1, 3 do hor[i] = tostring(hor[i] or "") end
    cfg.horariosConfigurados = hor
    local conc = {}
    if type(cfg.concluidoEm) == "table" then
        for k, v in pairs(cfg.concluidoEm) do
            local n = tonumber(tostring(k):match("(%d+)"))
            if n and n >= 1 and n <= 3 and type(v) == "string" then conc["s" .. n] = v end
        end
    end
    cfg.concluidoEm = conc
    local usado = {}
    if type(cfg.usadoEm) == "table" then
        for k, v in pairs(cfg.usadoEm) do
            local n = tonumber(tostring(k):match("(%d+)"))
            if n and n >= 1 and n <= 3 and type(v) == "string" then usado["s" .. n] = v end
        end
    end
    cfg.usadoEm = usado
    if type(cfg.historicoRotacoes) ~= "table" then cfg.historicoRotacoes = {} end
    if type(cfg.horariosRotacoes) ~= "table" then cfg.horariosRotacoes = {} end
    if cfg.indiceRotacaoAtual ~= nil and type(cfg.indiceRotacaoAtual) ~= "number" then
        cfg.indiceRotacaoAtual = tonumber(cfg.indiceRotacaoAtual)
    end
end

function BossFarm.inicioDiaTs()
    local d = os.date("*t", os.time() - BossFarm.VIRADA_DIA * 60)
    d.hour, d.min, d.sec = 6, 15, 0
    return os.time(d)
end

function BossFarm.slotLiberado(i)
    local cfg = storage.BossFarmHorario
    if not cfg.salvoEm then return true end
    local rel = BossFarm.horaRel(cfg.horariosConfigurados[i])
    if not rel then return false end
    -- vale se foi salvo antes do fim da janela (minuto do horario + 5 min de carencia)
    return BossFarm.inicioDiaTs() + (rel + 5) * 60 + 59 >= cfg.salvoEm
end

function BossFarm.aplicarModoUnico()
    local cfg = storage.BossFarmHorario
    if not cfg or not cfg.rotacoesAtivas then return end
    if BossFarm.modoHorarioUnico() then
        if not cfg.ativasSalvas then
            cfg.ativasSalvas = {cfg.rotacoesAtivas[2] ~= false, cfg.rotacoesAtivas[3] ~= false}
        end
        cfg.rotacoesAtivas[2] = false
        cfg.rotacoesAtivas[3] = false
    elseif cfg.ativasSalvas then
        cfg.rotacoesAtivas[2] = cfg.ativasSalvas[1] ~= false
        cfg.rotacoesAtivas[3] = cfg.ativasSalvas[2] ~= false
        cfg.ativasSalvas = nil
    end
end

function BossFarm.slotUsado(i)
    local cfg = storage.BossFarmHorario
    if not (cfg.horariosUsados and cfg.horariosUsados[i]) then return false end
    return type(cfg.usadoEm) == "table" and cfg.usadoEm["s" .. i] == BossFarm.dataDoDia()
end

function BossFarm.marcarSlot(i)
    local cfg = storage.BossFarmHorario
    if type(cfg.usadoEm) ~= "table" then cfg.usadoEm = {} end
    cfg.horariosUsados = BossFarm.lista3(cfg.horariosUsados, false)
    cfg.horariosUsados[i] = true
    cfg.usadoEm["s" .. i] = BossFarm.dataDoDia()
end

function BossFarm.inicializarHorario()
    local hoje = BossFarm.dataDoDia()
    local cfg = storage.BossFarmHorario
    if not BossFarm.storageOk then
        BossFarm.normalizarStorage()
        BossFarm.storageOk = true
        BossFarm.aplicarModoUnico()
    end

    cfg.horariosConfigurados = cfg.horariosConfigurados or {
        BossFarm.HorariosPadrao[1],
        BossFarm.HorariosPadrao[2],
        BossFarm.HorariosPadrao[3]
    }

    cfg.rotacoesAtivas = cfg.rotacoesAtivas or {true, true, true}
    cfg.labelConfigurado = cfg.labelConfigurado or "farmboss"
    cfg.labelPosNpc = cfg.labelPosNpc or "saida cave"

    if cfg.data ~= hoje then
        cfg.data = hoje
        storage.BossFarmNPCList = storage.BossFarmNPCList or {}
        for i = 1, 15 do storage.BossFarmNPCList[i] = false end
        if BossFarm.syncCheckboxes then BossFarm.syncCheckboxes() end
        if BossFarm.logEvento then BossFarm.logEvento("Novo dia (06:15): rotacoes, horarios e aba NPC zerados.") end
        cfg.rotacoesFeitas = 0
        cfg.horariosUsados = {false, false, false}
        cfg.janelasPerdidas = {false, false, false}
        cfg.usadoEm = {}
        cfg.concluidoEm = {}
        cfg.horariosRotacoes = {}
        cfg.historicoRotacoes = {}
        cfg.rotacaoEmAndamento = false
        cfg.horaRotacaoAtual = nil
        cfg.indiceRotacaoAtual = nil
        cfg.inicioRotacaoTs = nil
        cfg.dataRotacao = nil
    else
        if (cfg.rotacoesFeitas or 0) > 0 and cfg.feitasData ~= hoje then
            cfg.rotacoesFeitas = 0
            cfg.historicoRotacoes = {}
            cfg.horariosRotacoes = {}
        end
        cfg.rotacoesFeitas = cfg.rotacoesFeitas or 0
        cfg.horariosUsados = cfg.horariosUsados or {false, false, false}
        cfg.janelasPerdidas = cfg.janelasPerdidas or {false, false, false}
        cfg.horariosRotacoes = cfg.horariosRotacoes or {}
        cfg.historicoRotacoes = cfg.historicoRotacoes or {}
        cfg.rotacaoEmAndamento = cfg.rotacaoEmAndamento or false
    end
end

BossFarm.inicializarHorario()

do
    local cfg = storage.BossFarmHorario
    local hist = cfg.historicoRotacoes or {}
    for i = #hist, 1, -1 do
        if tostring(hist[i]):find("morte/net", 1, true) then
            table.remove(hist, i)
            cfg.rotacoesFeitas = math.max(0, (cfg.rotacoesFeitas or 0) - 1)
        end
    end
    for idx in pairs(cfg.rotacoesInterrompidas or {}) do
        local n = tonumber(idx)
        if n and cfg.horariosUsados then cfg.horariosUsados[n] = false end
    end
    cfg.rotacoesInterrompidas, cfg.limpezaPendente, cfg.manterMarcacoes = nil, nil, nil
    cfg.ultimaAtividade, cfg.rotacoesCompletas = nil, nil
end

function BossFarm.syncCheckboxes()
    if not bossFarmWindow then return end

    local npcTodosMarcados = true
    for i = 1, 15 do
        local cbReal = bossFarmWindow.npcListPanel:getChildById("npcCb" .. i)
        if cbReal then cbReal:setChecked(storage.BossFarmNPCList[i] or false) end

        if not storage.BossFarmNPCList[i] then
            npcTodosMarcados = false
        end

        local cbCust = bossFarmWindow.customListPanel:getChildById("customCb" .. i)
        if cbCust then cbCust:setChecked(storage.BossFarmCustomList[i] or false) end
    end

    if bossFarmWindow.npcSelectAllButton then
        if npcTodosMarcados then
            bossFarmWindow.npcSelectAllButton:setText("DESMARCAR TODOS")
            bossFarmWindow.npcSelectAllButton:setColor("#FF3333")
        else
            bossFarmWindow.npcSelectAllButton:setText("MARCAR TODOS")
            bossFarmWindow.npcSelectAllButton:setColor("#00FF00")
        end
    end
end

function BossFarm.iniciarNovaRotacao()
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    cfg.rotacaoEmAndamento = true
    cfg.inicioRotacaoTs = os.time()
    cfg.dataRotacao = BossFarm.dataDoDia()

    if BossFarm.modoHorarioUnico() then
        cfg.indiceRotacaoAtual = 1
    elseif not cfg.horaRotacaoAtual then
        for i = 1, 3 do
            if not BossFarm.slotUsado(i) then
                cfg.indiceRotacaoAtual = i
                break
            end
        end
    end

    for i = 1, 15 do storage.BossFarmNPCList[i] = false end
    BossFarm.syncCheckboxes()

    BossFarm.currentBoss = nil
    BossFarm.entrou = false
    BossFarm.derrotou = false
    BossFarm.teleportado = false
    BossFarm.tentativaEntrada = 0
    BossFarm.esperandoEntrada = false
    BossFarm.tempoPasso = 0
    BossFarm.passagem = {}
    BossFarm.pendente = {}
    BossFarm.buscandoPendente = false
    BossFarm.pendenteAtual = nil
    BossFarm.jaDerrotadoDetectado = false
    BossFarm.lastLabel = nil
    BossFarm.dentroDaSala = nil

    BossFarm.NPC.ativo = false
    BossFarm.NPC.concluido = false
    BossFarm.NPC.etapa = 0
    BossFarm.NPC.tentativa = 0
    BossFarm.logEvento("Nova cacada iniciada! Memoria da Rotacao resetada.")
    return true
end

function BossFarm.salvarHorarios(h1, h2, h3, labelDestino, labelPosNpc)
    BossFarm.inicializarHorario()
    local horarios = {h1, h2, h3}
    local label = tostring(labelDestino or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local labelPos = tostring(labelPosNpc or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if label == "" then return false, "Label ida vazia" end
    if labelPos == "" then return false, "Label volta vazia" end

    local ativas = storage.BossFarmHorario.rotacoesAtivas

    for i = 1, 3 do
        local hText = (horarios[i] or ""):gsub("%s+", "")
        local usado = not (BossFarm.modoHorarioUnico() and i >= 2)
        if usado and ativas[i] ~= false and hText ~= "" then
            if not BossFarm.validarHorario(hText) then
                return false, "O Horario " .. i .. " esta invalido! Use o padrao de 24h (HH:MM)."
            end
            if BossFarm.horarioNoSS(hText) then
                return false, "O Horario " .. i .. " cai no SS (05:50 ate 06:14). Escolha outro."
            end
        end
    end

    local antigos = storage.BossFarmHorario.horariosConfigurados or {}
    local horarioAntigo = {antigos[1], antigos[2], antigos[3]}
    storage.BossFarmHorario.horariosConfigurados = {h1, h2, h3}

    for i = 1, 3 do
        local hText = (horarios[i] or ""):gsub("%s+", "")
        if BossFarm.validarHorario(hText) then
            local hh, mm = hText:match("^(%d%d?):(%d%d)$")
            storage.BossFarmHorario.horariosConfigurados[i] = string.format("%02d:%02d", tonumber(hh), tonumber(mm))
        else
            storage.BossFarmHorario.horariosConfigurados[i] = horarios[i]
        end
    end

    storage.BossFarmHorario.labelConfigurado = label
    storage.BossFarmHorario.labelPosNpc = labelPos
    local cfg = storage.BossFarmHorario
    local idx = cfg.indiceRotacaoAtual
    if cfg.rotacaoEmAndamento and idx and cfg.horariosConfigurados[idx] ~= horarioAntigo[idx] then
        cfg.rotacaoEmAndamento = false
        cfg.horaRotacaoAtual = nil
        cfg.indiceRotacaoAtual = nil
        if cfg.horariosUsados then cfg.horariosUsados[idx] = false end
        if cfg.usadoEm then cfg.usadoEm["s" .. idx] = nil end
        BossFarm.passeAte = 0
        BossFarm.logEvento("Horario da Rotacao " .. idx .. " mudou: rotacao em andamento cancelada e passe apagado.")
    end
    if not cfg.rotacaoEmAndamento then
        cfg.salvoEm = os.time()
        for i = 1, 3 do
            if cfg.janelasPerdidas and cfg.janelasPerdidas[i] then
                cfg.janelasPerdidas[i] = false
                cfg.horariosUsados[i] = false
                if cfg.usadoEm then cfg.usadoEm["s" .. i] = nil end
            end
        end
    end
    BossFarm.aplicarModoUnico()
    return true
end

function BossFarm.registrarRotacao(indiceHorario)
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    local qtd = cfg.rotacoesFeitas or 0

    local maxRots = storage.BossFarmExecutionMode == "ONCE" and 1 or 3
    if qtd >= maxRots or cfg.rotacaoEmAndamento then return end

    BossFarm.marcarSlot(indiceHorario)
    cfg.janelasPerdidas = cfg.janelasPerdidas or {false, false, false}
    cfg.janelasPerdidas[indiceHorario] = false
    cfg.horaRotacaoAtual = os.date("%H:%M")
    cfg.indiceRotacaoAtual = indiceHorario

    BossFarm.iniciarNovaRotacao()
end

function BossFarm.registrarJanelaPerdida(indiceHorario)
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    BossFarm.marcarSlot(indiceHorario)
    cfg.janelasPerdidas = cfg.janelasPerdidas or {false, false, false}
    cfg.janelasPerdidas[indiceHorario] = true
    BossFarm.logEvento("Horario da Rotacao " .. indiceHorario .. " expirou. Janela marcada como PERDIDA.")
end

function BossFarm.finalizarRotacao()
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    local maxRots = storage.BossFarmExecutionMode == "ONCE" and 1 or 3

    if (cfg.rotacoesFeitas or 0) < maxRots then
        cfg.rotacoesFeitas = (cfg.rotacoesFeitas or 0) + 1
        cfg.feitasData = BossFarm.dataDoDia()

        local feito = nil
        if BossFarm.modoHorarioUnico() then
            BossFarm.marcarSlot(1)
            feito = 1
        elseif not cfg.horaRotacaoAtual then
            for i = 1, 3 do
                if not BossFarm.slotUsado(i) then
                    BossFarm.marcarSlot(i)
                    feito = i
                    break
                end
            end
        else
            feito = cfg.indiceRotacaoAtual
        end
        if feito then
            if type(cfg.concluidoEm) ~= "table" then cfg.concluidoEm = {} end
            cfg.concluidoEm["s" .. feito] = BossFarm.dataDoDia()
        end

        cfg.historicoRotacoes = cfg.historicoRotacoes or {}
        local tipoStr = storage.BossFarmRotationType == "9BOSS" and "9 Bosses" or (storage.BossFarmRotationType == "CUSTOM" and "Custom" or "15 Bosses")
        table.insert(cfg.historicoRotacoes, tipoStr)

        cfg.horariosRotacoes = cfg.horariosRotacoes or {}
        table.insert(cfg.horariosRotacoes, cfg.horaRotacaoAtual or os.date("%H:%M"))
    end

    cfg.horaRotacaoAtual = nil
    cfg.indiceRotacaoAtual = nil
    cfg.rotacaoEmAndamento = false
    BossFarm.lastLabel = nil

    if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
end

function BossFarm.verificarHorario()
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    if not BossFarm.ativo or BossFarm.ativo.isOff() then return true end
    if cfg.rotacaoEmAndamento and storage.BossFarmExecutionMode == "LOOP" then
        cfg.rotacaoEmAndamento = false
        cfg.horaRotacaoAtual = nil
        cfg.indiceRotacaoAtual = nil
        cfg.janelasPerdidas = cfg.janelasPerdidas or {false, false, false}
        cfg.janelasPerdidas[1] = true
        BossFarm.marcarSlot(1)
        BossFarm.passeAte = 0
        BossFarm.estado = "ROTACAO 1 PERDIDA (" .. (cfg.rotacoesFeitas or 0) .. "/3)"
        BossFarm.logEvento("Checkin: voltou para a hunt sem terminar o loop (morte/queda). Rotacao 1 PERDIDA, nao puxa mais hoje.")
        return true
    end
    if cfg.rotacaoEmAndamento then
        local velha = not cfg.inicioRotacaoTs
            or (cfg.dataRotacao and cfg.dataRotacao ~= BossFarm.dataDoDia())
            or os.time() - cfg.inicioRotacaoTs > 3 * 3600
        -- rotacao desligada no painel (Rotacao 1/2/3) nao pode ser retomada
        local idx = cfg.indiceRotacaoAtual
        local desligada = idx and cfg.rotacoesAtivas and cfg.rotacoesAtivas[idx] == false
        if velha or desligada then
            cfg.rotacaoEmAndamento = false
            cfg.horaRotacaoAtual = nil
            cfg.indiceRotacaoAtual = nil
            if desligada then
                BossFarm.logEvento("Rotacao " .. idx .. " esta DESATIVADA: nao vai retomar, rotacao em andamento liberada.")
            else
                BossFarm.logEvento("Rotacao antiga que ficou travada 'em andamento' foi liberada.")
            end
        else
            local destino = cfg.labelConfigurado or "farmboss"
            BossFarm.estado = "RETOMANDO ROTACAO " .. tostring(cfg.indiceRotacaoAtual or "")
            BossFarm.logEvento("Checkin: a rotacao ainda nao saiu da cave. Indo de novo para: " .. destino)
            BossFarm.darPasse()
            BossFarm.irPara(destino)
            return "retry"
        end
    end

    local maxRots = storage.BossFarmExecutionMode == "ONCE" and 1 or 3

    if (cfg.rotacoesFeitas or 0) >= maxRots then
        if storage.BossFarmExecutionMode == "ONCE" then
            BossFarm.estado = "1 ROTACAO CONCLUIDA NO DIA"
        else
            BossFarm.estado = "3 ROTACOES CONCLUIDAS NO DIA"
        end
        return true
    end

    if storage.BossFarmVipExpiration and storage.BossFarmVipExpiration > 0 then
        local tempoRestante = storage.BossFarmVipExpiration - os.time()
        if tempoRestante < (10 * 86400) then
            BossFarm.estado = "ERRO: VIP < 10 DIAS!"
            if os.time() - (BossFarm.lastVipWarn or 0) >= 3 then
                local diasFaltando = math.max(0, math.floor(tempoRestante / 86400))
                BossFarm.logEvento("ERRO DE SEGURANCA: Tempo VIP insuficiente (" .. diasFaltando .. " dias restantes). E necessario ter 10 dias ou mais.")
                BossFarm.lastVipWarn = os.time()
            end
            delay(1000)
            return true
        end
    end

    local agora = os.date("*t")
    local agoraMin = BossFarm.minRel(agora.hour * 60 + agora.min)

    if storage.BossFarmExecutionMode == "LOOP" or storage.BossFarmExecutionMode == "ONCE" then

        if cfg.rotacoesAtivas and cfg.rotacoesAtivas[1] == false then
            BossFarm.estado = "ERRO: ROTACAO 1 DESATIVADA"
            return true
        end

        local slotValido = nil
        for i = 1, 1 do
            if cfg.rotacoesAtivas and cfg.rotacoesAtivas[i] == false then

            elseif not BossFarm.slotUsado(i) then
                if BossFarm.validarHorario(cfg.horariosConfigurados[i]) then
                    local inicio = BossFarm.horaRel(cfg.horariosConfigurados[i])
                    local fim = inicio + 5
                    if inicio and agoraMin >= inicio and agoraMin <= fim and BossFarm.slotLiberado(i) then
                        slotValido = i
                        break
                    end
                end
            end
        end

        if slotValido then
            local qtdNecessaria = (storage.BossFarmRotationType == "9BOSS") and 90 or 150
            if storage.BossFarmRotationType == "CUSTOM" then
                local ativos = BossFarm.getActiveBosses()
                if #ativos == 0 then
                    BossFarm.estado = "ERRO: CUSTOM VAZIO!"
                    delay(1000)
                    return true
                end
                qtdNecessaria = #ativos * 10
            end

            local hwCount = BossFarm.countItem(13201)
            if hwCount == nil and not BossFarm.modoGratis() then
                BossFarm.estado = "AGUARDANDO SALDO DO BANK"
                delay(1000)
                return true
            end
            if hwCount ~= nil and hwCount < qtdNecessaria and not BossFarm.modoGratis() then
                BossFarm.estado = "FALTA HARVESTABLE! (" .. hwCount .. "/" .. qtdNecessaria .. ")"
                if os.time() - (BossFarm.lastHwWarn or 0) >= 3 then
                    BossFarm.logEvento("ERRO: Rotacao travada! Faltam Harvestables (" .. hwCount .. "/" .. qtdNecessaria .. ")")
                    BossFarm.lastHwWarn = os.time()
                end
                delay(1000)
                return true
            end

            BossFarm.estado = "INICIANDO ROTACAO " .. slotValido
            BossFarm.registrarRotacao(slotValido)

            local destino = cfg.labelConfigurado or "farmboss"
            BossFarm.logEvento("Engatando rotacao " .. slotValido .. ". Indo para: " .. destino)
            BossFarm.darPasse()
            BossFarm.irPara(destino)
            return "retry"
        else
            for i = 1, 1 do
                if cfg.rotacoesAtivas and cfg.rotacoesAtivas[i] ~= false and not BossFarm.slotUsado(i) then
                    local inicio = BossFarm.horaRel(cfg.horariosConfigurados[i])
                    if inicio and agoraMin > (inicio + 5) then
                        BossFarm.registrarJanelaPerdida(i)
                    end
                end
            end
            local inicio1 = BossFarm.horaRel(cfg.horariosConfigurados[1])
            if inicio1 and BossFarm.slotUsado(1) and agoraMin >= inicio1 and agoraMin <= inicio1 + 5 then
                BossFarm.estado = "ROTACAO 1 " .. ((cfg.janelasPerdidas and cfg.janelasPerdidas[1]) and "PERDIDA HOJE" or "JA FEITA HOJE")
            else
                BossFarm.estado = "AGUARDANDO " .. tostring(cfg.horariosConfigurados[1] or "")
            end
            return true
        end
    end

    local proximoInicio, proximoTexto = nil, nil
    for i = 1, 3 do
        if cfg.rotacoesAtivas and cfg.rotacoesAtivas[i] == false then

        else
            if not BossFarm.slotUsado(i) then
                local inicio = BossFarm.horaRel(cfg.horariosConfigurados[i])
                if inicio then
                    local fim = inicio + 5
                    if agoraMin >= inicio and agoraMin <= fim and BossFarm.slotLiberado(i) then

                        local qtdNecessaria = (storage.BossFarmRotationType == "9BOSS") and 90 or 150
                        if storage.BossFarmRotationType == "CUSTOM" then
                            local ativos = BossFarm.getActiveBosses()
                            if #ativos == 0 then
                                BossFarm.estado = "ERRO: CUSTOM VAZIO!"
                                delay(1000)
                                return true
                            end
                            qtdNecessaria = #ativos * 10
                        end

                        local hwCount = BossFarm.countItem(13201)
                        if hwCount == nil then
                            BossFarm.estado = "AGUARDANDO SALDO DO BANK"
                            delay(1000)
                            return true
                        end
                        if hwCount < qtdNecessaria then
                            BossFarm.estado = "FALTA HARVESTABLE! (" .. hwCount .. "/" .. qtdNecessaria .. ")"
                            if os.time() - (BossFarm.lastHwWarn or 0) >= 3 then
                                BossFarm.logEvento("ERRO: Rotacao travada! Faltam Harvestables (" .. hwCount .. "/" .. qtdNecessaria .. ")")
                                BossFarm.lastHwWarn = os.time()
                            end
                            delay(1000)
                            return true
                        end

                        BossFarm.estado = "JANELA " .. cfg.horariosConfigurados[i]
                        BossFarm.registrarRotacao(i)

                        local destino = cfg.labelConfigurado or "farmboss"
                        BossFarm.logEvento("Horario atingido! Iniciando e indo para a label: " .. destino)
                        BossFarm.darPasse()
                        BossFarm.irPara(destino)
                        return "retry"
                    end
                    if agoraMin > fim then
                        BossFarm.registrarJanelaPerdida(i)
                    elseif not proximoInicio or inicio < proximoInicio then
                        proximoInicio = inicio
                        proximoTexto = cfg.horariosConfigurados[i]
                    end
                end
            end
        end
    end
    for i = 1, 3 do
        local inicio = BossFarm.horaRel(cfg.horariosConfigurados[i])
        if inicio and agoraMin >= inicio and agoraMin <= inicio + 5 and BossFarm.slotUsado(i) then
            BossFarm.estado = "ROTACAO " .. i .. ((cfg.janelasPerdidas and cfg.janelasPerdidas[i]) and " PERDIDA HOJE" or " JA FEITA HOJE")
            return true
        end
    end
    if proximoTexto then
        BossFarm.estado = "AGUARDANDO " .. proximoTexto
        return true
    end
    BossFarm.estado = "AGUARDANDO"
    return true
end

function BossFarm.aguardarHorarioInicio()
    BossFarm.inicializarHorario()
    local cfg = storage.BossFarmHorario
    if not BossFarm.ativo or BossFarm.ativo.isOff() then return true end

    local agora = os.date("*t")
    local agoraMin = BossFarm.minRel(agora.hour * 60 + agora.min)
    local horarioAlvoMin = nil
    local ultimoSlot = BossFarm.modoHorarioUnico() and 1 or 3

    for i = 1, ultimoSlot do
        if cfg.rotacoesAtivas and cfg.rotacoesAtivas[i] ~= false then
            if cfg.horariosConfigurados[i] then
                local inicioMin = BossFarm.horaRel(cfg.horariosConfigurados[i])
                if inicioMin then
                    if agoraMin >= inicioMin and agoraMin <= (inicioMin + 5) then
                        horarioAlvoMin = inicioMin
                        break
                    end
                end
            end
        end
    end

    if not horarioAlvoMin then return true end

    if agoraMin < horarioAlvoMin then
        local faltaMin = horarioAlvoMin - agoraMin
        BossFarm.estado = "AGUARDANDO HORARIO (" .. faltaMin .. "m restantes)"
        delay(1000)
        return "retry"
    end

    BossFarm.estado = "ROTACAO INICIADA"
    return true
end

function BossFarm.harvNecessario()
    if storage.BossFarmRotationType == "9BOSS" then return 90 end
    if storage.BossFarmRotationType == "CUSTOM" then return #BossFarm.getActiveBosses() * 10 end
    return 150
end

BossFarm.textoNome = ""
function BossFarm.textoAcimaDoNome()
    if BossFarm.ativo.isOff() or not storage.BossFarmAvisoNome then return "" end
    local avisos = {}
    local vip = storage.BossFarmVipExpiration or 0
    if vip > 0 then
        local dias = math.floor((vip - os.time()) / 86400)
        if dias < 0 then
            table.insert(avisos, "SEM VIP")
        elseif vip - os.time() < 10 * 86400 then
            table.insert(avisos, "VIP " .. dias .. " DIAS (PRECISA 10)")
        end
    end
    if not BossFarm.modoGratis() then
        local tem, precisa = BossFarm.countItem(13201), BossFarm.harvNecessario()
        if tem ~= nil and tem < precisa then
            table.insert(avisos, "FALTA HARVESTABLE " .. tem .. "/" .. precisa)
        end
    end
    return table.concat(avisos, " | ")
end

function BossFarm.mostrarAcimaDoNome(texto)
    pcall(function() player:setText(texto, "#FF4040") end)
end

function BossFarm.limparAvisoNome()
    local ok, visivel = pcall(function() return player:getText() end)
    if ok and type(visivel) == "string" then
        local nosso = (BossFarm.textoNome ~= "" and visivel == BossFarm.textoNome)
            or visivel:find("FALTA HARVESTABLE", 1, true)
            or visivel:find("SEM VIP", 1, true)
            or visivel:match("VIP %d+ DIAS %(PRECISA 10%)")
        if nosso then BossFarm.mostrarAcimaDoNome("") end
    elseif BossFarm.textoNome ~= "" then
        BossFarm.mostrarAcimaDoNome("")
    end
end

function BossFarm.atualizarAvisoNome()
    local ok, texto = pcall(BossFarm.textoAcimaDoNome)
    if not ok then texto = "" end
    if texto == "" then BossFarm.limparAvisoNome() end
    BossFarm.textoNome = texto
end

-- O texto do Creature persiste entre recargas, mesmo quando textoNome foi zerado.
BossFarm.limparAvisoNome()
macro(1000, BossFarm.atualizarAvisoNome)

macro(100, function()
    if BossFarm.textoNome ~= "" then BossFarm.mostrarAcimaDoNome(BossFarm.textoNome) end
end)

BossFarm.nome = {
    "Ophidian Horror", "Heart of Havoc", "Widow of Dusk", "Corrupted Grovekeeper", "Hive of Blight",
    "Chillrend Titan", "Soulbinder Knight", "Umbracrypt Hierophant", "Cryomancer Eternal", "Doomhammer Sentinel",
    "Maw of Madness", "Decayroot Beast", "Shattered Beholder", "Oathbreaker Witchlord", "Oblivion Winged Fiend"
}

BossFarm.nomeMap = {}
for _, nomeBoss in ipairs(BossFarm.nome) do
    BossFarm.nomeMap[nomeBoss:lower()] = true
end

BossFarm.label = {
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "boss6", "boss7", "boss8", "boss9", "boss10",
    "boss11", "boss12", "boss13", "boss14", "boss15"
}

BossFarm.direcao = {
    South, East, East, East, North, North, North, North, West, West,
    West, South, South, South, South
}

BossFarm.salasCantos = {
    [1]  = { {7773,1425,3}, {7776,1425,3}, {7773,1434,3}, {7776,1434,3} },
    [2]  = { {7694,1274,5}, {7693,1279,5}, {7703,1272,5}, {7704,1279,5} },
    [3]  = { {7942,1293,2}, {7947,1294,2}, {7941,1296,2}, {7947,1296,2} },
    [4]  = { {7933,1141,4}, {7935,1141,4}, {7932,1147,4}, {7937,1148,4} },
    [5]  = { {7933,1213,4}, {7937,1213,4}, {7933,1205,4}, {7938,1206,4} },
    [6]  = { {7773,1362,2}, {7777,1362,2}, {7778,1365,2}, {7773,1365,2} },
    [7]  = { {7695,1197,4}, {7703,1197,4}, {7695,1204,4}, {7703,1204,4} },
    [8]  = { {7843,1112,5}, {7845,1112,5}, {7845,1119,5}, {7843,1119,5} },
    [9]  = { {7804,1222,3}, {7805,1222,3}, {7804,1230,3}, {7807,1230,3} },
    [10] = { {7636,1130,3}, {7636,1138,3}, {7643,1138,3}, {7640,1130,3} },
    [11] = { {7794,1116,4}, {7794,1119,4}, {7800,1119,4}, {7801,1116,4} },
    [12] = { {7935,1381,4}, {7941,1381,4}, {7941,1392,4}, {7931,1389,4} },
    [13] = { {7703,1154,4}, {7705,1154,4}, {7705,1145,4}, {7703,1145,4} },
    [14] = { {7791,1273,4}, {7793,1274,4}, {7791,1278,4}, {7793,1278,4} },
    [15] = { {7697,1347,5}, {7698,1347,5}, {7695,1354,5}, {7698,1355,5} },
}

BossFarm.salas = {}
for boss, cantos in pairs(BossFarm.salasCantos) do
    local s = { x1 = math.huge, x2 = -math.huge, y1 = math.huge, y2 = -math.huge, z = cantos[1][3] }
    for _, c in ipairs(cantos) do
        s.x1 = math.min(s.x1, c[1]); s.x2 = math.max(s.x2, c[1])
        s.y1 = math.min(s.y1, c[2]); s.y2 = math.max(s.y2, c[2])
    end
    BossFarm.salas[boss] = s
end

function BossFarm.salaDaPosicao(p)
    if not p then return nil end
    for boss, s in pairs(BossFarm.salas) do
        if p.z == s.z and p.x >= s.x1 and p.x <= s.x2 and p.y >= s.y1 and p.y <= s.y2 then
            return boss
        end
    end
    return nil
end

function BossFarm.bossDoContexto()
    local sala = BossFarm.salaDaPosicao(player:getPosition())
    if sala then return sala end
    if BossFarm.ultimoBossVisto and (os.time() - (BossFarm.ultimoBossVistoTime or 0)) <= 15 then
        return BossFarm.ultimoBossVisto
    end
    if BossFarm.dentroDaSala then return BossFarm.dentroDaSala end
    return BossFarm.currentBoss
end

macro(200, function()
    if BossFarm.ativo.isOff() then return end
    local sala = BossFarm.salaDaPosicao(player:getPosition())
    if not sala or BossFarm.dentroDaSala == sala then return end
    if BossFarm.currentBoss == sala and BossFarm.teleportado then return end

    if BossFarm.currentBoss ~= sala then
        BossFarm.setCurrent(sala)
    else
        BossFarm.resetBoss()
    end
    BossFarm.entrou = true
    BossFarm.dentroDaSala = sala
    BossFarm.estado = "DENTRO DA BOSS ROOM"
    BossFarm.logEvento("Entrada detectada no Boss " .. sala .. " (" .. BossFarm.nome[sala] .. ") pela posicao.")
    if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
end)

function BossFarm.getActiveBosses()
    if storage.BossFarmRotationType == "9BOSS" then
        return {1, 2, 3, 4, 5, 6, 7, 9, 10}
    elseif storage.BossFarmRotationType == "CUSTOM" then
        local ativos = {}
        for i = 1, 15 do
            if storage.BossFarmCustomList[i] then
                table.insert(ativos, i)
            end
        end
        return ativos
    else
        return {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
    end
end

function BossFarm.proximoBoss(bossAtual)
    local ativos = BossFarm.getActiveBosses()
    local inicio = bossAtual or 0
    for _, b in ipairs(ativos) do
        if b > inicio then

            if not storage.BossFarmNPCList[b] then
                return b
            end
        end
    end
    return nil
end

function BossFarm.proximoPendente()
    local ativos = BossFarm.getActiveBosses()
    for _, i in ipairs(ativos) do
        if not storage.BossFarmNPCList[i] then
            return i
        end
    end
    return nil
end

function BossFarm.checarProximoCustom(bossAtual)
    local ativos = BossFarm.getActiveBosses()
    if #ativos == 0 then
        BossFarm.logEvento("ERRO: Nenhum boss ativo na lista da rotacao!")
        return true
    end

    local proximo = BossFarm.proximoBoss(bossAtual)

    if proximo then
        if bossAtual then
            BossFarm.logEvento("Pulo Inteligente: Indo para o Boss " .. proximo)
        else
            BossFarm.logEvento("Buscando rota... Engatando direto no Boss " .. proximo)
        end
        BossFarm.irPara(BossFarm.label[proximo])
        return "retry"
    else
        BossFarm.logEvento("Todos os bosses do ciclo ja estao derrotados! Finalizando o ciclo.")
        BossFarm.checarPendentesFinal()
        return "retry"
    end
end

function BossFarm.logEvento(texto)
    BossFarm.ultimoEvento = texto
    BossFarm.ultimoEventoTime = os.date("%H:%M:%S")
    print("[Boss Farm] " .. texto)
end

if BossFarm.modoSeparado() then BossFarm.instalarCaveBoss() end

function BossFarm.setCurrent(boss)
    if BossFarm.currentBoss ~= boss then
        BossFarm.currentBoss = boss
        BossFarm.voltasPorta = 0
        BossFarm.entrou = false
        BossFarm.derrotou = false
        BossFarm.teleportado = false
        BossFarm.tentativaEntrada = 0
        BossFarm.esperandoEntrada = false
        BossFarm.tempoPasso = 0
        BossFarm.jaDerrotadoDetectado = false
        if BossFarm.passagem[boss] == nil then
            BossFarm.passagem[boss] = 1
        end
    end
end

function BossFarm.resetBoss()
    BossFarm.entrou = false
    BossFarm.derrotou = false
    BossFarm.teleportado = false
    BossFarm.tentativaEntrada = 0
    BossFarm.esperandoEntrada = false
    BossFarm.tempoPasso = 0
end

function BossFarm.marcarPendente(boss)
    BossFarm.pendente[boss] = true
    BossFarm.passagem[boss] = 1
    BossFarm.estado = "BOSS " .. boss .. " PENDENTE"
end

function BossFarm.checarPendentesFinal()
    local pendente = BossFarm.proximoPendente()
    if pendente then
        BossFarm.iniciarPendentes()
    else
        BossFarm.finalizarCiclo()
    end
end

function BossFarm.finalizarCiclo()

    if BossFarm.modoGratis() then
        BossFarm.irParaSaidaGratis()
        return
    end

    BossFarm.buscandoPendente = false
    BossFarm.pendenteAtual = nil
    BossFarm.estado = "INDO PARA O NPC"
    BossFarm.irPara("npc")
end

function BossFarm.iniciarPendentes()
    local boss = BossFarm.proximoPendente()
    if not boss then
        BossFarm.finalizarCiclo()
        return
    end
    BossFarm.buscandoPendente = true
    BossFarm.pendenteAtual = boss
    BossFarm.passagem[boss] = 2
    BossFarm.currentBoss = nil
    BossFarm.resetBoss()
    BossFarm.estado = "2a PASSAGEM - BOSS " .. boss
    BossFarm.irPara(BossFarm.label[boss])
end

function BossFarm.concluirPendente(boss)
    BossFarm.pendente[boss] = false
    BossFarm.estado = "BOSS " .. boss .. " CONCLUIDO"
    local proximo = BossFarm.proximoPendente()
    if proximo then
        BossFarm.buscandoPendente = true
        BossFarm.pendenteAtual = proximo
        BossFarm.passagem[proximo] = 2
        BossFarm.currentBoss = nil
        BossFarm.resetBoss()
        BossFarm.estado = "PROXIMO PENDENTE - BOSS " .. proximo
        BossFarm.irPara(BossFarm.label[proximo])
    else
        BossFarm.finalizarCiclo()
    end
end

function BossFarm.aplicarTrocaRotacao()
    if not BossFarm.ativo or BossFarm.ativo.isOff() or BossFarm.NPC.ativo then return end
    if BossFarm.dentroDaSala or BossFarm.salaDaPosicao(player:getPosition()) then return end
    if #BossFarm.getActiveBosses() == 0 then return end
    local ultima = tostring(BossFarm.lastLabel or "")
    local alvo = tonumber(ultima:match("^boss(%d+)$"))
    if not alvo and ultima ~= "npc" then return end
    local proximo = BossFarm.proximoPendente()
    if proximo == alvo then return end
    if not proximo and ultima == "npc" then return end
    BossFarm.currentBoss = nil
    BossFarm.resetBoss()
    BossFarm.buscandoPendente = false
    BossFarm.pendenteAtual = nil
    if proximo then
        BossFarm.estado = "TROCA MANUAL - BOSS " .. proximo
        BossFarm.logEvento("Troca manual aplicada: indo agora para o Boss " .. proximo)
        BossFarm.irPara(BossFarm.label[proximo])
    else
        BossFarm.logEvento("Troca manual aplicada: nenhum boss pendente na rotacao nova.")
        BossFarm.finalizarCiclo()
    end
end

function BossFarm.tentarEntrada(boss, direcao)
    if BossFarm.buscandoPendente and BossFarm.pendenteAtual ~= boss then
        return true
    end

    BossFarm.setCurrent(boss)

    if BossFarm.entrou then
        BossFarm.tentativaEntrada = 0
        BossFarm.esperandoEntrada = false
        BossFarm.estado = "DENTRO DA BOSS ROOM"
        return true
    end

    if BossFarm.esperandoEntrada then
        if os.time() - (BossFarm.tempoPasso or 0) < 5 then
            delay(500)
            return "retry"
        else
            BossFarm.esperandoEntrada = false
        end
    end

    if not BossFarm.esperandoEntrada then
        BossFarm.tentativaEntrada = BossFarm.tentativaEntrada + 1
        if BossFarm.tentativaEntrada <= 3 then
            BossFarm.estado = "ENTRADA - TENTATIVA " .. BossFarm.tentativaEntrada .. "/3"
            g_game.walk(direcao)
            BossFarm.esperandoEntrada = true
            BossFarm.tempoPasso = os.time()
            delay(500)
            return "retry"
        end
    end

    BossFarm.esperandoEntrada = false
    BossFarm.resetBoss()

    if BossFarm.jaDerrotadoDetectado then
        BossFarm.jaDerrotadoDetectado = false
        BossFarm.estado = "BOSS " .. boss .. " JA DERROTADO (PULANDO)"
        BossFarm.logEvento("3 tentativas concluidas. Boss ja estava derrotado, avancando...")

        if BossFarm.buscandoPendente then
            BossFarm.concluirPendente(boss)
        else
            local proximo = BossFarm.proximoBoss(boss)
            if proximo then
                BossFarm.estado = "INDO PARA BOSS " .. proximo
                BossFarm.irPara(BossFarm.label[proximo])
            else
                BossFarm.iniciarPendentes()
            end
        end
        return "retry"
    end

    if not BossFarm.buscandoPendente then
        BossFarm.marcarPendente(boss)
        BossFarm.logEvento("Boss " .. boss .. " ocupado na 1a passagem. Vai ser verificado no fim do ciclo.")

        local proximo = BossFarm.proximoBoss(boss)
        if proximo then
            BossFarm.estado = "INDO PARA BOSS " .. proximo
            BossFarm.irPara(BossFarm.label[proximo])
        else
            BossFarm.iniciarPendentes()
        end
        return "retry"
    else
        BossFarm.logEvento("Boss " .. boss .. " ainda ocupado na checagem de pendentes.")

        local proximo = BossFarm.proximoBoss(boss)
        if not proximo then
            proximo = BossFarm.proximoPendente()
        end

        if proximo and proximo ~= boss then
            BossFarm.pendenteAtual = proximo
            BossFarm.passagem[proximo] = 2
            BossFarm.estado = "PROXIMO PENDENTE: BOSS " .. proximo
            BossFarm.logEvento("Indo checar o proximo pendente (Boss " .. proximo .. ").")
            BossFarm.irPara(BossFarm.label[proximo])
            return "retry"
        else
            BossFarm.estado = "ACAMPANDO PORTA..."
            BossFarm.logEvento("Boss " .. boss .. " e o unico pendente restante. Aguardando 5s para tentar de novo...")
            delay(5000)
            return "retry"
        end
    end
end

function BossFarm.waitBossDead(boss)
    if BossFarm.buscandoPendente and BossFarm.pendenteAtual ~= boss then return true end
    if BossFarm.currentBoss ~= boss then BossFarm.setCurrent(boss) end

    if BossFarm.derrotou and not BossFarm.entrou then
        BossFarm.entrou = true
        BossFarm.logEvento("Boss " .. boss .. ": Entrada nao detectada, mas Derrota confirmada. Seguindo.")
    end

    if not BossFarm.entrou and (BossFarm.dentroDaSala == boss or BossFarm.salaDaPosicao(player:getPosition()) == boss) then
        BossFarm.entrou = true
    end

    if not BossFarm.entrou and BossFarm.noLobby(player:getPosition()) then
        BossFarm.voltasPorta = (BossFarm.voltasPorta or 0) + 1
        if BossFarm.voltasPorta <= 3 then
            BossFarm.estado = "NAO ENTROU - VOLTANDO NA PORTA " .. BossFarm.voltasPorta .. "/3"
            BossFarm.logEvento("Checkin: Boss " .. boss .. " ainda no lobby dos TPs, nao entrou. Voltando na porta (" .. BossFarm.voltasPorta .. "/3).")
            BossFarm.esperandoEntrada = false
            BossFarm.irPara(BossFarm.label[boss])
            return "retry"
        end
        BossFarm.logEvento("Checkin: Boss " .. boss .. " nao entrou em 3 voltas na porta. Pulando como na porta ocupada.")
        BossFarm.esperandoEntrada = false
        BossFarm.tentativaEntrada = 3
        BossFarm.voltasPorta = 0
        return BossFarm.tentarEntrada(boss, nil)
    end

    if not BossFarm.entrou then
        BossFarm.estado = "AGUARDANDO ENTRADA"
        delay(500)
        return "retry"
    end
    BossFarm.voltasPorta = 0

    if not BossFarm.derrotou then
        BossFarm.estado = "AGUARDANDO DERROTA"
        delay(500)
        return "retry"
    end

    if not BossFarm.teleportado then
        BossFarm.estado = "AGUARDANDO TELEPORTE"
        delay(500)
        return "retry"
    end

    BossFarm.estado = "BOSS FINALIZADO"

    storage.BossFarmNPCList[boss] = true
    BossFarm.syncCheckboxes()

    if BossFarm.buscandoPendente and BossFarm.pendenteAtual == boss then
        BossFarm.concluirPendente(boss)
    else
        local proximo = BossFarm.proximoBoss(boss)
        if proximo then
            BossFarm.estado = "INDO PARA BOSS " .. proximo
            BossFarm.irPara(BossFarm.label[proximo])
        else
            BossFarm.checarPendentesFinal()
        end
    end

    return true
end

function BossFarm.resetGeral()
    BossFarm.currentBoss = nil
    BossFarm.entrou = false
    BossFarm.derrotou = false
    BossFarm.teleportado = false
    BossFarm.tentativaEntrada = 0
    BossFarm.esperandoEntrada = false
    BossFarm.tempoPasso = 0
    BossFarm.passagem = {}
    BossFarm.pendente = {}
    BossFarm.buscandoPendente = false
    BossFarm.pendenteAtual = nil
    BossFarm.jaDerrotadoDetectado = false
    BossFarm.lastLabel = nil
    BossFarm.dentroDaSala = nil
    BossFarm.passeAte = 0
    storage.BossAntiTrapTPEnabled = false
    BossFarm.estado = "AGUARDANDO"
    BossFarm.ultimoEvento = "-"
    BossFarm.ultimoEventoTime = "-"

    BossFarm.NPC.ativo = false
    BossFarm.NPC.concluido = false
    for i = 1, 15 do storage.BossFarmNPCList[i] = false end
    BossFarm.syncCheckboxes()

    local cfg = storage.BossFarmHorario
    if cfg then
        cfg.rotacoesFeitas = 0
        cfg.horariosUsados = {false, false, false}
        cfg.janelasPerdidas = {false, false, false}
        cfg.usadoEm = {}
        cfg.concluidoEm = {}
        cfg.historicoRotacoes = {}
        cfg.rotacaoEmAndamento = false
        cfg.horaRotacaoAtual = nil
        cfg.indiceRotacaoAtual = nil
    end

    if bossFarmWindow then
        local btn = bossFarmWindow.resetGeralButton
        if btn then
            btn:setColor("#00FF00")
            btn:setText("SISTEMA RESETADO COM SUCESSO!")
            BossFarm.resetBtnTimer = os.time() + 2
        end
    end

    if BossFarm.atualizarPainel then BossFarm.atualizarPainel() end
end

local function temJa(msg, resto)
    return msg:find("j\225 " .. resto, 1, true) or msg:find("j\195\161 " .. resto, 1, true)
        or msg:find("ja " .. resto, 1, true) or msg:find("j\193 " .. resto, 1, true)
end

onTextMessage(function(mode, text)
    local msg = tostring(text or ""):lower()

    local d, h, m, s = msg:match("tempo restante:%s*(%d+)%s*dia%(s%)%s*(%d+):(%d+):(%d+)")
    if d and h and m and s then
        local totalSegundos = (tonumber(d) * 86400) + (tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s)
        storage.BossFarmVipExpiration = os.time() + totalSegundos
        BossFarm.logEvento("Sincronizado: VIP Expira em " .. d .. "d " .. h .. "h " .. m .. "m.")
    end

    if msg:find("entrou na boss room", 1, true) then
        if BossFarm.currentBoss then
            BossFarm.entrou = true
            BossFarm.dentroDaSala = BossFarm.currentBoss
            BossFarm.estado = "DENTRO DA BOSS ROOM"
        end
    end

    if temJa(msg, "derrotou") then
        local boss = BossFarm.currentBoss
        if boss then
            BossFarm.logEvento("Boss " .. boss .. " ja derrotado hoje! Marcando na memoria...")
            storage.BossFarmNPCList[boss] = true
            BossFarm.syncCheckboxes()
            BossFarm.jaDerrotadoDetectado = true
        end
        return
    end

    if msg:find("ocupada", 1, true) then
        local boss = BossFarm.currentBoss
        if boss then
            BossFarm.logEvento("Boss " .. boss .. " esta ocupado! Respeitando tentativas...")
        end
        return
    end

    if msg:find("derrotou", 1, true) and (msg:find("!", 1, true) or msg:find("boss", 1, true)) then
        if BossFarm.currentBoss then
            BossFarm.derrotou = true
            BossFarm.estado = "BOSS DERROTADO"
            storage.BossFarmNPCList[BossFarm.currentBoss] = true
            BossFarm.syncCheckboxes()
            BossFarm.logEvento("Boss " .. BossFarm.currentBoss .. " derrotado. Marcado no NPC.")
        end
    end

    if msg:find("teleportado para fora", 1, true) then
        local boss = BossFarm.currentBoss
        if not boss then return end
        BossFarm.teleportado = true
        BossFarm.dentroDaSala = nil
        BossFarm.estado = "TELEPORTADO PARA FORA"
        BossFarm.logEvento("Boss " .. boss .. ": teleportado para fora.")
    end
end)

function BossFarm.iniciarAutoNPC()
    BossFarm.NPC.modo = "AUTO"
    BossFarm.NPC.etapa = 0
    BossFarm.NPC.ativo = true
    BossFarm.NPC.concluido = false
    BossFarm.NPC.queue = {}
    BossFarm.NPC.timer = os.time()
    BossFarm.NPC.respondeu = false

    for i = 1, 15 do
        if storage.BossFarmNPCList[i] then
            table.insert(BossFarm.NPC.queue, i)
        end
    end
    BossFarm.logEvento("Final da rotacao: Iniciando limpeza de " .. #BossFarm.NPC.queue .. " bosses derrotados.")
end

BossFarm.NPC_NOME = "Seraphina Timeweaver"

function BossFarm.acharNpc()
    local alvo = BossFarm.NPC_NOME:lower()
    for _, spec in ipairs(getSpectators()) do
        if spec:getName():lower() == alvo then return spec end
    end
    return nil
end

onTalk(function(name, level, mode, text)
    if BossFarm.NPC.ativo and tostring(name or ""):lower() == BossFarm.NPC_NOME:lower() then
        BossFarm.NPC.respondeu = true
    end
end)

function BossFarm.falhaNpc(motivo)
    BossFarm.NPC.ativo = false
    BossFarm.NPC.concluido = false
    BossFarm.NPC.etapa = 0
    if g_game.getFollowingCreature() then g_game.cancelFollow() end
    BossFarm.NPC.tentativa = (BossFarm.NPC.tentativa or 0) + 1
    if BossFarm.NPC.tentativa < 3 then
        BossFarm.estado = "NPC - TENTATIVA " .. (BossFarm.NPC.tentativa + 1) .. "/3"
        BossFarm.logEvento("NPC: " .. motivo .. " Voltando na label npc (tentativa " .. (BossFarm.NPC.tentativa + 1) .. "/3).")
        BossFarm.irPara("npc")
        return
    end
    BossFarm.NPC.tentativa = 0
    local cfg = storage.BossFarmHorario
    cfg.rotacaoEmAndamento = false
    cfg.horaRotacaoAtual = nil
    cfg.indiceRotacaoAtual = nil
    local labelSaida = cfg.labelPosNpc or "saida cave"
    BossFarm.estado = "NPC FALHOU - VOLTA NAO CONTADA"
    BossFarm.logEvento("NPC: " .. motivo .. " 3 tentativas sem falar com a " .. BossFarm.NPC_NOME .. ". Volta NAO contada. Indo para: " .. labelSaida)
    BossFarm.irPara(labelSaida)
end

function BossFarm.processarNPC()
    if BossFarm.NPC.concluido then return end
    local loop = BossFarm.NPC.modo == "AUTO" and storage.BossFarmExecutionMode == "LOOP"

    if BossFarm.NPC.etapa == 0 then
        local npc = BossFarm.acharNpc()
        local esperando = os.time() - (BossFarm.NPC.timer or 0)
        if npc then
            if g_game.getFollowingCreature() ~= npc then g_game.follow(npc) end
            local p, n = player:getPosition(), npc:getPosition()
            local perto = p and n and p.z == n.z and math.max(math.abs(p.x - n.x), math.abs(p.y - n.y)) <= 2
            if not perto and esperando < 8 then
                BossFarm.estado = "NPC - SEGUINDO " .. BossFarm.NPC_NOME:upper()
                return
            end
        elseif esperando < 5 then
            BossFarm.estado = "NPC - PROCURANDO " .. BossFarm.NPC_NOME:upper()
            return
        elseif loop then
            BossFarm.falhaNpc(BossFarm.NPC_NOME .. " nao encontrada na tela.")
            return
        else
            BossFarm.logEvento("NPC: " .. BossFarm.NPC_NOME .. " nao apareceu na tela. Falando hi assim mesmo.")
        end
        BossFarm.estado = "NPC - ENVIANDO HI"
        BossFarm.logEvento("NPC: Iniciando conversa com 'hi'")
        NPC.say("hi")
        BossFarm.NPC.etapa = 1
        BossFarm.NPC.timer = os.time()
        return
    end

    if BossFarm.NPC.etapa == 1 then
        if loop and not BossFarm.NPC.respondeu then
            if os.time() - BossFarm.NPC.timer < 5 then
                BossFarm.estado = "NPC - ESPERANDO RESPOSTA"
            else
                BossFarm.falhaNpc(BossFarm.NPC_NOME .. " nao respondeu o hi.")
            end
            return
        end
        if os.time() - BossFarm.NPC.timer >= 1 then
            if #BossFarm.NPC.queue > 0 then
                local bossId = BossFarm.NPC.queue[1]
                local bossName = BossFarm.nome[bossId]
                BossFarm.estado = "NPC - LIMPANDO " .. bossName:upper()
                NPC.say(bossName:lower())
                BossFarm.NPC.etapa = 2
                BossFarm.NPC.timer = os.time()
            else
                local loopHarvestableCount
                if loop and (storage.BossFarmHorario.rotacoesFeitas or 0) < 2 then
                    loopHarvestableCount = BossFarm.countItem(13201)
                    if loopHarvestableCount == nil then
                        BossFarm.estado = "AGUARDANDO SALDO DO BANK"
                        return
                    end
                end
                BossFarm.NPC.ativo = false
                BossFarm.NPC.concluido = true
                BossFarm.estado = "LIMPEZA CONCLUIDA"
                if g_game.getFollowingCreature() then g_game.cancelFollow() end

                if BossFarm.NPC.modo == "AUTO" then

                    BossFarm.NPC.tentativa = 0
                    if BossFarm.finalizarRotacao then BossFarm.finalizarRotacao() end

                    local cfg = storage.BossFarmHorario
                    local maxRots = storage.BossFarmExecutionMode == "ONCE" and 1 or 3

                    if storage.BossFarmExecutionMode == "LOOP" and (cfg.rotacoesFeitas or 0) < maxRots then
                        local qtdNecessaria = (storage.BossFarmRotationType == "9BOSS") and 90 or 150
                        if storage.BossFarmRotationType == "CUSTOM" then
                            local countAtivos = 0
                            for i=1,15 do if storage.BossFarmCustomList[i] then countAtivos = countAtivos + 1 end end
                            qtdNecessaria = countAtivos * 10
                        end

                        if loopHarvestableCount < qtdNecessaria then
                            local labelSaida = cfg.labelPosNpc or "saida cave"
                            BossFarm.logEvento("Loop Abortado! Sem Harvestables. Indo pra saida: " .. labelSaida)
                            BossFarm.irPara(labelSaida)
                        else
                            BossFarm.logEvento("Limpeza efetuada! Rotacao contabilizada. Aguardando delay e engatando 'start'...")
                            delay(1500)
                            BossFarm.iniciarNovaRotacao()
                            BossFarm.irPara("start")
                        end
                    else
                        local labelSaida = cfg.labelPosNpc or "saida cave"
                        BossFarm.logEvento("Limpeza efetuada! Rotacao contabilizada. Indo para saida: " .. labelSaida)
                        delay(1500)
                        BossFarm.irPara(labelSaida)
                    end
                else
                    BossFarm.logEvento("NPC: Limpeza manual concluida.")
                end
            end
        end
        return
    end

    if BossFarm.NPC.etapa == 2 then
        if os.time() - BossFarm.NPC.timer >= 1 then
            BossFarm.estado = "NPC - YES/SIM"
            NPC.say("sim")
            delay(500)
            NPC.say("yes")
            BossFarm.NPC.etapa = 3
            BossFarm.NPC.timer = os.time()
        end
        return
    end

    if BossFarm.NPC.etapa == 3 then
        if os.time() - BossFarm.NPC.timer >= 1 then
            local bossId = BossFarm.NPC.queue[1]

            storage.BossFarmNPCList[bossId] = false
            BossFarm.syncCheckboxes()

            table.remove(BossFarm.NPC.queue, 1)
            BossFarm.NPC.etapa = 1
            BossFarm.NPC.timer = os.time()
        end
        return
    end
end

function BossFarm.fazerNPC()

    if BossFarm.modoGratis() then
        if not BossFarm.NPC.concluido then
            BossFarm.NPC.ativo = false
            BossFarm.NPC.concluido = true
            BossFarm.logEvento("Rotacao Gratis: label do NPC ignorada (sem conversa).")
            BossFarm.irParaSaidaGratis()
        end
        return true
    end

    if BossFarm.NPC.concluido then
        return true
    end

    if os.time() - (BossFarm.lastNpcCheck or 0) < 1 then
        return "retry"
    end
    BossFarm.lastNpcCheck = os.time()

    if not BossFarm.NPC.ativo then
        BossFarm.iniciarAutoNPC()
        return "retry"
    end

    BossFarm.processarNPC()
    return "retry"
end

macro(500, function()
    if BossFarm.NPC.modo == "MANUAL" and BossFarm.NPC.ativo then
        BossFarm.processarNPC()
    end
end)

function BossFarm.normalizarNomePlayer(nome)
  nome = tostring(nome or "")
  nome = nome:gsub("%s*%[%d+%]%s*$", "")
  nome = nome:gsub("^%s+", ""):gsub("%s+$", "")
  return nome
end

function BossFarm.nomePlayerIgual(a, b)
  return BossFarm.normalizarNomePlayer(a):lower() == BossFarm.normalizarNomePlayer(b):lower()
end

panelName = "autoParty"
if not storage[panelName] then
  storage[panelName] = {
    leaderName = 'Leader',
    autoPartyList = {},
    enabled = false,
  }
end

local config = storage[panelName]
config.leaderName = BossFarm.normalizarNomePlayer(config.leaderName)

if config.autoPartyList then
  local listaNormalizada = {}
  local vistos = {}
  for _, nome in ipairs(config.autoPartyList) do
    local limpo = BossFarm.normalizarNomePlayer(nome)
    local chave = limpo:lower()
    if limpo ~= "" and not vistos[chave] and not BossFarm.nomePlayerIgual(limpo, config.leaderName) then
      vistos[chave] = true
      table.insert(listaNormalizada, limpo)
    end
  end
  config.autoPartyList = listaNormalizada
end

macro(2000, function()
  if not storage.autoPartyEnabled then return end

  local meuNome = BossFarm.normalizarNomePlayer(player:getName())
  local nomeLider = BossFarm.normalizarNomePlayer(config.leaderName)
  local souLider = BossFarm.nomePlayerIgual(meuNome, nomeLider)

  for _, spec in pairs(getSpectators()) do
    if spec:isPlayer() and spec ~= player then
      local specNome = BossFarm.normalizarNomePlayer(spec:getName())

      if souLider then
        if spec:getShield() == 0 then
          for _, pName in ipairs(config.autoPartyList) do
            if BossFarm.nomePlayerIgual(pName, specNome) then
              g_game.partyInvite(spec:getId())
              break
            end
          end
        end
      else
        if spec:getShield() == 1 and BossFarm.nomePlayerIgual(specNome, nomeLider) then
          g_game.partyJoin(spec:getId())
        end
      end
    end
  end
end)

storage.BossAutoFollowEnabled = storage.BossAutoFollowEnabled or false

macro(3000, function()
  if not storage.BossAutoFollowEnabled then return end
  if BossFarm.ativo.isOff() then return end

  local targetAtual = g_game.getAttackingCreature()
  if targetAtual and targetAtual:isMonster() then
    local tName = targetAtual:getName():lower()
    if BossFarm.nomeMap[tName] then
      if g_game.getFollowingCreature() ~= targetAtual then
        g_game.follow(targetAtual)
      end
      return
    end
  end

  for _, spec in ipairs(getSpectators()) do
    if spec:isMonster() then
      local mName = spec:getName():lower()
      if BossFarm.nomeMap[mName] then
        g_game.attack(spec)
        g_game.follow(spec)
        break
      end
    end
  end
end)

g_ui.importStyleFromString([[
BossFarmBtn < UIButton
  font: verdana-11px-rounded
  text-align: center
  background-color: #333333DD
  border-width: 1
  border-color: #666666
  $hover:
    background-color: #555555DD
  $pressed:
    background-color: #1A1A1ADD

AutoPartyName < Label
  background-color: alpha
  text-offset: 2 0
  focusable: true
  height: 16
  $focus:
    background-color: #00000055
  Button
    id: remove
    text: x
    anchors.right: parent.right
    margin-right: 15
    width: 15
    height: 15

BossCheckBox < CheckBox
  font: verdana-11px-rounded
  color: #CCCCCC
  margin-left: 2

AutoPartyListWindow < MainWindow
  text: Auto Party Setup
  size: 200 280
  @onEscape: self:hide()
  Label
    id: lblLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text-align: center
    text: Leader Name (somente nome)
  TextEdit
    id: txtLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 5
  Label
    id: lblParty
    anchors.left: parent.left
    anchors.top: prev.bottom
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Party List
  TextList
    id: lstAutoParty
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    margin-bottom: 5
    padding: 1
    height: 100
    vertical-scrollbar: AutoPartyListListScrollBar
  VerticalScrollBar
    id: AutoPartyListListScrollBar
    anchors.top: lstAutoParty.top
    anchors.bottom: lstAutoParty.bottom
    anchors.right: parent.right
    step: 14
    pixels-scroll: true
  TextEdit
    id: playerName
    anchors.left: parent.left
    anchors.top: lstAutoParty.bottom
    margin-top: 5
    width: 120
  Button
    id: addPlayer
    text: +
    font: verdana-11px-rounded
    anchors.right: parent.right
    anchors.left: prev.right
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    margin-left: 3
  Label
    id: lblEspera
    anchors.left: parent.left
    anchors.top: playerName.bottom
    margin-top: 9
    width: 130
    text: Esperar time 1X (min):
  TextEdit
    id: txtEspera
    anchors.left: prev.right
    anchors.right: parent.right
    anchors.top: playerName.bottom
    margin-top: 5
    margin-left: 3
  Button
    id: closeButton
    text: Close
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21

BossFarmWindow < UIWindow
  width: 270
  height: 480
  padding: 6
  image-source: ~
  background-color: #000000DD
  border-width: 1
  border-color: #555555
  @onEscape: self:hide()

  layout:
    type: verticalBox

  Panel
    height: 20
    UILabel
      id: title
      text: BOSS FARM PREMIUM
      color: #00FFFF
      font: verdana-11px-rounded
      anchors.left: parent.left
      anchors.right: minimizeButton.left
      anchors.top: parent.top
      text-align: center
    BossFarmBtn
      id: closeButton
      text: X
      anchors.right: parent.right
      anchors.top: parent.top
      width: 22
      height: 18
      color: #FF3333
    BossFarmBtn
      id: minimizeButton
      text: -
      anchors.right: prev.left
      anchors.top: parent.top
      margin-right: 4
      width: 22
      height: 18
      color: #FFFF00

  Panel
    id: tabBar
    height: 22
    margin-top: 4
    layout:
      type: horizontalBox
      spacing: 2

    BossFarmBtn
      id: tabStatus
      text: STATUS
      width: 63
      height: 20

    BossFarmBtn
      id: tabConfig
      text: CONFIG
      width: 63
      height: 20

    BossFarmBtn
      id: tabCustom
      text: CUSTOM
      width: 63
      height: 20

    BossFarmBtn
      id: tabNpc
      text: NPC
      width: 63
      height: 20

  Panel
    id: pageStatus
    height: 370
    layout:
      type: verticalBox

    UILabel
      id: system
      text: Sistema: ATIVO
      color: #00FF00
      height: 16
      margin-top: 2

    UILabel
      id: vipStatus
      text: VIP: Sincronizando...
      color: #FF6347
      height: 16

    UILabel
      id: rotationInfo
      text: Tipo: FULL (15 Bosses)
      color: #00FFFF
      height: 16

    Panel
      id: harvestableRow
      height: 16
      layout:
        type: horizontalBox
      UILabel
        text: Harvestables:
        color: #CCCCCC
        width: 95
      UILabel
        id: harvestableCount
        text: 0
        color: #00FF00
        width: 100

    Panel
      id: dailyStatusRow
      height: 16
      layout:
        type: horizontalBox
      UILabel
        text: Rotacao Concluida:
        color: #CCCCCC
        width: 115
      UILabel
        id: dailyStatus
        text: 0/3
        color: #00FFFF
        width: 125

    UILabel
      id: current
      text: Boss atual: -
      color: #FFFF00
      height: 16
      margin-top: 2

    UILabel
      id: bossName
      text: Nome: -
      color: #CCCCCC
      height: 16

    UILabel
      id: passage
      text: Passagem: -
      color: #CCCCCC
      height: 16

    UILabel
      id: attempt
      text: Tentativa: 0/3
      color: #CCCCCC
      height: 16

    Panel
      id: enteredRow
      height: 16
      layout:
        type: horizontalBox

      UILabel
        id: enteredLabel
        text: Entrada:
        color: #CCCCCC
        width: 105

      UILabel
        id: entered
        text: NAO
        color: #FF3333
        width: 40

    Panel
      id: defeatedRow
      height: 16
      layout:
        type: horizontalBox

      UILabel
        id: defeatedLabel
        text: Derrotou:
        color: #CCCCCC
        width: 105

      UILabel
        id: defeated
        text: NAO
        color: #FF3333
        width: 40

    Panel
      id: teleportedRow
      height: 16
      layout:
        type: horizontalBox

      UILabel
        id: teleportedLabel
        text: Teleportado:
        color: #CCCCCC
        width: 105

      UILabel
        id: teleported
        text: NAO
        color: #FF3333
        width: 40

    HorizontalSeparator
      height: 2
      margin-top: 2

    UILabel
      id: pendingTitle
      text: BOSSES PENDENTES
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 16
      margin-top: 2

    UILabel
      id: pending
      text: Nenhum
      color: #CCCCCC
      height: 20
      text-wrap: true

    UILabel
      id: target
      text: Alvo pendente: -
      color: #CCCCCC
      height: 16

    HorizontalSeparator
      height: 2
      margin-top: 2

    UILabel
      id: stateTitle
      text: ESTADO
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 14
      margin-top: 2

    UILabel
      id: state
      text: AGUARDANDO
      color: #FFFF00
      height: 16

    HorizontalSeparator
      height: 2
      margin-top: 2

    UILabel
      id: eventTitle
      text: ULTIMO EVENTO
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 14

    UILabel
      id: event
      text: -
      color: #CCCCCC
      height: 55
      text-wrap: true

  Panel
    id: pageConfig
    height: 370
    visible: false
    layout:
      type: verticalBox

    UILabel
      id: configTitle
      text: CONFIGURACAO DE ROTA
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 16
      margin-top: 2

    BossFarmBtn
      id: toggleRotationType
      text: ROTACAO: FULL (15 BOSSES)
      height: 18
      color: #00FFFF
      margin-top: 2

    BossFarmBtn
      id: toggleModeCount
      text: HORARIO: 3X
      height: 18
      color: #7FFF00
      margin-top: 2

    BossFarmBtn
      id: toggleContinuous
      text: EXECUCAO: PADRAO (3 HORARIOS)
      height: 18
      color: #FFFF00
      margin-top: 2

    HorizontalSeparator
      height: 2
      margin-top: 4

    Panel
      height: 18
      margin-top: 2
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: BOSS FARM:
        width: 140
        color: #F0FFF0
        font: verdana-11px-rounded
      BossFarmBtn
        id: toggleButton
        text: ATIVO
        width: 118
        color: #00FF00

    Panel
      height: 18
      margin-top: 2
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: AUTO FOLLOW BOSSES:
        width: 140
        color: #F0FFF0
        font: verdana-11px-rounded
      BossFarmBtn
        id: toggleChase
        text: ATIVO
        width: 118
        color: #00FF00

    Panel
      height: 18
      margin-top: 2
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: AUTO PARTY LEADER:
        width: 140
        color: #F0FFF0
        font: verdana-11px-rounded
      BossFarmBtn
        id: toggleParty
        text: ATIVO
        width: 118
        color: #00FF00

    Panel
      height: 18
      margin-top: 2
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: TP ACIDENTAL:
        width: 140
        color: #F0FFF0
        font: verdana-11px-rounded
      BossFarmBtn
        id: toggleAntiTrap
        text: ATIVO
        width: 118
        color: #00FF00

    Panel
      height: 18
      margin-top: 2
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: AVISO NO NOME:
        width: 140
        color: #F0FFF0
        font: verdana-11px-rounded
      BossFarmBtn
        id: toggleAvisoNome
        text: DESATIVADO
        width: 118
        color: #B03060

    BossFarmBtn
      id: editPartyList
      text: SETUP AUTO PARTY
      height: 18
      color: #FFFF00
      margin-top: 4

    HorizontalSeparator
      height: 2
      margin-top: 4

    UILabel
      id: scheduleTitle
      text: HORARIOS DAS ROTACOES
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 16
      margin-top: 2

    Panel
      id: labelRow
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        id: labelText
        text: Ir p/ Bosses:
        color: #CCCCCC
        width: 90
      BotTextEdit
        id: labelDestino
        width: 168
        height: 18
        text-align: center

    Panel
      id: labelPosRow
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        id: labelPosText
        text: Voltar Cave:
        color: #CCCCCC
        width: 90
      BotTextEdit
        id: labelPosNpc
        width: 168
        height: 18
        text-align: center

    Panel
      id: modoCaveRow
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      UILabel
        text: CaveBot:
        color: #CCCCCC
        width: 55
      BossFarmBtn
        id: toggleModoCave
        text: UNICO
        width: 100
        height: 18
      UILabel
        text: Delay(s):
        color: #CCCCCC
        width: 55
        text-align: center
      BotTextEdit
        id: delayEntrada
        width: 48
        height: 18
        text-align: center

    Panel
      id: scheduleRow1
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      BossFarmBtn
        id: btnRot1
        text: Rotacao 1:
        width: 75
        height: 18
        color: #00FF00
      BotTextEdit
        id: hour1
        width: 50
        height: 18
        text-align: center
      UILabel
        id: rotationStatus1
        text: PENDENTE
        color: #AAAAAA
        width: 133
        text-align: center

    Panel
      id: scheduleRow2
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      BossFarmBtn
        id: btnRot2
        text: Rotacao 2:
        width: 75
        height: 18
        color: #00FF00
      BotTextEdit
        id: hour2
        width: 50
        height: 18
        text-align: center
      UILabel
        id: rotationStatus2
        text: PENDENTE
        color: #AAAAAA
        width: 133
        text-align: center

    Panel
      id: scheduleRow3
      height: 20
      layout:
        type: horizontalBox
        spacing: 0
      BossFarmBtn
        id: btnRot3
        text: Rotacao 3:
        width: 75
        height: 18
        color: #00FF00
      BotTextEdit
        id: hour3
        width: 50
        height: 18
        text-align: center
      UILabel
        id: rotationStatus3
        text: PENDENTE
        color: #AAAAAA
        width: 133
        text-align: center

    BossFarmBtn
      id: saveScheduleButton
      text: SALVAR HORARIOS E LABELS
      height: 18
      margin-top: 2

  Panel
    id: pageCustom
    height: 350
    visible: false
    layout:
      type: verticalBox

    UILabel
      id: customTabTitle
      text: BOSSES DA ROTA CUSTOMIZADA
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 16
      margin-top: 2

    Panel
      id: customListPanel
      height: 280
      margin-top: 5
      layout:
        type: verticalBox
        spacing: 1

    Panel
      height: 18
      margin-top: 5
      layout:
        type: horizontalBox
        spacing: 6
      BossFarmBtn
        id: btnMarcarTodos
        text: MARCAR TODOS
        color: #00FF00
        width: 126
      BossFarmBtn
        id: btnDesmarcarTodos
        text: DESMARCAR TODOS
        color: #FF3333
        width: 126

  Panel
    id: pageNpc
    height: 350
    visible: false
    layout:
      type: verticalBox

    UILabel
      id: npcTabTitle
      text: BOSSES PARA LIMPAR
      text-align: center
      font: verdana-11px-rounded
      color: #C455FF
      height: 16
      margin-top: 2

    Panel
      id: npcListPanel
      height: 280
      margin-top: 5
      layout:
        type: verticalBox
        spacing: 1

    Panel
      id: npcActionRow
      height: 20
      margin-top: 5
      layout:
        type: horizontalBox
        spacing: 6

      BossFarmBtn
        id: forceCleanButton
        text: LIMPAR SELEC.
        color: #FFFF00
        width: 126
        height: 18

      BossFarmBtn
        id: npcSelectAllButton
        text: MARCAR TODOS
        color: #00FF00
        width: 126
        height: 18

  BossFarmBtn
    id: resetGeralButton
    text: RESETAR SISTEMA E ROTACOES
    color: #FF3333
    height: 18
    margin-top: 5
]])

if autoPartyListWindow == nil then
    autoPartyListWindow = UI.createWindow('AutoPartyListWindow', g_ui.getRootWidget())
    autoPartyListWindow:hide()

    autoPartyListWindow.closeButton.onClick = function(widget)
        autoPartyListWindow:hide()
    end

    if config.autoPartyList and #config.autoPartyList > 0 then
        for _, pName in ipairs(config.autoPartyList) do
            local label = g_ui.createWidget("AutoPartyName", autoPartyListWindow.lstAutoParty)
            label.remove.onClick = function(widget)
                table.removevalue(config.autoPartyList, label:getText())
                label:destroy()
            end
            label:setText(pName)
        end
    end

    autoPartyListWindow.addPlayer.onClick = function(widget)
        local playerName = BossFarm.normalizarNomePlayer(autoPartyListWindow.playerName:getText())
        if playerName:len() > 0 and not BossFarm.nomePlayerIgual(playerName, config.leaderName) then
            local existe = false
            for _, nomeExistente in ipairs(config.autoPartyList) do
                if BossFarm.nomePlayerIgual(nomeExistente, playerName) then
                    existe = true
                    break
                end
            end

            if not existe then
                table.insert(config.autoPartyList, playerName)
                local label = g_ui.createWidget("AutoPartyName", autoPartyListWindow.lstAutoParty)
                label.remove.onClick = function(widget)
                    table.removevalue(config.autoPartyList, label:getText())
                    label:destroy()
                end
                label:setText(playerName)
                autoPartyListWindow.playerName:setText('')
            end
        end
    end

    autoPartyListWindow.playerName.onKeyPress = function(self, keyCode, keyboardModifiers)
        if not (keyCode == 5) then return false end
        autoPartyListWindow.addPlayer.onClick()
        return true
    end

    autoPartyListWindow.txtLeader.onTextChange = function(widget, text)
        config.leaderName = BossFarm.normalizarNomePlayer(text)
    end
    autoPartyListWindow.txtLeader:setText(config.leaderName)

    autoPartyListWindow.txtEspera:setText(tostring(config.esperaTime or 0))
    autoPartyListWindow.txtEspera.onTextChange = function(widget, text)
        config.esperaTime = math.max(0, math.min(30, math.floor(tonumber(text) or 0)))
    end
end

bossFarmWindow = g_ui.createWidget("BossFarmWindow", g_ui.getRootWidget())
pcall(function() bossFarmWindow:recursiveGetChildById("title"):setText("BOSS FARM PREMIUM " .. BossFarm.VERSAO) end)

storage.BossFarmWindowPos = storage.BossFarmWindowPos or {x = 100, y = 100}
bossFarmWindow:setRect({x = storage.BossFarmWindowPos.x, y = storage.BossFarmWindowPos.y, width = 270, height = 480})

bossFarmWindow.onMove = function(widget, newPos)
    storage.BossFarmWindowPos = {x = newPos.x, y = newPos.y}
end

bossFarmWindow.title = bossFarmWindow:recursiveGetChildById("title")
bossFarmWindow.minimizeButton = bossFarmWindow:recursiveGetChildById("minimizeButton")
bossFarmWindow.closeButton = bossFarmWindow:recursiveGetChildById("closeButton")
bossFarmWindow.resetGeralButton = bossFarmWindow:recursiveGetChildById("resetGeralButton")
bossFarmWindow.system = bossFarmWindow:recursiveGetChildById("system")
bossFarmWindow.vipStatus = bossFarmWindow:recursiveGetChildById("vipStatus")
bossFarmWindow.rotationInfo = bossFarmWindow:recursiveGetChildById("rotationInfo")
bossFarmWindow.harvestableCount = bossFarmWindow:recursiveGetChildById("harvestableCount")
bossFarmWindow.dailyStatus = bossFarmWindow:recursiveGetChildById("dailyStatus")
bossFarmWindow.current = bossFarmWindow:recursiveGetChildById("current")
bossFarmWindow.bossName = bossFarmWindow:recursiveGetChildById("bossName")
bossFarmWindow.passage = bossFarmWindow:recursiveGetChildById("passage")
bossFarmWindow.attempt = bossFarmWindow:recursiveGetChildById("attempt")
bossFarmWindow.entered = bossFarmWindow:recursiveGetChildById("entered")
bossFarmWindow.defeated = bossFarmWindow:recursiveGetChildById("defeated")
bossFarmWindow.teleported = bossFarmWindow:recursiveGetChildById("teleported")
bossFarmWindow.pending = bossFarmWindow:recursiveGetChildById("pending")
bossFarmWindow.target = bossFarmWindow:recursiveGetChildById("target")
bossFarmWindow.state = bossFarmWindow:recursiveGetChildById("state")
bossFarmWindow.event = bossFarmWindow:recursiveGetChildById("event")

bossFarmWindow.toggleButton = bossFarmWindow:recursiveGetChildById("toggleButton")
bossFarmWindow.toggleContinuous = bossFarmWindow:recursiveGetChildById("toggleContinuous")
bossFarmWindow.toggleRotationType = bossFarmWindow:recursiveGetChildById("toggleRotationType")
bossFarmWindow.toggleModeCount = bossFarmWindow:recursiveGetChildById("toggleModeCount")
bossFarmWindow.toggleChase = bossFarmWindow:recursiveGetChildById("toggleChase")
bossFarmWindow.toggleParty = bossFarmWindow:recursiveGetChildById("toggleParty")
bossFarmWindow.toggleAntiTrap = bossFarmWindow:recursiveGetChildById("toggleAntiTrap")
bossFarmWindow.toggleAvisoNome = bossFarmWindow:recursiveGetChildById("toggleAvisoNome")
bossFarmWindow.editPartyList = bossFarmWindow:recursiveGetChildById("editPartyList")

bossFarmWindow.btnRot1 = bossFarmWindow:recursiveGetChildById("btnRot1")
bossFarmWindow.btnRot2 = bossFarmWindow:recursiveGetChildById("btnRot2")
bossFarmWindow.btnRot3 = bossFarmWindow:recursiveGetChildById("btnRot3")
bossFarmWindow.hour1 = bossFarmWindow:recursiveGetChildById("hour1")
bossFarmWindow.hour2 = bossFarmWindow:recursiveGetChildById("hour2")
bossFarmWindow.hour3 = bossFarmWindow:recursiveGetChildById("hour3")
bossFarmWindow.labelDestino = bossFarmWindow:recursiveGetChildById("labelDestino")
bossFarmWindow.labelPosNpc = bossFarmWindow:recursiveGetChildById("labelPosNpc")
bossFarmWindow.toggleModoCave = bossFarmWindow:recursiveGetChildById("toggleModoCave")
bossFarmWindow.delayEntrada = bossFarmWindow:recursiveGetChildById("delayEntrada")
if bossFarmWindow.delayEntrada then bossFarmWindow.delayEntrada:setText(tostring(storage.BossFarmDelayEntrada)) end
bossFarmWindow.rotationStatus1 = bossFarmWindow:recursiveGetChildById("rotationStatus1")
bossFarmWindow.rotationStatus2 = bossFarmWindow:recursiveGetChildById("rotationStatus2")
bossFarmWindow.rotationStatus3 = bossFarmWindow:recursiveGetChildById("rotationStatus3")
bossFarmWindow.saveScheduleButton = bossFarmWindow:recursiveGetChildById("saveScheduleButton")

bossFarmWindow.tabStatus = bossFarmWindow:recursiveGetChildById("tabStatus")
bossFarmWindow.tabConfig = bossFarmWindow:recursiveGetChildById("tabConfig")
bossFarmWindow.tabCustom = bossFarmWindow:recursiveGetChildById("tabCustom")
bossFarmWindow.tabNpc = bossFarmWindow:recursiveGetChildById("tabNpc")

bossFarmWindow.pageStatus = bossFarmWindow:recursiveGetChildById("pageStatus")
bossFarmWindow.pageConfig = bossFarmWindow:recursiveGetChildById("pageConfig")
bossFarmWindow.pageCustom = bossFarmWindow:recursiveGetChildById("pageCustom")
bossFarmWindow.pageNpc = bossFarmWindow:recursiveGetChildById("pageNpc")

bossFarmWindow.npcListPanel = bossFarmWindow:recursiveGetChildById("npcListPanel")
bossFarmWindow.customListPanel = bossFarmWindow:recursiveGetChildById("customListPanel")
bossFarmWindow.forceCleanButton = bossFarmWindow:recursiveGetChildById("forceCleanButton")
bossFarmWindow.npcSelectAllButton = bossFarmWindow:recursiveGetChildById("npcSelectAllButton")
bossFarmWindow.btnMarcarTodos = bossFarmWindow:recursiveGetChildById("btnMarcarTodos")
bossFarmWindow.btnDesmarcarTodos = bossFarmWindow:recursiveGetChildById("btnDesmarcarTodos")

for i = 1, 15 do
    if storage.BossFarmCustomList[i] == nil then storage.BossFarmCustomList[i] = true end
end

for i, bName in ipairs(BossFarm.nome) do
    if storage.BossFarmNPCList[i] == nil then storage.BossFarmNPCList[i] = false end
    local cbNpc = g_ui.createWidget("BossCheckBox", bossFarmWindow.npcListPanel)
    cbNpc:setId("npcCb" .. i)
    cbNpc:setText("Boss " .. i .. "    " .. bName)
    cbNpc:setChecked(storage.BossFarmNPCList[i])
    cbNpc.onClick = function(widget)
        storage.BossFarmNPCList[i] = not storage.BossFarmNPCList[i]
        widget:setChecked(storage.BossFarmNPCList[i])
        BossFarm.syncCheckboxes()
    end

    local cbCust = g_ui.createWidget("BossCheckBox", bossFarmWindow.customListPanel)
    cbCust:setId("customCb" .. i)
    cbCust:setText("Boss " .. i .. "    " .. bName)
    cbCust:setChecked(storage.BossFarmCustomList[i])
    cbCust.onClick = function(widget)
        storage.BossFarmCustomList[i] = not storage.BossFarmCustomList[i]
        widget:setChecked(storage.BossFarmCustomList[i])
        BossFarm.gravarArquivo()
        BossFarm.aplicarTrocaRotacao()
    end
end

if bossFarmWindow.btnMarcarTodos then
    bossFarmWindow.btnMarcarTodos.onClick = function()
        for i = 1, 15 do storage.BossFarmCustomList[i] = true end
        BossFarm.syncCheckboxes()
        BossFarm.gravarArquivo()
        BossFarm.aplicarTrocaRotacao()
    end
end
if bossFarmWindow.btnDesmarcarTodos then
    bossFarmWindow.btnDesmarcarTodos.onClick = function()
        for i = 1, 15 do storage.BossFarmCustomList[i] = false end
        BossFarm.syncCheckboxes()
        BossFarm.gravarArquivo()
        BossFarm.aplicarTrocaRotacao()
    end
end

bossFarmWindow.forceCleanButton.onClick = function()
    BossFarm.NPC.modo = "MANUAL"
    BossFarm.NPC.etapa = 0
    BossFarm.NPC.ativo = true
    BossFarm.NPC.concluido = false
    BossFarm.NPC.queue = {}
    BossFarm.NPC.timer = os.time()
    for i = 1, 15 do
        if storage.BossFarmNPCList[i] then
            table.insert(BossFarm.NPC.queue, i)
        end
    end
    BossFarm.logEvento("Limpando " .. #BossFarm.NPC.queue .. " bosses manualmente...")
end

if bossFarmWindow.npcSelectAllButton then
    bossFarmWindow.npcSelectAllButton.onClick = function(widget)
        local todosMarcados = true
        for i = 1, 15 do
            if not storage.BossFarmNPCList[i] then
                todosMarcados = false
                break
            end
        end

        local novoStatus = not todosMarcados
        for i = 1, 15 do
            storage.BossFarmNPCList[i] = novoStatus
        end
        BossFarm.syncCheckboxes()
    end
end

local isMinimized = false
if bossFarmWindow.minimizeButton then
    bossFarmWindow.minimizeButton.onClick = function()
        isMinimized = not isMinimized
        if isMinimized then
            bossFarmWindow.pageStatus:hide()
            bossFarmWindow.pageConfig:hide()
            bossFarmWindow.pageCustom:hide()
            bossFarmWindow.pageNpc:hide()
            bossFarmWindow.tabStatus:hide()
            bossFarmWindow.tabConfig:hide()
            bossFarmWindow.tabCustom:hide()
            bossFarmWindow.tabNpc:hide()
            bossFarmWindow.resetGeralButton:hide()
            bossFarmWindow:setHeight(26)
            bossFarmWindow.minimizeButton:setText("+")
        else
            bossFarmWindow.pageStatus:show()
            bossFarmWindow.tabStatus:show()
            bossFarmWindow.tabConfig:show()
            bossFarmWindow.tabCustom:show()
            bossFarmWindow.tabNpc:show()
            bossFarmWindow.resetGeralButton:show()
            bossFarmWindow:setHeight(480)
            BossFarm.mostrarPagina(BossFarm.paginaAtual or 1)
            bossFarmWindow.minimizeButton:setText("-")
        end
    end
end

if bossFarmWindow.closeButton then
    bossFarmWindow.closeButton.onClick = function() bossFarmWindow:hide() end
end

BossFarm.inicializarHorario()
storage.BossFarmHorario.rotacoesAtivas = storage.BossFarmHorario.rotacoesAtivas or {true, true, true}

local function atualizarCorBotaoRotacao(btn, index)
    if storage.BossFarmHorario.rotacoesAtivas[index] then
        btn:setColor("#00FA9A")
    else
        btn:setColor("#FF3333")
    end
end

if bossFarmWindow.btnRot1 then
    atualizarCorBotaoRotacao(bossFarmWindow.btnRot1, 1)
    bossFarmWindow.btnRot1.onClick = function()
        storage.BossFarmHorario.rotacoesAtivas[1] = not storage.BossFarmHorario.rotacoesAtivas[1]
        atualizarCorBotaoRotacao(bossFarmWindow.btnRot1, 1)
        BossFarm.gravarArquivo()
    end
end

if bossFarmWindow.btnRot2 then
    atualizarCorBotaoRotacao(bossFarmWindow.btnRot2, 2)
    bossFarmWindow.btnRot2.onClick = function()
        if BossFarm.modoHorarioUnico() then return end
        storage.BossFarmHorario.rotacoesAtivas[2] = not storage.BossFarmHorario.rotacoesAtivas[2]
        atualizarCorBotaoRotacao(bossFarmWindow.btnRot2, 2)
        BossFarm.gravarArquivo()
    end
end

if bossFarmWindow.btnRot3 then
    atualizarCorBotaoRotacao(bossFarmWindow.btnRot3, 3)
    bossFarmWindow.btnRot3.onClick = function()
        if BossFarm.modoHorarioUnico() then return end
        storage.BossFarmHorario.rotacoesAtivas[3] = not storage.BossFarmHorario.rotacoesAtivas[3]
        atualizarCorBotaoRotacao(bossFarmWindow.btnRot3, 3)
        BossFarm.gravarArquivo()
    end
end

if bossFarmWindow.toggleRotationType then
    bossFarmWindow.toggleRotationType.onClick = function()
        if storage.BossFarmRotationType == "FULL" then
            storage.BossFarmRotationType = "9BOSS"
        elseif storage.BossFarmRotationType == "9BOSS" then
            storage.BossFarmRotationType = "CUSTOM"
        else
            storage.BossFarmRotationType = "FULL"
        end
        BossFarm.gravarArquivo()
        BossFarm.logEvento("Rotacao alterada para: " .. storage.BossFarmRotationType)
        BossFarm.aplicarTrocaRotacao()
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleModeCount then
    bossFarmWindow.toggleModeCount.onClick = function()
        if storage.BossFarmModeCount == "3X" then
            storage.BossFarmModeCount = "1X"
        else
            storage.BossFarmModeCount = "3X"
        end
        BossFarm.gravarArquivo()
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleContinuous then
    bossFarmWindow.toggleContinuous.onClick = function()
        if storage.BossFarmExecutionMode == "SCHEDULE" then
            storage.BossFarmExecutionMode = "ONCE"
        elseif storage.BossFarmExecutionMode == "ONCE" then
            storage.BossFarmExecutionMode = "LOOP"
        else
            storage.BossFarmExecutionMode = "SCHEDULE"
        end
        BossFarm.aplicarModoUnico()
        if bossFarmWindow.btnRot2 then atualizarCorBotaoRotacao(bossFarmWindow.btnRot2, 2) end
        if bossFarmWindow.btnRot3 then atualizarCorBotaoRotacao(bossFarmWindow.btnRot3, 3) end
        BossFarm.gravarArquivo()
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleChase then
    bossFarmWindow.toggleChase.onClick = function()
        storage.BossAutoFollowEnabled = not storage.BossAutoFollowEnabled
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleModoCave then
    bossFarmWindow.toggleModoCave.onClick = function()
        storage.BossFarmModoCave = BossFarm.modoSeparado() and "UNICO" or "SEPARADO"
        if BossFarm.modoSeparado() then BossFarm.instalarCaveBoss() end
        BossFarm.logEvento("Modo CaveBot: " .. storage.BossFarmModoCave .. (BossFarm.modoSeparado() and (" (rotacao no CaveBot '" .. BossFarm.CAVE_BOSS .. "')") or ""))
        BossFarm.gravarArquivo()
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.delayEntrada then
    bossFarmWindow.delayEntrada.onTextChange = function(widget, texto)
        local seg = tonumber((tostring(texto or ""):gsub(",", ".")))
        if not seg or seg < 0 or seg > 30 then return end
        storage.BossFarmDelayEntrada = seg
        BossFarm.gravarArquivo()
    end
end

if bossFarmWindow.toggleAvisoNome then
    bossFarmWindow.toggleAvisoNome.onClick = function()
        storage.BossFarmAvisoNome = not storage.BossFarmAvisoNome
        BossFarm.gravarArquivo()
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleParty then
    bossFarmWindow.toggleParty.onClick = function()
        storage.autoPartyEnabled = not storage.autoPartyEnabled
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.toggleAntiTrap then
    bossFarmWindow.toggleAntiTrap.onClick = function()
        storage.BossAntiTrapTPEnabled = not storage.BossAntiTrapTPEnabled
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.editPartyList and autoPartyListWindow then
    bossFarmWindow.editPartyList.onClick = function()
        autoPartyListWindow:show()
        autoPartyListWindow:raise()
        autoPartyListWindow:focus()
    end
end

BossFarm.painelHorariosCarregados = false
bossFarmWindow:hide()

function BossFarm.mostrarPagina(numero)
    BossFarm.paginaAtual = numero

    bossFarmWindow.pageStatus:hide()
    bossFarmWindow.pageConfig:hide()
    bossFarmWindow.pageCustom:hide()
    bossFarmWindow.pageNpc:hide()

    local corInativa = "#777777"
    local corAtiva = "#00FFFF"

    bossFarmWindow.tabStatus:setColor(corInativa)
    bossFarmWindow.tabConfig:setColor(corInativa)
    bossFarmWindow.tabCustom:setColor(corInativa)
    bossFarmWindow.tabNpc:setColor(corInativa)

    if numero == 1 then
        bossFarmWindow.pageStatus:show()
        bossFarmWindow.tabStatus:setColor(corAtiva)
    elseif numero == 2 then
        bossFarmWindow.pageConfig:show()
        bossFarmWindow.tabConfig:setColor(corAtiva)
    elseif numero == 3 then
        bossFarmWindow.pageCustom:show()
        bossFarmWindow.tabCustom:setColor(corAtiva)
    elseif numero == 4 then
        bossFarmWindow.pageNpc:show()
        bossFarmWindow.tabNpc:setColor(corAtiva)
    end
end

if bossFarmWindow.tabStatus then
    bossFarmWindow.tabStatus.onClick = function() BossFarm.mostrarPagina(1) end
end
if bossFarmWindow.tabConfig then
    bossFarmWindow.tabConfig.onClick = function() BossFarm.mostrarPagina(2) end
end
if bossFarmWindow.tabCustom then
    bossFarmWindow.tabCustom.onClick = function() BossFarm.mostrarPagina(3) end
end
if bossFarmWindow.tabNpc then
    bossFarmWindow.tabNpc.onClick = function() BossFarm.mostrarPagina(4) end
end

BossFarm.mostrarPagina(1)

onKeyPress(function(keys)
    if keys == "Ctrl+F1" then
        if bossFarmWindow:isVisible() then
            bossFarmWindow:hide()
        else
            bossFarmWindow:show()
            bossFarmWindow:raise()
            bossFarmWindow:focus()
        end
    end
end)

addButton("BossFarmPainel", "Boss Farm - Painel", function()
    if bossFarmWindow:isVisible() then
        bossFarmWindow:hide()
    else
        bossFarmWindow:show()
        bossFarmWindow:raise()
        bossFarmWindow:focus()
    end
end)

if bossFarmWindow.toggleButton then
    bossFarmWindow.toggleButton.onClick = function()
        if BossFarm.ativo.isOn() then
            BossFarm.ativo.setOff()
            BossFarm.estado = "DESATIVADO"
        else
            BossFarm.ativo.setOn()
            BossFarm.estado = "AGUARDANDO"
        end
        BossFarm.atualizarPainel()
    end
end

if bossFarmWindow.resetGeralButton then
    bossFarmWindow.resetGeralButton.onClick = function()
        BossFarm.resetGeral()
    end
end

if bossFarmWindow.saveScheduleButton then
    bossFarmWindow.saveScheduleButton.onClick = function()
        local h1 = bossFarmWindow.hour1:getText()
        local h2 = bossFarmWindow.hour2:getText()
        local h3 = bossFarmWindow.hour3:getText()
        local labelDestino = bossFarmWindow.labelDestino:getText()
        local labelPos = bossFarmWindow.labelPosNpc:getText()

        local ok, erro = BossFarm.salvarHorarios(h1, h2, h3, labelDestino, labelPos)

        if ok then
            BossFarm.painelHorariosCarregados = true
            local cfg = storage.BossFarmHorario.horariosConfigurados
            bossFarmWindow.hour1:setText(cfg[1] or "")
            bossFarmWindow.hour2:setText(cfg[2] or "")
            bossFarmWindow.hour3:setText(cfg[3] or "")
            bossFarmWindow.labelDestino:setText(storage.BossFarmHorario.labelConfigurado or "farmboss")
            bossFarmWindow.labelPosNpc:setText(storage.BossFarmHorario.labelPosNpc or "saida cave")

            bossFarmWindow.saveScheduleButton:setColor("#00FA9A")
            bossFarmWindow.saveScheduleButton:setText("SALVO COM SUCESSO!")
            BossFarm.gravarArquivo()
            BossFarm.logEvento("Horarios e Labels salvos com sucesso!")

            BossFarm.saveBtnTimer = os.time() + 2
        else
            bossFarmWindow.saveScheduleButton:setColor("#FF3333")
            bossFarmWindow.saveScheduleButton:setText("ERRO!")
            BossFarm.logEvento(tostring(erro))
            BossFarm.gravarArquivo()

            BossFarm.saveBtnTimer = os.time() + 2
        end
        BossFarm.atualizarPainel()
    end
end

function BossFarm.atualizarPainel()
    if not bossFarmWindow then return end

    if BossFarm.resetBtnTimer and BossFarm.resetBtnTimer > 0 and os.time() >= BossFarm.resetBtnTimer then
        if bossFarmWindow.resetGeralButton then
            bossFarmWindow.resetGeralButton:setColor("#FF3333")
            bossFarmWindow.resetGeralButton:setText("RESETAR SISTEMA E ROTACOES")
        end
        BossFarm.resetBtnTimer = 0
    end

    if BossFarm.saveBtnTimer and BossFarm.saveBtnTimer > 0 and os.time() >= BossFarm.saveBtnTimer then
        if bossFarmWindow.saveScheduleButton then
            bossFarmWindow.saveScheduleButton:setColor("#CCCCCC")
            bossFarmWindow.saveScheduleButton:setText("SALVAR HORARIOS E LABELS")
        end
        BossFarm.saveBtnTimer = 0
    end

    local boss = BossFarm.currentBoss
    local nome = boss and (BossFarm.nome[boss] or "-") or "-"
    local passagem = 1
    if boss then passagem = BossFarm.passagem[boss] or 1 end

    local lista = {}
    for _, i in ipairs(BossFarm.getActiveBosses()) do
        if BossFarm.pendente[i] then table.insert(lista, "B" .. i) end
    end

    local sistema = "DESATIVADO"
    if BossFarm.ativo and BossFarm.ativo.isOn() then sistema = "ATIVO" end

    if bossFarmWindow.system then
        bossFarmWindow.system:setText("Sistema: " .. sistema)
        bossFarmWindow.system:setColor(sistema == "ATIVO" and "#00FA9A" or "#FF3333")
    end

    if bossFarmWindow.vipStatus then
        if storage.BossFarmVipExpiration and storage.BossFarmVipExpiration > 0 then
            local diff = storage.BossFarmVipExpiration - os.time()
            if diff > 0 then
                local d = math.floor(diff / 86400)
                local h = math.floor((diff % 86400) / 3600)
                local m = math.floor((diff % 3600) / 60)
                local s = diff % 60
                bossFarmWindow.vipStatus:setText(string.format("VIP: %dd %02dh %02dm %02ds", d, h, m, s))
                if d < 10 then
                    bossFarmWindow.vipStatus:setColor("#FF3333")
                else
                    bossFarmWindow.vipStatus:setColor("#FF6347")
                end
            else
                bossFarmWindow.vipStatus:setText("VIP: Expirado!")
                bossFarmWindow.vipStatus:setColor("#FF3333")
            end
        else
            bossFarmWindow.vipStatus:setText("VIP: Sincronizando...")
            bossFarmWindow.vipStatus:setColor("#FF6347")
        end
    end

    if bossFarmWindow.harvestableCount then
        if os.time() - (BossFarm.lastHarvestableCheck or 0) >= 2 then
            BossFarm.cachedHarvestableCount = BossFarm.countItem(13201)
            BossFarm.lastHarvestableCheck = os.time()
        end

        local hw = BossFarm.cachedHarvestableCount
        bossFarmWindow.harvestableCount:setText(hw == nil and "..." or tostring(hw))

        local qtdNecessaria = 150
        if storage.BossFarmRotationType == "9BOSS" then
            qtdNecessaria = 90
        elseif storage.BossFarmRotationType == "CUSTOM" then
            local countAtivos = 0
            for i = 1, 15 do
                if storage.BossFarmCustomList[i] then countAtivos = countAtivos + 1 end
            end
            qtdNecessaria = countAtivos * 10
        end

        if hw == nil then
            bossFarmWindow.harvestableCount:setColor("#FFFF00")
        elseif hw < qtdNecessaria then
            bossFarmWindow.harvestableCount:setColor("#FF3333")
        else
            bossFarmWindow.harvestableCount:setColor("#00FA9A")
        end
    end

    if bossFarmWindow.dailyStatus then
        local cfg = storage.BossFarmHorario
        local feitos = cfg.rotacoesFeitas or 0
        local hist = cfg.historicoRotacoes or {}

        local maxRot = storage.BossFarmExecutionMode == "ONCE" and 1 or 3
        local txt = feitos .. "/" .. maxRot

        if feitos > 0 and hist[feitos] then
            txt = txt .. " (" .. hist[feitos] .. ")"
        end
        bossFarmWindow.dailyStatus:setText(txt)

        if cfg.rotacaoEmAndamento then
            bossFarmWindow.dailyStatus:setColor("#FFFF00")
        elseif feitos >= maxRot then
            bossFarmWindow.dailyStatus:setColor("#00FA9A")
        else
            bossFarmWindow.dailyStatus:setColor("#00FFFF")
        end
    end

    if bossFarmWindow.rotationInfo then
        if storage.BossFarmRotationType == "9BOSS" then
            bossFarmWindow.rotationInfo:setText("Tipo: 9 Bosses")
        elseif storage.BossFarmRotationType == "CUSTOM" then
            local countAtivos = 0
            for i = 1, 15 do
                if storage.BossFarmCustomList[i] then countAtivos = countAtivos + 1 end
            end
            bossFarmWindow.rotationInfo:setText("Tipo: Custom (" .. countAtivos .. " Bosses)")
        else
            bossFarmWindow.rotationInfo:setText("Tipo: FULL (15 Bosses)")
        end
    end

    if bossFarmWindow.toggleRotationType then
        bossFarmWindow.toggleRotationType:setText(storage.BossFarmRotationType == "9BOSS" and "ROTACAO: 9 BOSSES" or (storage.BossFarmRotationType == "CUSTOM" and "ROTACAO: CUSTOM (SELECIONADOS)" or "ROTACAO: FULL (15 BOSSES)"))
        bossFarmWindow.toggleRotationType:setColor("#00FFFF")
    end

    if bossFarmWindow.toggleModeCount then
        if storage.BossFarmModeCount == "1X" then
            bossFarmWindow.toggleModeCount:setText("HORARIO: 1X (LIVRE)")
            bossFarmWindow.toggleModeCount:setColor("#A52A2A")
        else
            bossFarmWindow.toggleModeCount:setText("HORARIO: 3X")
            bossFarmWindow.toggleModeCount:setColor("#7FFF00")
        end
    end

    if bossFarmWindow.toggleContinuous then
        if storage.BossFarmExecutionMode == "LOOP" then
            bossFarmWindow.toggleContinuous:setText("EXECUCAO: LOOP 3X SEGUIDAS")
            bossFarmWindow.toggleContinuous:setColor("#DDA0DD")
        elseif storage.BossFarmExecutionMode == "ONCE" then
            bossFarmWindow.toggleContinuous:setText("EXECUCAO: ROTACAO GRATIS 1X NO DIA")
            bossFarmWindow.toggleContinuous:setColor("#FF8800")
        else
            bossFarmWindow.toggleContinuous:setText("EXECUCAO: PADRAO (3 HORARIOS)")
            bossFarmWindow.toggleContinuous:setColor("#FFFF00")
        end
    end

    if bossFarmWindow.toggleChase then
        if storage.BossAutoFollowEnabled then
            bossFarmWindow.toggleChase:setText("ATIVO")
            bossFarmWindow.toggleChase:setColor("#00FA9A")
        else
            bossFarmWindow.toggleChase:setText("DESATIVADO")
            bossFarmWindow.toggleChase:setColor("#B03060")
        end
    end

    if bossFarmWindow.toggleModoCave then
        if BossFarm.modoSeparado() then
            bossFarmWindow.toggleModoCave:setText("SEPARADO")
            bossFarmWindow.toggleModoCave:setColor("#00FA9A")
        else
            bossFarmWindow.toggleModoCave:setText("UNICO")
            bossFarmWindow.toggleModoCave:setColor("#FFFF00")
        end
    end

    if bossFarmWindow.toggleAvisoNome then
        if storage.BossFarmAvisoNome then
            bossFarmWindow.toggleAvisoNome:setText("ATIVO")
            bossFarmWindow.toggleAvisoNome:setColor("#00FA9A")
        else
            bossFarmWindow.toggleAvisoNome:setText("DESATIVADO")
            bossFarmWindow.toggleAvisoNome:setColor("#B03060")
        end
    end

    if bossFarmWindow.toggleParty then
        if storage.autoPartyEnabled then
            bossFarmWindow.toggleParty:setText("ATIVO")
            bossFarmWindow.toggleParty:setColor("#00FA9A")
        else
            bossFarmWindow.toggleParty:setText("DESATIVADO")
            bossFarmWindow.toggleParty:setColor("#B03060")
        end
    end

    if bossFarmWindow.toggleAntiTrap then
        if storage.BossAntiTrapTPEnabled then
            bossFarmWindow.toggleAntiTrap:setText("ATIVO (AUTO)")
            bossFarmWindow.toggleAntiTrap:setColor("#00FA9A")
        else
            bossFarmWindow.toggleAntiTrap:setText("DESATIVADO")
            bossFarmWindow.toggleAntiTrap:setColor("#B03060")
        end
    end

    if bossFarmWindow.toggleButton then
        if BossFarm.ativo.isOn() then
            bossFarmWindow.toggleButton:setText("ATIVO")
            bossFarmWindow.toggleButton:setColor("#00FA9A")
        else
            bossFarmWindow.toggleButton:setText("DESATIVADO")
            bossFarmWindow.toggleButton:setColor("#B03060")
        end
    end

    BossFarm.inicializarHorario()
    local cfgHorarios = storage.BossFarmHorario.horariosConfigurados or BossFarm.HorariosPadrao

    local horarioLivre = storage.BossFarmExecutionMode ~= "LOOP"
    for _, campo in ipairs({bossFarmWindow.hour2, bossFarmWindow.hour3}) do
        if campo and campo:isEnabled() ~= horarioLivre then
            campo:setEditable(horarioLivre)
            campo:setEnabled(horarioLivre)
        end
    end

    if not BossFarm.painelHorariosCarregados and bossFarmWindow.hour1 then
        bossFarmWindow.hour1:setText(cfgHorarios[1] or "")
        bossFarmWindow.hour2:setText(cfgHorarios[2] or "")
        bossFarmWindow.hour3:setText(cfgHorarios[3] or "")
        if bossFarmWindow.labelDestino then
            bossFarmWindow.labelDestino:setText(storage.BossFarmHorario.labelConfigurado or "farmboss")
        end
        if bossFarmWindow.labelPosNpc then
            bossFarmWindow.labelPosNpc:setText(storage.BossFarmHorario.labelPosNpc or "saida cave")
        end
        BossFarm.painelHorariosCarregados = true
    end

    if bossFarmWindow.current then bossFarmWindow.current:setText("Boss atual: " .. (boss and "Boss " .. boss or "-")) end
    if bossFarmWindow.bossName then bossFarmWindow.bossName:setText("Nome: " .. nome) end
    if bossFarmWindow.passage then bossFarmWindow.passage:setText("Passagem: " .. (passagem == 2 and "2a" or "1a")) end
    if bossFarmWindow.attempt then bossFarmWindow.attempt:setText("Tentativa: " .. tostring(BossFarm.tentativaEntrada or 0) .. "/3") end

    if bossFarmWindow.entered then
        bossFarmWindow.entered:setText(BossFarm.entrou and "SIM" or "NAO")
        bossFarmWindow.entered:setColor(BossFarm.entrou and "#00FA9A" or "#FF3333")
    end
    if bossFarmWindow.defeated then
        bossFarmWindow.defeated:setText(BossFarm.derrotou and "SIM" or "NAO")
        bossFarmWindow.defeated:setColor(BossFarm.derrotou and "#00FA9A" or "#FF3333")
    end
    if bossFarmWindow.teleported then
        bossFarmWindow.teleported:setText(BossFarm.teleportado and "SIM" or "NAO")
        bossFarmWindow.teleported:setColor(BossFarm.teleportado and "#00FA9A" or "#FF3333")
    end

    if bossFarmWindow.pending then
        if #lista > 0 then
            bossFarmWindow.pending:setText(table.concat(lista, ", "))
        else
            bossFarmWindow.pending:setText("Nenhum")
        end
    end

    if bossFarmWindow.target then
        if BossFarm.pendenteAtual then
            bossFarmWindow.target:setText("Alvo pendente: Boss " .. BossFarm.pendenteAtual)
        else
            bossFarmWindow.target:setText("Alvo pendente: -")
        end
    end

    local agora = os.date("*t")
    local agoraMin = BossFarm.minRel(agora.hour * 60 + agora.min)
    local cfg = storage.BossFarmHorario

    local function atualizarStatusRotacao(i, widget)
        if not widget then return end

        local hText = (cfgHorarios[i] or ""):gsub("%s+", "")
        local isEmpty = (hText == "")
        local isValid = BossFarm.validarHorario(hText)

        local isMissed = cfg.janelasPerdidas and cfg.janelasPerdidas[i] and BossFarm.slotUsado(i)

        local texto = "PENDENTE"
        local cor = "#AAAAAA"
        local loop = storage.BossFarmExecutionMode == "LOOP"
        local feitas = cfg.rotacoesFeitas or 0

        if loop and i >= 2 then
            texto = "DESATIVADA"
            cor = "#B03060"
        elseif loop and feitas >= 3 then
            texto = "CONCLUIDA"
            cor = "#00FA9A"
        elseif loop and cfg.rotacaoEmAndamento then
            texto = (feitas + 1) .. "/3"
            cor = "#FFFF00"
        elseif loop and feitas > 0 then
            texto = feitas .. "/3" .. ((cfg.janelasPerdidas and cfg.janelasPerdidas[1]) and " PERDIDA" or "")
            cor = "#FF8C00"
        elseif BossFarm.modoHorarioUnico() and i >= 2 then
            texto = "NAO USADA"
            cor = "#555555"
        elseif cfg.rotacoesAtivas and cfg.rotacoesAtivas[i] == false then
            texto = "DESATIVADA"
            cor = "#B03060"
        elseif isEmpty then
            texto = "VAZIO"
            cor = "#555555"
        elseif not isValid then
            texto = "INVALIDO"
            cor = "#FF3333"
        elseif cfg.rotacaoEmAndamento and cfg.indiceRotacaoAtual == i then
            texto = "EM ROTACAO"
            cor = "#FFFF00"
        elseif isMissed then
            texto = "PERDIDA"
            cor = "#555555"
        elseif BossFarm.slotUsado(i) and type(cfg.concluidoEm) == "table" and cfg.concluidoEm["s" .. i] == BossFarm.dataDoDia() then
            texto = "CONCLUIDA"
            cor = "#00FA9A"
        elseif BossFarm.slotUsado(i) then
            texto = "NAO CONCLUIDA"
            cor = "#FF8C00"
        else
            local inicio = BossFarm.horaRel(hText)
            local fim = inicio + 5
            if inicio and agoraMin >= inicio and agoraMin <= fim then
                texto = "AGUARDANDO"
                cor = "#FFFF00"
            elseif inicio and agoraMin > fim then
                texto = "PERDIDA"
                cor = "#555555"
            end
        end
        widget:setText(texto)
        widget:setColor(cor)
    end

    atualizarStatusRotacao(1, bossFarmWindow.rotationStatus1)
    atualizarStatusRotacao(2, bossFarmWindow.rotationStatus2)
    atualizarStatusRotacao(3, bossFarmWindow.rotationStatus3)

    if bossFarmWindow.state then
        bossFarmWindow.state:setText(BossFarm.estado or "AGUARDANDO")
        if BossFarm.ativo.isOff() then
            bossFarmWindow.state:setColor("#FF3333")
        elseif (BossFarm.estado or ""):find("AGUARDANDO", 1, true) then
            bossFarmWindow.state:setColor("#FFFF00")
        elseif (BossFarm.estado or ""):find("ERRO", 1, true) then
            bossFarmWindow.state:setColor("#FF3333")
        else
            bossFarmWindow.state:setColor("#00FA9A")
        end
    end

    if bossFarmWindow.event then
        bossFarmWindow.event:setText(tostring(BossFarm.ultimoEventoTime or "-") .. " - " .. tostring(BossFarm.ultimoEvento or "-"))
    end
end

macro(250, function() BossFarm.atualizarPainel() end)
