-- 
-- Please see the license.txt file included with this distribution for 
-- attribution and copyright information.
--

local modAttack
function onInit()
	modAttack = ActionAttack.modAttack
	ActionAttack.modAttack = modAttackCustom

	ActionsManager.registerModHandler("attack", modAttackCustom);
	ActionsManager.registerModHandler("grapple", modAttackCustom);
	
	OptionsManager.registerOption2('AUTO_FLANK', false, 'option_header_game', 'opt_lab_autoflank', 'option_entry_cycler', 
		{ labels = 'option_val_off', values = 'off', baselabel = 'option_val_on', baseval = 'on', default = 'on' })
end

function modAttackCustom(rSource, rTarget, rRoll, ...)
	
	-- Debug.chat("rSource:  ", rSource);
	-- Debug.chat("rTarget:  ", rTarget);
	-- Debug.chat("rRoll:  ", rRoll);
	-- for an NPC, this is the CT node; for PC, it is the charsheet
	local srcNode = ActorManager.getCreatureNode(rSource);
	local srcCTnode = ActorManager.getCTNode(rSource);
	
	local sAttackType = attackType(rRoll);
	local nRange = getRangeToTarget(rSource, rTarget);
	
	-- Check range and add/remove "rng30" effect as appropriate
	-- This needs to be done before modAttack so that the effect
	-- is correctly applied to the current roll
	if rTarget ~= nil and sAttackType == "R" and nRange <= 30 and nRange >= 0 then
		if hasFeat(srcNode, "Point Blank Shot") or hasFeat(srcNode, "Point-Blank Shot") then
			-- Point blank and has feat
			-- addEffect("", "", srcCTnode, {sName = "PBS; rng30; ATK: 1 ranged; DMG: 1 ranged; DMGS: 1"}, false);
			addEffect(rSource, {sName = "PBS; rng30; ATK: 1 ranged; DMG: 1 ranged; DMGS: 1"});
		else
			-- Point blank but no feat (e.g. for Sneak Attack)
			-- addEffect("", "", srcCTnode, {sName = "rng30", nDuration = 1, nGMOnly = 0}, false);
			addEffect(rSource, {sName = "rng30", nDuration = 1, nGMOnly = 0});
		end
	else
		removeEffect(srcCTnode, "rng30");
		removeEffect(srcCTnode, "PBS; rng30; ATK: 1 ranged; DMG: 1 ranged; DMGS: 1");
	end
	
	-- Call original modAttack
	modAttack(rSource, rTarget, rRoll, ...);
	
	if sAttackType == "R" then
		removeEffect(srcCTnode, "Flanking");
		if rTarget ~= nil then
			-- Check range modifier
			local nRangeMod = getRangeModifier(srcNode, rRoll, nRange);
			if nRangeMod < 0 then
				rRoll.sDesc = rRoll.sDesc .. " " .. "[RANGE " .. nRangeMod .."]";
				rRoll.nMod = rRoll.nMod + nRangeMod;
			end
			
			-- Check and add shooting into melee modifier
			local nShootMeleeMod = checkShootMelee(rSource, srcNode, rTarget);
			if nShootMeleeMod < 0 then
				rRoll.sDesc = rRoll.sDesc .. " " .. "[SHOOT MELEE " .. nShootMeleeMod .."]";
				rRoll.nMod = rRoll.nMod + nShootMeleeMod;
			end
		end
	elseif rTarget ~= nil then
		-- Check and add flank modifier
		-- Debug.chat(testTokenEdgeSquares(rSource, rTarget));
		local bFlank = ModifierStack.getModifierKey("ATT_FLANK") or checkFlanked(rSource, srcNode, rTarget);
		if bFlank then
			rRoll.sDesc = rRoll.sDesc .. " " .. "[FLANK +2]";
			rRoll.nMod = rRoll.nMod + 2;
			
			-- Add "Flanking" effect to the acting character (e.g. for Sneak Attack)
			-- addEffect("", "", srcCTnode, {sName = "Flanking", nDuration = 1, nGMOnly = 0}, false);
			addEffect(rSource, {sName = "Flanking", nDuration = 1, nGMOnly = 0});
		else
			removeEffect(srcCTnode, "Flanking");
		end
	end
	
end

function getRangeToTarget(rSource, rTarget)
	-- Returns the range from source to target
	
	-- are we on a gridded map?
	local srcToken, tgtToken, srcImage, tgtImage = getTokensMaps(rSource, rTarget);
	if srcToken == nil then
		return -1;
	end
	
	return Token.getDistanceBetween(srcToken, tgtToken);
	
end

function getRangeModifier(srcNode, rRoll, nRange)
	-- Get the range penalty based on the distance to target and weapon used
	
	-- Get the name of the weapon being used
	local sWeaponUsed = string.match(rRoll.sDesc, "%]([^%[]*)");
	sWeaponUsed = StringManager.trim(sWeaponUsed):lower();
	local nMaxInc = 0;
	local nRangeInc = 0;
	if ActorManager.isPC(srcNode) then
		-- For a PC, pull the range right from their weapon entry in case of a special
		-- weapon with better (or worse) range
		for _,vWeaponNode in pairs(DB.getChildren(srcNode, "weaponlist")) do
			local sWeaponName = DB.getValue(vWeaponNode, "name"):lower();
			local sWeaponType = DB.getValue(vWeaponNode, "type");  -- 0 M; 1 R; 2 CMB
			if sWeaponName == sWeaponUsed and sWeaponType == 1 then
				nRangeInc = DB.getValue(vWeaponNode, "rangeincrement");
				-- Records imported from PCGen for melee weapons which can also be thrown have a
				-- ranged attack called e.g. "Dagger (Thrown)" with no reference back to the inventory
				-- Bolas are just a wierd case because they are "martial ranged" but thrown
				if string.match(sWeaponName, "thrown") or string.match(sWeaponName, "bolas") then
					nMaxInc = 5;
					break;
				end
				-- The weapon record does not include the item subtype, which we need to figure out
				-- the maximum number of range increments.  For that, we need the inventory record.
				local sClass, sRecordName = DB.getValue(vWeaponNode, "shortcut");
				local vInvNode = DB.findNode(sRecordName);
				if vInvNode ~= nil then
					local sSubType = DB.getValue(vInvNode, "subtype");
					if sSubType ~= nil then
						if string.match(sSubType:lower(), "ranged") then
							nMaxInc = 10;
						else
							nMaxInc = 5;
						end
					else
						nMaxInc = 10;
					end
				end
				break;
			end
		end
	else
		-- For an NPC, get the standard range data for the weapon type
		-- Check for a match against the weapon data
		local tWeaponRangeData = DataCommonCMC.weaponranges[sWeaponUsed];
		if tWeaponRangeData == nil then
			-- It wasn't found; check for a match vs each entry in the
			-- data table in case this weapon has additional words (Mwk, silver, etc.)
			for sWeaponName, tWeaponRangeData in pairs(DataCommonCMC.weaponranges) do
				if string.match(sWeaponUsed, sWeaponName) then
					nRangeInc = tWeaponRangeData[1];
					nMaxInc = tWeaponRangeData[2];
					break;
				end
			end
		else
			nRangeInc = tWeaponRangeData[1];
			nMaxInc = tWeaponRangeData[2];
		end
	end
	
	if nMaxInc == 0 or nRangeInc == 0 then
		-- Weapon wasn't found.  Maybe it is a spell or special ability?
		if hasSpell(srcNode, sWeaponUsed) then
			return 0;
		end
		-- Give a warning in Chat
		local tMsg = {sender = "", font = "emotefont", mood = "ooc"};
		local nMaxRange = nMaxInc * nRangeInc;
		tMsg.text = "Weapon " .. sWeaponUsed .. " not found";
		Comm.deliverChatMessage(tMsg);
		return 0;
	end
	
	local nInc = math.ceil(nRange / nRangeInc);
	
	-- Issue warning if beyond maximum range
	if nInc > nMaxInc then
		local tMsg = {sender = "", font = "emotefont", mood = "ooc"};
		local nMaxRange = nMaxInc * nRangeInc;
		tMsg.text = "Range " .. nRange .. " is beyond the " .. sWeaponUsed .. "'s maximum of " .. nMaxRange;
		Comm.deliverChatMessage(tMsg);
	end
	
	local nRngMod = -2;
	if hasFeat(srcNode, "Far Shot") then
		nRngMod = -1;
	end
	return (nInc - 1) * nRngMod;
	
end

function checkShootMelee(rSource, srcNode, rTarget)
	-- Returns the modifier for shooting into melee:
	-- If the target is engaged with a friendly actor
	--   ("if they are enemies of each other and either threatens the other")
	-- -4 to hit
	-- -2 to hit if the target is 2 or more sizes larger than the friendly
	-- no penalty if the target is 3 or more sizes larger than the friendly
	-- no penalty if the target (or the part being targetted) is 10 or more feet from the friendly
	-- Does not account for adjacent friendlies who are unconcious or otherwise unable to engage
	-- ("An unconscious or otherwise immobilized character is not considered engaged
	--   unless he is actually being attacked.)"
	-- Does not handle the situation of two or more size <-1 creatures fighting in the same space
	
	-- check for Precise Shot feat
	if hasFeat(srcNode, "Precise Shot") then
		return 0;
	end
	
	-- check for "Precise Shot" effect (in case something else ignores this penalty)
	if EffectManager35E.hasEffectCondition(rSource, "Precise Shot") then
		return 0;
	end
	
	-- are we on a gridded map?
	local srcToken, tgtToken, srcImage, tgtImage = getTokensMaps(rSource, rTarget);
	if srcToken == nil then
		return 0;
	end
	
	-- shotX, shotY:  x,y of the targetted grid square, i.e. the closest grid containing the target
	local tgtSpace = DB.getValue(ActorManager.getCTNode(rTarget), "space");
	local tgtSize = ActorManager35E.getSize(rTarget);
	local tgtCoord = {};
	if tgtSpace <= 5 then
		tgtCoord.x, tgtCoord.y = tgtToken.getPosition();
	else
		-- figure out which square of the target is closest to source
		tgtCoord.x, tgtCoord.y = getClosestTargetSquare(rTarget, srcToken, tgtToken, tgtSpace, tgtImage);
	end
	
	local adjTokens = srcImage.getTokensWithinDistance({x=tgtCoord.x, y=(tgtCoord.y * -1)}, 5);
	local srcFaction = DB.getValue(ActorManager.getCTNode(rSource), "friendfoe");
	local nPenalty = 0
	for _,checkToken in pairs(adjTokens) do
		if checkToken ~= srcToken and checkToken ~= tgtToken then
			local adjActor = CombatManager.getCTFromToken(checkToken);
			local adjSize = ActorManager35E.getSize(adjActor);
			-- Ignore adj of -2 or smaller, as they do not threaten outside their square
			if adjSize > -2 then
				local adjFaction = DB.getValue(adjActor, "friendfoe");
				local bCheck = false;
				-- Compare factions to see if adjacent is friendly to target
				if srcFaction == "friend" and adjFaction ~= "foe" then
					bCheck = true;
				elseif srcFaction == "foe" and adjFaction ~= "friend" then
					bCheck = true;
				elseif srcFaction == "neutral" or srcFaction == "" then
					bCheck = true;
				end
				-- Check for size (-4 to +4)
				-- -4 to hit if engaged
				-- -2 if the target is two size categories larger than adjacent friendly
				-- no penalty if target 3+ sizes larger than adjacent friendly
				if bCheck and checkCanThreaten(adjActor, rTarget.sCTNode) then
					nSizeDiff = tgtSize - adjSize;
					if nSizeDiff < 2 then
						return -4;
					elseif nSizeDiff == 2 then
						nPenalty = -2;
					end
				end
			end
		end
	end
	
	return nPenalty;
	
end

function getClosestTargetSquare(rTarget, srcToken, tgtToken, tgtSpace, tgtImage)
	-- return the X,Y of the center of the closest square of tgtToken from srcToken
	
	local tgtEdges = getTokenEdgeSquares(rTarget, tgtToken, tgtImage)
	
	-- Which target edge square is closest to srcToken?
	-- Two squares are often equally close, since ranges are in grid increments (4 straight up is 20',
	-- 3 up 1 diagonal is also 20')
	-- Therefore, don't just use distance between points; look for closest X and closest Y
	local tgtX, tgtY = tgtToken.getPosition();
	local srcX, srcY = srcToken.getPosition();
	local xDiff = math.abs(srcX - tgtX);
	local yDiff = math.abs(srcY - tgtY);
	local xClose = tgtX;
	local yClose = tgtY;
	for _,c in pairs(tgtEdges) do
		local thisDiffX = math.abs(srcX - c.x);
		local thisDiffY = math.abs(srcY - c.y);

		if thisDiffX < xDiff then
			xDiff = thisDiffX;
			xClose = c.x;
		end
		if thisDiffY < yDiff then
			yDiff = thisDiffY;
			yClose = c.y;
		end
	end
	
	return xClose, yClose;
	
end

function checkFlanked(rSource, srcNode, rTarget)
	-- Return true if the rSource is flanking the rTarget
	-- Does not account for the use of weapons with Reach
	
	-- When making a melee attack, you get a +2 flanking bonus if your opponent is threatened by another enemy character or creature on its opposite border or opposite corner.
	-- When in doubt about whether two characters flank an opponent in the middle, trace an imaginary line between the two attackers’ centers. If the line passes through opposite borders of the opponent’s space (including corners of those borders), then the opponent is flanked.
	-- Exception: If a flanker takes up more than 1 square, it gets the flanking bonus if any square it occupies counts for flanking.
	-- Only a creature or character that threatens the defender can help an attacker get a flanking bonus.
	-- Creatures with a reach of 0 feet can’t flank an opponent.
	
	local bFlanked = false;

	if OptionsManager.isOption('AUTO_FLANK', 'on') then
		-- Some creatures can't be flanked; some can be flanked (for purposes of Sneak Attack) but
		-- ignore the +2 bonus
		local bIgnoreFlank, bIgnoreBonus = checkCanBeFlanked(rSource, rTarget);
		if bIgnoreFlank then
			return false;
		end

		-- are we on a gridded map?
		local srcToken, tgtToken, srcImage, tgtImage = getTokensMaps(rSource, rTarget);
		if srcToken == nil then
			return false;
		end

		-- Get all tokens threatening rTarget in the same faction as rSource
		local tThreats = getMeleeThreats(srcToken, tgtToken, DB.getValue(ActorManager.getCTNode(rSource), "friendfoe"));

		-- Get the upper/lower Y and left/right X values of rTarget's edges
		local tTgtBnd = getTokenBounds(rTarget, tgtToken, tgtImage);

		-- Get the coordinate of target's center
		-- local tgtX, tgtY = tgtToken.getPosition();
		local tgtX = (tTgtBnd.left + tTgtBnd.right) / 2;
		local tgtY = (tTgtBnd.top + tTgtBnd.bottom) / 2;

		-- Get the squares around the edge of rSource
		local tSrcEdge = getTokenEdgeSquares(rSource, srcToken, srcImage);

		for _, tknThreat in pairs(tThreats) do
			-- Get edge squares of tknThreat
			local tThrEdge = getTokenEdgeSquares(CombatManager.getCTFromToken(tknThreat), tknThreat, srcImage);

			-- Compare the line from each source edge to each threat edge
			for _, srcCoord in pairs(tSrcEdge) do
				for _, thrCoord in pairs(tThrEdge) do
					-- Is this square of the threat token actually a threat?
					local rThrCT = CombatManager.getCTFromToken(tknThreat);
					local nThrReach = DB.getValue(ActorManager.getCTNode(rThrCT), "reach");
					local nThrRange = srcImage.getDistanceBetween({x = thrCoord.x, y = thrCoord.y * -1}, tgtToken);
					if nThrReach >= nThrRange then
						-- y = mx + b
						-- m = slope = delta Y / delta X
						local slope = (srcCoord.y - thrCoord.y) / (srcCoord.x - thrCoord.x)
						-- b = Y intercept = y - mx
						local yInt = srcCoord.y - (slope * srcCoord.x);

						-- Figure out the Y value where the line intersects left/right target bounds and
						-- the X value where the line intersects top/bottom target bounds
						local tInt = {
							left = slope * tTgtBnd.left + yInt,  -- y = mx + b
							right = slope * tTgtBnd.right + yInt,  -- y = mx + b
							top = (tTgtBnd.top - yInt) / slope,  -- x = (y - b) / m
							bottom = (tTgtBnd.bottom - yInt) / slope  -- x = (y - b) / m
						}
						-- Lines that are straight up (srcCoord.x = thrCoord.x) require special handling
						if srcCoord.x == thrCoord.x then
							tInt.top = srcCoord.x;
							tInt.bottom = srcCoord.x;
						end
						-- If the line intersects both top and bottom between the left and right bounds,
						-- or both left and right between the top and bottom bounds, then it's a flank
						-- Must also be on opposite sides of the target
						if tInt.left >= tTgtBnd.top and tInt.left <= tTgtBnd.bottom and tInt.right >= tTgtBnd.top and tInt.right <= tTgtBnd.bottom then
							-- Line intersects both target's left and right between target's top and bottom
							if (srcCoord.x < tgtX and thrCoord.x > tgtX) or
							   (srcCoord.x > tgtX and thrCoord.x < tgtX) then
							   -- target is between source and threat
								return true;
							end
						end
						if tInt.top <= tTgtBnd.right and tInt.top >= tTgtBnd.left and tInt.bottom <= tTgtBnd.right and tInt.bottom >= tTgtBnd.left then
							-- Line intersects both target's top and bottom between target's left and right
							if (srcCoord.y < tgtY and thrCoord.y > tgtY) or
							   (srcCoord.y > tgtY and thrCoord.y < tgtY) then
							   -- target is between source and threat
								return true;
							end
						end
					end
				end
			end
		end
	end
	return bFlanked;
end

function checkCanBeFlanked(rSource, rTarget)
	-- Check for various conditions which prevent rTarget from being flanked.
	-- Return two booleans:
	--		true if rTarget igrnores flanking completely
	--		true if rTarget can be flanked (for sneak attack) but ignores the +2 bonus (e.g. Formians)
	
	local bIgnoreFlank, bIgnoreBonus = false, true;
	local bTgtPC = ActorManager.isPC(rTarget)
	
	-- subtype "swarm"
	if bTgtPC == false then
		local vTgtNode = ActorManager.getCreatureNode(rTarget);
		local sTgtType = DB.getValue(vTgtNode, "type");
		-- Debug.chat("sTgtType:  ", sTgtType);
		if string.match(DB.getValue(vTgtNode, "type"):lower(), "swarm") then
			return true, false;
		end
	end
	
	-- "all-around vision" in "Senses" (Pathfinder Bestiary 2 Universal Monster Rules)
	
	-- "Immune ... flanking" in "SQ"
	
	-- "IMMUNE: ... flanking" effect
	
	-- wearing Robe of Eyes or Ring of Eyes
	
	-- feat Hand's Sight
	
	-- class ability Improved Uncanny Dodge:  cannot be flanked;
	-- can sneak attack if at least 4 more Rogue levels than the target
	-- (Barbarian, Rogue, Shadowdancer, Assassin, Stalwart Defender)
	
	-- Unflankable
	
	-- Massive (Ex):  can only be flanked by Huge or larger foes
	
	-- feat "Eyes in the Back of Your Head"  can be flanked, but no +2 to hit
	
	return bIgnoreFlank, bIgnoreBonus;
	
end

function getMeleeThreats(srcToken, tgtToken, sSourceFaction)
	-- Get all tokens threatening tgtToken
	--     "colossal" reach is 30', so get all tokens within that distance
	--     check for faction (must be same as source)
	
	local tThreats = {};
	
	local tNearTokens = Token.getTokensWithinDistance(tgtToken, 30);
	
	for _,checkToken in pairs(tNearTokens) do
		local rNearActorCT = CombatManager.getCTFromToken(checkToken);
		-- Debug.chat("rNearActorCT:  ", rNearActorCT, DB.getValue(ActorManager.getCTNode(rNearActorCT), "name"));
		if rNearActorCT then
			local nNearSize = ActorManager35E.getSize(rNearActorCT);
			local nNearReach = DB.getValue(ActorManager.getCTNode(rNearActorCT), "reach");
			-- Ignore if threat is self
			if checkToken ~= srcToken then
				-- Ignore if reach < than range (this will include size -2 or less, as their reach is 0)
				local nNearRange = Token.getDistanceBetween(tgtToken, checkToken);
				-- Debug.chat("nNearRange, nNearReach, nNearSize:  ", nNearRange, nNearReach, nNearSize);
				if nNearRange <= nNearReach then
					-- Ignore if faction is not the same as source's faction
					local sNearFaction = DB.getValue(rNearActorCT, "friendfoe");
					if sNearFaction == sSourceFaction then
						-- Make sure the near actor can threaten
						if checkCanThreaten(rNearActorCT, CombatManager.getCTFromToken(tgtToken)) then
							table.insert(tThreats, checkToken);
						end
					end
				end
			end
		end
	end
	
	return tThreats;
	
end

-- function testTokenEdgeSquares(rSource, rTarget)
	
	-- local srcToken, tgtToken, srcImage, tgtImage = getTokensMaps(rSource, rTarget);
	-- Debug.chat("testTokenEdgeSquares");
	-- Debug.chat(tgtToken.getPosition());
	-- local tknEdge = getTokenEdgeSquares(rTarget, tgtToken, tgtImage)
	-- Debug.chat(tknEdge);
	-- for _, c in pairs(tknEdge) do
		-- Debug.chat(c);
		-- tgtImage.addToken("tokens/Biohazard_symbol_(black_and_yellow).png", c.x, c.y);
	-- end
	
-- end

function getTokenEdgeSquares(rActor, theToken, tknImage)
	-- Returns a table holding the X,Y coordinates of the edge squares of theToken
	
	local tgtSpace = DB.getValue(ActorManager.getCTNode(rActor), "space");
	
	if tgtSpace == 5 then
		local tknX, tknY = theToken.getPosition();
		return {{x = tknX, y = tknY}};
	end
	
	local tknBounds = getTokenBounds(rActor, theToken, tknImage)
	
	local nGridSize = tknImage.getGridSize();
	local nGrid = GameSystem.getDistanceUnitsPerGrid(); -- for 3.5E this is 5
	local nHalfGrid = nGridSize / 2;
	local tgtSide = tgtSpace / nGrid;  -- number of squares per side of the target token
	-- size 1, space 10 (2x2)
	-- size 2, space 15 (3x3)
	-- size 3, space 20 (4x4)
	-- size 4, space 30 (6x6)
	local tknEdge = {};
	-- top/bottom, including corners
	for i = 0.5, tgtSide - 0.5 do
		table.insert(tknEdge, {x = tknBounds.left + (i * nGridSize), y = tknBounds.top + nHalfGrid});
		table.insert(tknEdge, {x = tknBounds.left + (i * nGridSize), y = tknBounds.bottom - nHalfGrid});
		-- table.insert(tknEdge, {y = tknBounds.top + nHalfGrid, x = tknBounds.left + (i * nGridSize)});
		-- table.insert(tknEdge, {y = tknBounds.bottom - nHalfGrid, x = tknBounds.left + (i * nGridSize)});
	end
	-- left/right, excluding corners
	for i = 1.5, tgtSide - 1.5 do
		table.insert(tknEdge, {x = tknBounds.left + nHalfGrid,  y = tknBounds.top + (i * nGridSize)});
		table.insert(tknEdge, {x = tknBounds.right - nHalfGrid, y = tknBounds.top + (i * nGridSize)});
		-- table.insert(tknEdge, {y = tknBounds.top + (i * nGridSize), x = tknBounds.left + nHalfGrid});
		-- table.insert(tknEdge, {y = tknBounds.top + (i * nGridSize), x = tknBounds.right - nHalfGrid});
	end
	
	return tknEdge;
	
end

function getTokenBounds(rActor, theToken, tknImage)
	-- Returns a table holding the the upper and lower Y and left and right X values of theToken
	-- {["top"] = #, ["bottom"] = #, ["left"] = #, ["right"] = #}
	
	local tgtX, tgtY = theToken.getPosition();
	local tgtSpace = DB.getValue(ActorManager.getCTNode(rActor), "space");
	
	local nGrid = GameSystem.getDistanceUnitsPerGrid(); -- for 3.5E this is 5
	local nGridSize = tknImage.getGridSize();  -- usually 50
	local nHalfGrid = nGridSize / 2;
	local tgtSide = tgtSpace / nGrid;  -- number of squares per side of the target token
	
	return {
			["top"]    = tgtY - (tgtSide / 2) * nGridSize;
			["bottom"] = tgtY + (tgtSide / 2) * nGridSize;
			["left"]   = tgtX - (tgtSide / 2) * nGridSize;
			["right"]  = tgtX + (tgtSide / 2) * nGridSize;
		};

end

function getTokensMaps(rSource, rTarget)
	-- Are the tokens for rSource and rTarget both on the same gridded map?
	
	if rTarget == nil or rSource == nil then
		return nil, nil, nil, nil;
	end
	
	local srcToken = CombatManager.getTokenFromCT(rSource.sCTNode);
	local tgtToken = CombatManager.getTokenFromCT(rTarget.sCTNode);
	local srcImage = ImageManager.getImageControl(srcToken);
	local tgtImage = ImageManager.getImageControl(tgtToken);
	if srcImage == nil or tgtImage == nil or srcImage ~= tgtImage or not srcImage.hasGrid() then
		return nil, nil, nil, nil;
	else
		return srcToken, tgtToken, srcImage, tgtImage;
	end
	
	
end

function attackType(rRoll)
	
	local sAttackType = nil;
	if rRoll.sType == "attack" then
		-- Debug.console("rRoll.sDesc:  ", rRoll.sDesc); 
		-- Example  "[ATTACK (M)] Long sword [CRIT 19]"
		-- Example  "[ATTACK (R)] Longbow"
		sAttackType = string.match(rRoll.sDesc, "%[ATTACK.*%((%w+)%)%]");
		if not sAttackType then
			sAttackType = "M";
		end
	elseif rRoll.sType == "grapple" then
		sAttackType = "M";
	end
	
	return sAttackType;
	
end

function hasFeat(actorNode, sFeat)
	
	-- Debug.chat("actorNode:  ", actorNode);
	if actorNode == nil
	then
		return false;
	end
	
	if ActorManager.isPC(actorNode) then
		return CharManager.hasFeat(actorNode, sFeat);
	else
		return npcHasFeat(actorNode, sFeat);
	end
	
end

function checkCanThreaten(nodeActorCT, nodeTargetCT)
	-- Returns true if the rActorCT can threaten enemies in melee;
	-- false if they have a status or effect which renders them unable to do so or
	-- they are unable to see the target
	
	-- Actor conditions
	if EffectManager35E.hasEffectCondition(nodeActorCT, "Unconscious") or
		EffectManager35E.hasEffectCondition(nodeActorCT, "Incapacitated") or
		EffectManager35E.hasEffectCondition (nodeActorCT, "Paralyzed") or
		EffectManager35E.hasEffectCondition(nodeActorCT, "Petrified") or
		EffectManager35E.hasEffectCondition(nodeActorCT, "Stunned") or
		EffectManager35E.hasEffectCondition(nodeActorCT, "Helpless") then
		return false;
	end
	
	-- Actor is flat-footed and doesn't have Combat Reflexes
	if EffectManager35E.hasEffectCondition(nodeActorCT, "Flatfooted") or
		EffectManager35E.hasEffectCondition(nodeActorCT, "Flat-footed") then
		if not hasFeat(nodeActorCT, "Combat Reflexes") then
			return false;
		end
	end
	
	-- Target invisibility
	-- I feel like something is missing here.  Tremorsense/scent?
	-- Also, for NPC Truesight/Blindsight/etc. might not be an effect, just a sense
	if EffectManager35E.hasEffectCondition(nodeTargetCT, "Invisible") then
		if not EffectManager35E.hasEffectCondition(nodeActorCT, "Truesight") and
			not EffectManager35E.hasEffectCondition(nodeActorCT, "Blindsight") then
			return false;
		end
	end
	
	-- Melee weapon check
	local rActorCT = ActorManager.resolveActor(nodeActorCT);
	local nodeActor = ActorManager.getCreatureNode(nodeActorCT);
	if ActorManager.isPC(rActorCT) then
		for _,nodeWeapon in pairs(nodeActor.getChild('.weaponlist').getChildren()) do
			if DB.getValue(nodeWeapon, 'carried', 0) == 2 and DB.getValue(nodeWeapon, 'type', 0) == 0 then
				return true;
			end
		end
	else
		return true;
	end
	
end

function npcHasFeat(ctNode, sFeat)
	
	local sLowerFeat = StringManager.trim(string.lower(sFeat));
	local sFeatList = DB.getValue(ctNode, "feats");
	local sLowerFeatList = StringManager.trim(string.lower(sFeatList));

	return string.match(sLowerFeatList, sLowerFeat);
	
end

function npcHasSQ(ctNode, sQuality)
	
	local sLowerQuality = StringManager.trim(string.lower(sQuality));
	local sQualityList = DB.getValue(ctNode, "specialqualities");
	local sLowerQualityList = StringManager.trim(string.lower(sQualityList));

	return string.match(sLowerQualityList, sLowerQuality);
	
end

function removeEffect(nodeCTEntry, sEffectToRemove)
	-- Using this instead of EffectManager.removeEffect() because we want an exact match
	if not sEffectToRemove then
		return;
	end
	
	for _,nodeEffect in pairs(DB.getChildren(nodeCTEntry, "effects")) do
		if DB.getValue(nodeEffect, "label", "") == sEffectToRemove then
			-- nodeEffect.delete();
			EffectManager.notifyExpire(nodeEffect, 0, true);
			return;
		end
	end
	
end

-- function addEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg)
function addEffect(rSource, rNewEffect)
	-- Check for the effect before adding it.
	-- Just calling EffectManager.addEffect will create a duplicate.
	
	-- Debug.chat(ActorManager.getCTNode(rSource));
	-- Debug.chat(rSource.sCTNode);
	local nodeCT = ActorManager.getCTNode(rSource);
	if not hasEffect(nodeCT, rNewEffect.sName) then
		-- EffectManager.addEffect doesn't work from client
		-- EffectManager.addEffect(sUser, sIdentity, nodeCT, rNewEffect, bShowMsg);
		EffectManager.notifyApply(rNewEffect, rSource.sCTNode);
	end
	
end

function hasEffect(nodeCT, sEffect)
	-- Using this instead of EffectManager35E.hasEffectCondition() because we want an exact match
	-- local nodeCT = ActorManager.getCTNode(rSource);
	
	local nodeEffectsList = nodeCT.createChild("effects");
	if nodeEffectsList then
		for _,nodeEffect in pairs(nodeEffectsList.getChildren()) do
			local sEffectName = DB.getValue(nodeEffect, "label", "");
			if sEffectName == sEffect then
				return true;
			end
		end
	end

	return false;
	
end

function hasSpell(actorNode, sSpell)
	-- returns true if the PC charsheet or NPC CTnode has the spell named sSpell;
	-- returns false if it is not found
	
	for _,vSSN in pairs(DB.getChildren(actorNode, "spellset")) do
		for _,vLevel in pairs(DB.getChildren(vSSN, "levels")) do
			for _,vSpell in pairs(DB.getChildren(vLevel, "spells")) do
				local sSpellName = DB.getValue(vSpell, "name"):lower();
				if sSpellName == sSpell:lower() then
					return true;
				end
			end
		end
	end
	
	return false;
	
end

