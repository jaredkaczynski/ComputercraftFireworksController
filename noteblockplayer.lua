-- +---------------------+------------+---------------------+
-- |                     |            |                     |
-- |                     |  Note API  |                     |
-- |                     |            |                     |
-- +---------------------+------------+---------------------+

-- Note Block Song format + conversion tools:   David Norgren
-- Iron Note Block + NBS loading & playback:   TheOriginalBIT
-- Music player interface & API structure:         Bomb Bloke

-- ----------------------------------------------------------

-- Place Note Block Studio NBS files on your ComputerCraft computer,
-- then play them back via a MoarPeripheral's Iron Note Block!

-- http://moarperipherals.com/index.php?title=Note
-- http://www.computercraft.info/forums2/index.php?/topic/19357-moarperipherals
-- http://www.minecraftforum.net/topic/136749-minecraft-note-block-studio

-- This script can be ran as any other, but it can *also* be loaded as an API!
-- Doing so exposes the following functions:

-- < note.playSong(fileName) >
-- Simply plays the specified NBS file.

-- < note.songEngine([fileName]) >
-- Plays the optionally specified NBS file, but whether one is specified or not, does
-- not return when complete - instead this is intended to run continuously as a background
-- process. Launch it via the parallel API and run it alongside your own script!

--  While the song engine function is active, it can be manipulated by queuing the
--  following events:

--   * musicPlay
--   Add a filename in as a parameter to start playback, eg:
--   os.queueEvent("musicPlay","mySong.nbs")

--   * musicPause
--   Halts playback.

--   * musicResume
--   Resumes playback.

--   * musicSkipTo
--   Add a song position in as a parameter to skip to that segment. Specify the time
--   in tenths of a second; for example, to skip a minute in use 600.

--   Additionally, whenever the song engine finishes a track, it will automatically
--   throw a "musicFinished" event, or a "newTrack" event whenever a new song is loaded.

--  **Remember!** The API cannot respond to these events until YOUR code yields!
--  Telling it to load a new song or jump to a different position won't take effect
--  until you pull an event or something!

-- < note.setPeripheral(targetDevice1, [targetDevice2,] ...) >
-- By default, upon loading the API attaches itself to any Iron Note Blocks it detects.
-- Use this if you have specific note block(s) in mind, or wish to use different blocks
-- at different times - perhaps mid-song! Returns true if at least one of the specified
-- devices was valid, or false if none were.

--  **Note!** The Iron Note Block peripheral can currently play up to five instruments
--            at any given moment. Providing multiple blocks to the API will cause it to
--            automatically spread the load for those songs that need the extra notes.
--            If you provide insufficient blocks, expect some notes to be skipped from
--            certain songs.

--            Very few songs (if any) require more than two Iron Note Blocks.

-- < note.isPlaying() >
-- Returns whether the API is currently mid-tune (ignoring whether it's paused or not).

-- < note.isPaused() >
-- Returns whether playback is paused.

-- < note.getSongLength() >
-- Returns the song length in "redstone updates". There are ten updates per second, or
-- one per two game ticks.

-- < note.getSongPosition() >
-- Returns the song position in "redstone updates". Time in game ticks is 2 * this. Time
-- in seconds is this / 10.

-- < note.getSongSeconds() >
-- Returns the song length in seconds.

-- < note.getSongPositionSeconds() >
-- Returns the song position in seconds.

-- < note.getSongTempo() >
-- Returns the song tempo, representing the "beats per second".
-- Eg: 2.5 = one beat per 0.4 seconds.
--       5 = one beat per 0.2 seconds.
--      10 = one beat per 0.1 seconds.

-- ... or whatever the song happens to be set to.
-- "Should" be a factor of ten, but lots of NBS files have other tempos.

-- < note.getSongName() >
-- Returns the name of the song.

-- < note.getSongAuthor() >
-- Returns the name of the NBS file author.

-- < note.getSongArtist() >
-- Returns the name of the song artist.

-- < note.getSongDescription() >
-- Returns the song's description.

--getvol, setvol, registerRemoteSpeaker

-- ----------------------------------------------------------

-- Cranking this value too high will cause crashes:
local MAX_INSTRUMENTS_PER_NOTE_BLOCK = 5

local CCver

do
	local vers = {{_HOST, tonumber(_HOST and _HOST:match("%d+.%d+"))}, {_CC_VERSION, tonumber(_CC_VERSION)},
		{textutils.serializeJSON, 1.7}, {paintutils.drawBox, 1.64}, {fs.getDir, 1.63},
		{term.current, 1.6}}

	for i = 1, #vers do if vers[i][1] then
		CCver = vers[i][2]
		break
	end end

	if not CCver then error("Sorry, CC 1.6 or later is required.") end
end

if not shell then
	-- -----------------------
	-- Load as API:
	-- -----------------------
	
	local volume, paused, cTick, song, remote, haveVolume = 1
	
	local translate = {[0]=0,4,1,2,3}

	local noteName = {[0]="harp", "basedrum", "snare", "hat", "bass"}
	
	-- Returns functions for each found "note block" attached; these take instrument/pitch/volume as their parameters.
	function getNoteblocks()
		local ironnote = {}
		haveVolume = false
		
		if peripheral.find("iron_note") then
			-- MoarPeripherals Iron Note Block
			local ironnote = {peripheral.find("iron_note")}
			
			for i = 1, #ironnote do
				local func = ironnote[i].playNote
				ironnote[i] = function(inst, pitch, vol) func(inst, pitch) end
			end

		elseif peripheral.find("speaker") then
			-- ComputerCraft Speaker
			ironnote = {peripheral.find("speaker")}
			haveVolume = true
			MAX_INSTRUMENTS_PER_NOTE_BLOCK = 20  -- Computronics crashes if spamming too many notes. Not sure what the safe limit is.

			for i = 1, #ironnote do
				local func = ironnote[i].playNote
				ironnote[i] = function(inst, pitch, vol) func(noteName[inst], vol * 3, pitch) end
			end

		elseif peripheral.find("iron_noteblock") then
			-- Computronics Iron Note Block
			ironnote = {peripheral.find("iron_noteblock")}
			haveVolume = true
			MAX_INSTRUMENTS_PER_NOTE_BLOCK = 20  -- Beats me what the real limit is here but 20 should be plenty anyways.

			for i = 1, #ironnote do
				local func = ironnote[i].playNote
				ironnote[i] = function(inst, pitch, vol) func(inst, pitch, vol / 10) end  -- NFI why volume works like this with Computronics.
			end

		elseif peripheral.find("neuralInterface", function(side, periph) return periph.hasModule("minecraft:noteblock") end)
				or peripheral.find("Music")
				or peripheral.find("minecraft:noteblock") then
				
			-- Plethora Note Block module
			ironnote = {peripheral.find("neuralInterface", function(side, periph) return periph.hasModule("minecraft:noteblock") end)}
			if #ironnote == 0 then ironnote = {peripheral.find("Music")} end
			if #ironnote == 0 then ironnote = {peripheral.find("minecraft:noteblock")} end
			
			haveVolume = true
			MAX_INSTRUMENTS_PER_NOTE_BLOCK = 20  -- Beats me what the real limit is here but 20 should be plenty anyways.
			
			for i = 1, #ironnote do 
				local play = ironnote[i].playNote
				ironnote[i] = function(inst, pitch, vol) if vol >= 0.1 then coroutine.resume(coroutine.create(play), inst, pitch, vol) end end  -- Don't ask
			end

		elseif commands then
			-- Command Computer synth
			haveVolume = true
			MAX_INSTRUMENTS_PER_NOTE_BLOCK = 20

			local comPart = {}
			for i = 0, 24 do comPart[i] = 1 / 24 * i end  -- If it looks wrong, that's not my bug: https://bugs.mojang.com/browse/MC-80658
			local comPitch = {0.5, 0.53, 0.56, 0.6, 0.63, 0.67, 0.7, 0.75, 0.8, 0.84, 0.9, 0.95, 1.0, 1.05, 1.1, 1.2, 1.25, 1.32, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0}
			
			if _HOST and not _HOST:find("Minecraft 1.8") then  -- MC 1.9 or higher
				local comSound = {[0] = "block.note.harp", "block.note.basedrum", "block.note.snare", "block.note.hat", "block.note.bass"}
				
				ironnote = {function(inst, pitch, vol)
					commands.execAsync("playsound " .. comSound[inst] .. " block @a ~ ~ ~ " .. tostring(vol) .. " " .. tostring(comPitch[pitch]))
					commands.execAsync("particle note ~ ~1 ~ " .. tostring(comPart[pitch]) .. " 0 0 1")
				end}
			else
				local comSound = {[0] = "note.harp", "note.bd", "note.snare", "note.hat", "note.bass"}
				
				ironnote = {function(inst, pitch, vol)
					commands.execAsync("playsound " .. comSound[inst] .. " @a ~ ~ ~ " .. tostring(vol) .. " " .. tostring(comPitch[pitch]))
					commands.execAsync("particle note ~ ~1 ~ " .. tostring(comPart[pitch]) .. " 0 0 1")
				end}
			end
		end
		
		return unpack(ironnote)
	end
	
	local ironnote = {getNoteblocks()}
	
	local function assert(cdn, msg, lvl)
		if not cdn then
			error(msg or "assertion failed!", (lvl == 0 and 0 or lvl and (lvl + 1) or 2))
		end
		return cdn
	end
	
	-- Returns a string ComputerCraft can render.
	local safeString = CCver < 1.76 and
			function(text)
				local newText = {}
				for i = 1, #text do
					local val = text:byte(i)
					newText[i] = (val > 31 and val < 127) and val or 63
				end
				return string.char(unpack(newText))
			end
		or function(text) return text end

	-- Returns the song length.
	function getSongLength()
		if type(song) == "table" then return song.length end
	end
	
	-- Returns the song position.
	function getSongPosition()
		return cTick
	end
	
	-- Returns the song length in seconds.
	function getSongSeconds()
		if type(song) == "table" then return song.length / song.tempo end
	end
	
	-- Returns the song position in seconds.
	function getSongPositionSeconds()
		if type(song) == "table" then return cTick / song.tempo end
	end
	
	-- Returns the tempo the song will be played at.
	function getSongTempo()
		if type(song) == "table" then return song.tempo end
	end
	
	-- Switches to a different playback device.
	function setPeripheral(...)
		local newironnote = {}
		
		for i=1,#arg do if type(arg[i]) == "string" and peripheral.getType(arg[i]) == "iron_note" then
			newironnote[#newironnote+1] = peripheral.wrap(arg[i])
		elseif type(arg[i]) == "table" and arg[i].playNote then
			newironnote[#newironnote+1] = arg[i]
		end end
		
		if #newironnote > 0 then
			ironnote = newironnote
			for i = 1, #ironnote do ironnote[i] = ironnote[i].playNote end
			return true
		else return false end
	end
	
	-- Switch to a remote playback device.
	function registerRemoteSpeaker(speakerID)
		if type(speakerID) ~= "number" and type(speakerID) ~= "string" then error("note.registerRemoteSpeaker: Expected: string (host name) or number (system ID). Got: "..type(speakerID)) end
		speakerID = (not tonumber(speakerID)) and (rednet.lookup("MoarPNoteSpeaker", speakerID) or speakerID) or tonumber(speakerID)
		if type(speakerID) ~= "number" then error("note.registerRemoteSpeaker: Rednet lookup failure on host \""..speakerID.."\".") end
		
		rednet.send(speakerID, "Hello?", "MoarPNoteSpeaker")
		local incoming = {rednet.receive(10)}
		if incoming[1] then haveVolume = incoming[2] else error("note.registerRemoteSpeaker: No reply from system ID "..speakerID..".", 2) end
		remote = speakerID
	end
	
	-- Returns whether music is loaded for playback.
	function isPlaying()
		return type(song) == "table"
	end
	
	-- Returns whether playback is paused.
	function isPaused()
		return paused
	end
	
	-- Returns the name of the song.
	function getSongName()
		if type(song) == "table" then return song.name end
	end
	
	-- Returns the name of NBS file author.
	function getSongAuthor()
		if type(song) == "table" then return song.author end
	end
	
	-- Returns the name of song artist.
	function getSongArtist()
		if type(song) == "table" then return song.originalauthor end
	end
	
	-- Returns the song's description.
	function getSongDescription()
		if type(song) == "table" then return song.description end
	end
	
	-- Gets the current volume level (between 0 and 1, inclusive).
	function getVolumeLevel()
		return haveVolume and volume
	end
	
	-- Sets the current volume level (between 0 and 1, inclusive).
	function setVolumeLevel(newVolume)
		assert(type(newVolume) == "number", "note.setVolumeLevel(): Invalid argument.")
		
		if newVolume > 1 then
			volume = 1
		elseif newVolume < 0 then
			volume = 0
		else volume = newVolume end
		
		if remote then rednet.send(remote, volume, "MoarPNoteSpeaker") end
	end
	
	local function byte_lsb(handle)
		return assert(handle.read(), "Note NBS loading error: Unexpected EOF (end of file).", 2)
	end

	local function int16_lsb(handle)
		return bit.bor(bit.blshift(byte_lsb(handle), 8), byte_lsb(handle))
	end

	local function int16_msb(handle)
		local x = int16_lsb(handle)
		--# convert little-endian to big-endian
		local y = 0
		y = y + bit.blshift(bit.band(x, 0x00FF), 8)
		y = y + bit.brshift(bit.band(x, 0xFF00), 8)
		return y
	end

	local function int32_lsb(handle)
		return bit.bor(bit.blshift(int16_lsb(handle), 16), int16_lsb(handle))
	end

	local function int32_msb(handle)
		local x = int32_lsb(handle)
		--# convert little-endian to big-endian
		local y = 0
		y = y + bit.blshift(bit.band(x, 0x000000FF), 24)
		y = y + bit.brshift(bit.band(x, 0xFF000000), 24)
		y = y + bit.blshift(bit.band(x, 0x0000FF00), 8)
		y = y + bit.brshift(bit.band(x, 0x00FF0000), 8)
		return y
	end

	local function nbs_string(handle)
		local str = ""
		for i = 1, int32_msb(handle) do
			str = str..string.char(byte_lsb(handle))
		end
		return str
	end

	local function readNbs(path)
		assert(fs.exists(path), "Note NBS loading error: File \""..path.."\" not found. Did you forget to specify the containing folder?", 0)
		assert(not fs.isDir(path), "Note NBS loading error: Specified file \""..path.."\" is actually a folder.", 0)
		local handle = fs.open(path, "rb")

		local newSong = { notes = {}; }

		--# NBS format found on http://www.stuffbydavid.com/nbs
		--# Part 1: Header
		newSong.length = int16_msb(handle)
		local layers = int16_msb(handle)
		newSong.name = safeString(nbs_string(handle))
		newSong.author = safeString(nbs_string(handle))
		newSong.originalauthor = safeString(nbs_string(handle))
		newSong.description = safeString(nbs_string(handle))
		newSong.tempo = int16_msb(handle)/100
		
		byte_lsb(handle) --# auto-saving has been enabled (0 or 1)
		byte_lsb(handle) --# The amount of minutes between each auto-save (if it has been enabled) (1-60)
		byte_lsb(handle) --# The time signature of the song. If this is 3, then the signature is 3/4. Default is 4. This value ranges from 2-8
		int32_msb(handle) --# The amount of minutes spent on the project
		int32_msb(handle) --# The amount of times the user has left clicked
		int32_msb(handle) --# The amount of times the user has right clicked
		int32_msb(handle) --# The amount of times the user have added a block
		int32_msb(handle) --# The amount of times the user have removed a block
		nbs_string(handle) --# If the song has been imported from a .mid or .schematic file, that file name is stored here (Only the name of the file, not the path)

		--# Part 2: Note Blocks
		local maxPitch = 24
		local notes = newSong.notes
		local tick = -1
		local jumps = 0
		while true do
			jumps = int16_msb(handle)
			if jumps == 0 then
				break
			end
			tick = tick + jumps
			local layer = -1
			while true do
				jumps = int16_msb(handle)
				if jumps == 0 then
					break
				end
				layer = layer + jumps
				local inst = byte_lsb(handle)
				local key = byte_lsb(handle)
				--
				notes[tick] = notes[tick] or {}
				table.insert(notes[tick], {inst = translate[inst]; pitch = math.max((key-33)%maxPitch,0); volume = layer})
			end
		end
		
		--# Part 3: Layers
		local volume = {}
		for i = 0, layers - 1 do
			nbs_string(handle)
			volume[i] = byte_lsb(handle) / 100
		end
		for i = 0, tick do if notes[i] then for _,note in pairs(notes[i]) do note.volume = volume[note.volume] or 1 end end end
		
		--# Part 4: Custom Instruments
		--# Ignored at this time.
		
		handle.close()
		
		song = newSong
	end

	function songEngine(targetSong)
		assert(remote or ironnote[1] or commands, "Note songEngine failure: No Iron Note Blocks assigned.", 0)
		
		local haveVolume, tTick, curPeripheral, delay, notes, endTime = getVolumeLevel() ~= nil, os.startTimer(0.1), 1
		
		if targetSong then os.queueEvent("musicPlay",targetSong) end
	
		modem = peripheral.wrap("bottom")
		
		modem.open(123)
				
		while true do
			local e = { os.pullEvent() }
			
			if e[1] == "timer" and e[2] == tTick and song and not paused then
				if cTick % 10 == 0 then
					redstone.setBundledOutput("back",0)
					redstone.setBundledOutput("left",0)
				end
				if notes[cTick] then
					--if not remote then
						local curMaxNotes, nowPlaying = (song.tempo == 20 and math.floor(MAX_INSTRUMENTS_PER_NOTE_BLOCK/2) or MAX_INSTRUMENTS_PER_NOTE_BLOCK) * #ironnote, 0
						for _,note in pairs(notes[cTick]) do
							-- tick
							if note.inst == 3 then
								print(note.inst)
								if note.pitch > 15 then
								else
								redstone.setBundledOutput("back",2^(note.pitch))
								end
							--snare
							elseif note.inst == 2 then
								print(note.inst)
								if note.pitch > 15 then
								else
								redstone.setBundledOutput("left",2^(note.pitch))
								end
							--Special modem mode
							elseif note.inst == 1 then
								print(note.inst)
								if note.pitch > 15 then
								else
								modem.transmit(123,1,note.pitch)
								end
							else
								ironnote[curPeripheral](note.inst, note.pitch, note.volume * volume)
								curPeripheral = (curPeripheral == #ironnote) and 1 or (curPeripheral + 1)
								nowPlaying = nowPlaying + 1
								if nowPlaying == curMaxNotes then break end
							end
						end

					--else 
					rednet.send(remote, notes[cTick], "MoarPNoteSpeaker") 
					--end
				end
				
				cTick = cTick + 1

				if cTick > song.length then
					song = nil
					notes = nil
					cTick = nil
					os.queueEvent("musicFinished")
					redstone.setBundledOutput("back",0)
					redstone.setBundledOutput("left",0)
				else tTick = os.startTimer(endTime - (delay * (song.length + 1 - cTick)) - os.clock()) end
				
			elseif e[1] == "musicPause" then
				paused = true
			elseif e[1] == "musicResume" then
				paused = false
				endTime = os.clock() + (delay * (song.length + 1 - cTick))
				tTick = os.startTimer(delay)
			elseif e[1] == "musicSkipTo" then
				cTick = e[2]
				endTime = os.clock() + (delay * (song.length + 1 - cTick))
			elseif e[1] == "musicPlay" then
				readNbs(e[2])
				notes = song.notes
				cTick = 0
				tTick = os.startTimer(0.1)
				paused = false
				delay = (100 / song.tempo) / 100
				endTime = os.clock() + (delay * (song.length + 1))
				os.queueEvent("newTrack")
			end
		end
	end
	
	function playSong(targetSong)
		parallel.waitForAny(function () songEngine(targetSong) end, function () os.pullEvent("musicFinished") end)
	end
else
	-- -----------------------
	-- Run as jukebox:
	-- ------------------------------------------------------------
	
	-- Ignore everything below this point if you're only interested
	-- in the API, unless you want to see example usage.
	
	-- ------------------------------------------------------------
	
	sleep(0)  -- 'cause ComputerCraft is buggy.
	
	os.loadAPI(shell.getRunningProgram())
	
	local startDir, playmode, lastSong, marqueePos, blackText, myEvent, bump, marquee, xSize, ySize, logo, buttons, termBlit, dot = shell.resolve("."), 0, {}, 1
	local playInitials = {{"R", 8}, {"N", 6}, {"M", 5}}
	local cursor = {{">>  ","  <<"},{"> > "," < <"},{" >> "," << "},{"> > "," < <"}}

	if term.blit then
		termBlit = term.blit
	else
		local colourNum, hex = {}, "0123456789abcdef"
		for i = 1, 16 do colourNum[hex:sub(i, i)] = 2 ^ (i - 1) end
		
		termBlit = function(t, tC, bC)
			local curChars, curFG, curBG = {t:sub(1, 1)}, tC:sub(1, 1), bC:sub(1, 1)
			
			for i = 2, #t do
				local cT, cTC, cBC = t:sub(i, i), tC:sub(i, i), bC:sub(i, i)
				
				if cTC ~= curFG or cBC ~= curBG then
					term.setTextColour(colourNum[curFG])
					term.setBackgroundColour(colourNum[curBG])
					term.write(table.concat(curChars))
					curChars, curFG, curBG = {cT}, cTC, cBC
				else curChars[#curChars + 1] = cT end
			end

			term.setTextColour(colourNum[curFG])
			term.setBackgroundColour(colourNum[curBG])
			term.write(table.concat(curChars))
		end
	end
	
	if CCver >= 1.74 then  -- ToDo: If adding support for older CC vers, check this for pre-1.55
		blackText = colours.grey
	else
		blackText = colours.black
	end

	if CCver >= 1.76 then
		logo = {{"\149\139\128\148\149\152\140\144\149\140\156\132\149\156\140\132",
			"\149\149\137\149\149\149\128\149\149\128\149\128\149\151\131\128",
			"\149\133\128\133\149\137\140\129\149\128\133\128\149\141\140\132"},
			{"788b7bbb7bbb7bbb", "7bbb7b8b78b87bb8", "7b8b7bbb78b87bbb"},
			{"8b88888888888888", "8888888888888888", "8888888888888888"}}
		
		buttons = {{{{"\151\128\135\148", "\149\145\128\149", "\138\128\139\133"},
			{"\151\139\128\148", "\149\128\157\149", "\138\135\128\133"},
			{"\151\128\148", "\149\128\149", "\138\128\133"},
			{"\151\144\128", "\149\128\132", "\138\129\128"}},
			{{"7773", "7733", "3733"}, {"7773", "7333", "3373"}, {"773", "773", "373"}, {"737", "733", "337"}},
			{{"3737", "3337", "7777"}, {"3377", "3377", "7777"}, {"377", "377", "777"}, {"377", "337", "777"}}},
			
			{{{"\149\135\149", "\149\139\149"}, {"\149\139\149", "\149\135\149"}, {"\149\128\149", "\149\128\149"}, {"\149\130\144", "\149\159\129"}},
			{{"773", "733"}, {"773", "733"}, {"773", "773"}, {"773", "733"}},
			{{"337", "377"}, {"337", "377"}, {"377", "377"}, {"337", "377"}}}}
		
		dot = "\007"
	else
		logo = {{" | | +-+ --- +--", " |\\| | |  |  |- ", " | | +-+  |  +--"},
			{"bbbbbbbbbbbbbbbb", "bbbbbbbbbbbbbbbb", "bbbbbbbbbbbbbbbb"},
			{"7888788878887888", "7888788878887888", "7888788878887888"}}
		
		buttons = {{{{"| /|","|< |","| \\|"}, {"|\\ |","| >|","|/ |"}, {"| |","| |","| |"}, {"|\\ ","| >","|/ "}},
			{{"3333", "3333", "3333"}, {"3333", "3333", "3333"}, {"333", "333", "333"}, {"333", "333", "333"}},
			{{"7777", "7777", "7777"}, {"7777", "7777", "7777"}, {"777", "777", "777"}, {"777", "777", "777"}}},
		
			{{{"|/|","|\\|"}, {"|\\|","|/|"},{"| |","| |"}, {"|\\ ","|/ "}},
			{{"333", "333"}, {"333", "333"}, {"333", "333"}, {"333", "333"}},
			{{"777", "777"}, {"777", "777"}, {"777", "777"}, {"777", "777"}}}}
		
		dot = "O"
	end
	
	if not term.isColour() then
		local function monochrome(txt)
			local result = {}
			for i = 1, #txt do
				local char = txt:sub(i, i)
				result[i] = (CCver >= 1.74) and ((char == "3" or char == "b") and "0" or char) or ((char == "7" or char == "8") and "f" or "0")
			end
			return table.concat(result)
		end
		
		for i = 1, 3 do logo[2][i], logo[3][i] = monochrome(logo[2][i]), monochrome(logo[3][i]) end
		
		for i = 1, 2 do for j = 2, 3 do for k = 1, 4 do
			local thisTab = buttons[i][j][k]
			for l = 1, #thisTab do thisTab[l] = monochrome(thisTab[l]) end
		end end end
	end
	
	-- Returns whether a click was performed at a given location.
	-- If one parameter is passed, it checks to see if y is [1].
	-- If two parameters are passed, it checks to see if x is [1] and y is [2].
	-- If three parameters are passed, it checks to see if x is between [1]/[2] (non-inclusive) and y is [3].
	-- If four paramaters are passed, it checks to see if x is between [1]/[2] and y is between [3]/[4] (non-inclusive).
	local function clickedAt(...)
		if myEvent[1] ~= "mouse_click" then return false end
		if #arg == 1 then return (arg[1] == myEvent[4])
		elseif #arg == 2 then return (myEvent[3] == arg[1] and myEvent[4] == arg[2])
		elseif #arg == 3 then return (myEvent[3] > arg[1] and myEvent[3] < arg[2] and myEvent[4] == arg[3])
		else return (myEvent[3] > arg[1] and myEvent[3] < arg[2] and myEvent[4] > arg[3] and myEvent[4] < arg[4]) end
	end

	-- Returns whether one of a given set of keys was pressed.
	local function pressedKey(...)
		if myEvent[1] ~= "key" then return false end
		for i=1,#arg do if arg[i] == myEvent[2] then return true end end
		return false
	end

	-- Ensures the display is suitable for play.
	local function enforceScreenSize()
		term.setTextColor(colours.white)
		term.setBackgroundColor(colours.black)
		
		while true do
			xSize, ySize = term.getSize()
			term.clear()
			
			if xSize < 26 or ySize < 7 then
				term.setCursorPos(1,1)
				print("Display too small!\n")
				local myEvent = {os.pullEvent()}
				if myEvent[1] == "mouse_click" or myEvent[1] == "key" then error() end
			else return end
		end
	end

	local function drawPlaymode()
		term.setBackgroundColour(term.isColour() and colours.lightGrey or colours.black)
		term.setTextColour(term.isColour() and colours.black or colours.white)
		
		if xSize > 49 then
			term.setCursorPos(bump+34, 1)
			term.write("[R]epeat    ( )")
			term.setCursorPos(bump+34, 2)
			term.write("Auto-[N]ext ( )")
			term.setCursorPos(bump+34, 3)
			term.write("[M]ix       ( )")

			if playmode ~= 0 then
				term.setTextColour(term.isColour() and colours.blue or colours.white)
				term.setCursorPos(bump+47, playmode)
				term.write(dot)
			end
		else
			term.setCursorPos(xSize - 12, 1)
			term.write("   [R]epeat")
			term.setCursorPos(xSize - 12, 2)
			term.write("Auto-[N]ext")
			term.setCursorPos(xSize - 12, 3)
			term.write("      [M]ix")
			
			if playmode ~= 0 then
				term.setTextColour(term.isColour() and colours.blue or colours.black)
				if not term.isColour() then term.setBackgroundColour(colours.white) end
				term.setCursorPos(xSize - playInitials[playmode][2], playmode)
				term.write(playInitials[playmode][1])
			end
		end
	end
	
	local function drawVolumeBar()
		term.setCursorPos(9,ySize-2)
		term.setBackgroundColour(term.isColour() and colours.brown or colours.black)
		term.setTextColour(term.isColour() and colours.red or colours.white)
		term.write("-")
		
		term.setBackgroundColour(term.isColour() and colours.white or colours.black)
		term.setTextColour(term.isColour() and colours.lightGrey or blackText)
		term.write(string.rep("V", xSize - 18))
		
		term.setBackgroundColour(term.isColour() and colours.green or colours.black)
		term.setTextColour(term.isColour() and colours.lime or colours.white)
		term.write("+")
		
		term.setTextColour(term.isColour() and colours.blue or colours.white)
		term.setBackgroundColour(colours.black)
		term.setCursorPos(10+(xSize-19)*note.getVolumeLevel(),ySize-2)
		term.write(dot)
	end
	
	local function drawInterface()
		if term.isColour() then
			-- Header / footer.
			term.setBackgroundColour(colours.grey)
			for i = 1, 3 do
				term.setCursorPos(1,i)
				term.clearLine()
				term.setCursorPos(1,ySize-i+1)
				term.clearLine()
			end
			
			-- Quit button.
			term.setTextColour(colours.white)
			term.setBackgroundColour(colours.red)
			term.setCursorPos(xSize,1)
			term.write("X")
		end

		if xSize > 49 then
			-- Note logo.
			local t, tC, bC = logo[1], logo[2], logo[3]
			for i = 1, 3 do
				term.setCursorPos(1, i)
				termBlit(t[i], tC[i], bC[i])
			end
			
			-- Skip back / forward buttons.
			t, tC, bC = buttons[1][1], buttons[1][2], buttons[1][3]
			for j = 0, 1 do for i = 1, 3 do
				term.setCursorPos(bump + 17 + j * 11, i)
				termBlit(t[j+1][i], tC[j+1][i], bC[j+1][i])
			end end
		else
			-- Note logo.
			term.setTextColour(term.isColour() and colours.blue or colours.white)
			term.setBackgroundColour(term.isColour() and colours.lightGrey or colours.black)
			term.setCursorPos(3, 1)
			term.write(" N O T E ")
	
			-- Skip back / forward buttons.
			local t, tC, bC = buttons[2][1], buttons[2][2], buttons[2][3]
			for j = 0, 1 do for i = 1, 2 do
				term.setCursorPos(2 + j * 8, i + 1)
				termBlit(t[j+1][i], tC[j+1][i], bC[j+1][i])
			end end
		end
		
		-- Progress bar.
		term.setCursorPos(2,ySize-1)
		term.setTextColour(term.isColour() and colours.black or colours.white)
		term.setBackgroundColour(term.isColour() and colours.lightGrey or colours.black)
		term.write("|"..string.rep("=",xSize-4).."|")
		
		drawPlaymode()
		if note.getVolumeLevel() then drawVolumeBar() end
	end
	
	local function startSong(newSong)
		if #lastSong == 32 then lastSong[32] = nil end
		table.insert(lastSong,1,newSong)
		os.queueEvent("musicPlay",newSong)
		marquee = nil
		marqueePos = 1
	end
	
	local function noteMenu()
		local lastPauseState, dragX = "maybe"
		bump = math.floor((xSize - 49) / 2) + 1
		drawInterface()
		
		while true do
			local displayList, position, lastPosition, animationTimer, curCount, gapTimer, lastProgress = {}, 1, 0, os.startTimer(0), 1
			if #shell.resolve(".") > 0 then displayList[1] = ".." end

			do
				local fullList = fs.list(shell.resolve("."))
				table.sort(fullList, function (a, b) return string.lower(a) < string.lower(b) end)
				for i = 1, #fullList do if fs.isDir(shell.resolve(fullList[i])) then displayList[#displayList + 1] = fullList[i] end end
				for i = 1, #fullList do if fullList[i]:sub(#fullList[i]-3):lower() == ".nbs" then displayList[#displayList + 1] = fs.getName(fullList[i]) end end
			end

			while true do
				myEvent = {os.pullEvent()}
				
				if myEvent[1] == "mouse_click" then dragX = (myEvent[4] == ySize) and myEvent[3] or nil end
				
				-- Track animations (bouncing, function (a, b) return string.lower(a) < string.lower(b) end cursor + scrolling marquee).
				if myEvent[1] == "timer" and myEvent[2] == animationTimer then
					if marquee then marqueePos = marqueePos == #marquee and 1 or (marqueePos + 1) end
					curCount = curCount == 4 and 1 or (curCount + 1)
					animationTimer = os.startTimer(0.5)
					myEvent[1] = "cabbage"
					
				-- Queue a new song to start playing, based on the playmode toggles (or if the user clicked the skip-ahead button).
				elseif (myEvent[1] == "timer" and myEvent[2] == gapTimer and not note.isPlaying()) or (pressedKey(keys.d,keys.right) or (xSize > 49 and clickedAt(bump+27,bump+32,0,4) or clickedAt(9,13,1,4))) then
					if playmode == 1 then
						os.queueEvent("musicPlay",lastSong[1])
					elseif (playmode == 2 or (playmode == 0 and myEvent[1] ~= "timer")) and not fs.isDir(shell.resolve(displayList[#displayList])) then
						if shell.resolve(displayList[position]) == lastSong[1] or fs.isDir(shell.resolve(displayList[position])) then repeat
							position = position + 1
							if position > #displayList then position = 1 end
						until not fs.isDir(shell.resolve(displayList[position])) end
						
						startSong(shell.resolve(displayList[position]))
					elseif playmode == 3 and not fs.isDir(shell.resolve(displayList[#displayList])) then
						repeat position = math.random(#displayList) until not fs.isDir(shell.resolve(displayList[position]))
						startSong(shell.resolve(displayList[position]))
					end
					
					gapTimer = nil
					myEvent[1] = "cabbage"
				
				elseif myEvent[1] ~= "timer" then   -- Special consideration, bearing in mind that the songEngine is spamming ten such events a second...
					-- Move down the list.
					if pressedKey(keys.down,keys.s) or (myEvent[1] == "mouse_scroll" and myEvent[2] == 1) then
						position = position == #displayList and 1 or (position + 1)

					-- Move up the list.
					elseif pressedKey(keys.up,keys.w) or (myEvent[1] == "mouse_scroll" and myEvent[2] == -1) then
						position = position == 1 and #displayList or (position - 1)

					-- Start a new song.
					elseif pressedKey(keys.enter, keys.space) or ((xSize > 49 and clickedAt(bump+22,bump+26,0,4) or clickedAt(5,9,1,4)) and not note.isPlaying()) or clickedAt(math.floor(ySize / 2) + 1) then
						if fs.isDir(shell.resolve(displayList[position])) then
							shell.setDir(shell.resolve(displayList[position]))
							break
						else startSong(shell.resolve(displayList[position])) end

					-- User clicked somewhere on the file list; move that entry to the currently-selected position.
					elseif clickedAt(0, xSize + 1, 3, ySize - 2) then
						position = position + myEvent[4] - math.floor(ySize / 2) - 1
						position = position > #displayList and #displayList or position
						position = position < 1 and 1 or position

					-- Respond to a screen-resize; triggers a full display redraw.
					elseif myEvent[1] == "term_resize" or myEvent[1] == "monitor_resize" then
						enforceScreenSize()
						bump = math.floor((xSize - 49) / 2) + 1
						lastPosition = 0
						drawInterface()
						animationTimer = os.startTimer(0)
						lastPauseState = "maybe"

					-- Quit.
					elseif pressedKey(keys.q, keys.x, keys.t) or clickedAt(xSize, 1) then
						if myEvent[1] == "key" then os.pullEvent("char") end
						os.unloadAPI("note")
						term.setTextColour(colours.white)
						term.setBackgroundColour(colours.black)
						term.clear()
						term.setCursorPos(1,1)
						print("Thanks for using the Note NBS player!\n")
						shell.setDir(startDir)
						error()

					-- Toggle repeat mode.
					elseif pressedKey(keys.r) or (xSize > 49 and clickedAt(bump + 33, bump + 49, 1)) or (xSize < 50 and clickedAt(xSize - 13, xSize - 1, 1)) then
						playmode = playmode == 1 and 0 or 1
						drawPlaymode()

					-- Toggle auto-next mode.
					elseif pressedKey(keys.n) or (xSize > 49 and clickedAt(bump + 33, bump + 49, 2)) or (xSize < 50 and clickedAt(xSize - 13, xSize - 1, 2)) then
						playmode = playmode == 2 and 0 or 2
						drawPlaymode()

					-- Toggle mix (shuffle) mode.
					elseif pressedKey(keys.m) or (xSize > 49 and clickedAt(bump + 33, bump + 49, 3)) or (xSize < 50 and clickedAt(xSize - 13, xSize - 1, 3)) then
						playmode = playmode == 3 and 0 or 3
						drawPlaymode()

					-- Music finished; wait a second or two before responding.
					elseif myEvent[1] == "musicFinished" then
						gapTimer = os.startTimer(2)
						lastPauseState = "maybe"
						marquee = ""

					-- Skip back to start of the song (or to the previous song, if the current song just started).
					elseif pressedKey(keys.a,keys.left) or (xSize > 49 and clickedAt(bump+16,bump+21,0,4) or clickedAt(1,5,1,4)) then
						if note.isPlaying() and note.getSongPositionSeconds() > 3 then
							os.queueEvent("musicSkipTo",0)
							os.queueEvent("musicResume")
						elseif #lastSong > 1 then
							table.remove(lastSong,1)
							startSong(table.remove(lastSong,1))
						end

					-- Toggle pause/resume.
					elseif note.isPlaying() and (pressedKey(keys.p) or (xSize > 49 and clickedAt(bump+22,bump+26,0,4) or clickedAt(5,9,1,4))) then
						if note.isPaused() then os.queueEvent("musicResume") else os.queueEvent("musicPause") end

					-- Tracking bar clicked.
					elseif note.isPlaying() and (myEvent[1] == "mouse_click" or myEvent[1] == "mouse_drag") and myEvent[3] > 1 and myEvent[3] < xSize and myEvent[4] == ySize - 1 then
						os.queueEvent("musicSkipTo",math.floor(note.getSongLength()*(myEvent[3]-1)/(xSize-2)))
					
					-- Song engine just initiated a new track.
					elseif myEvent[1] == "newTrack" then
						marquee = " [Title: "
						if note.getSongName() ~= "" then marquee = marquee..note.getSongName().."]" else marquee = marquee..fs.getName(lastSong[1]).."]" end
						if note.getSongArtist() ~= "" then marquee = marquee.." [Artist: "..note.getSongArtist().."]" end
						if note.getSongAuthor() ~= "" then marquee = marquee.." [NBS Author: "..note.getSongAuthor().."]" end
						marquee = marquee.." [Tempo: "..note.getSongTempo().."]"
						if note.getSongDescription() ~= "" then marquee = marquee.." [Description: "..note.getSongDescription().."]" end
						lastPauseState = "maybe"
					
					-- Drag the marquee.
					elseif myEvent[1] == "mouse_drag" and myEvent[4] == ySize and dragX and marquee then
						marqueePos = (marqueePos - myEvent[3] + dragX)%#marquee
						dragX = myEvent[3]
					
					elseif note.getVolumeLevel() then
						-- Volume down.
						if pressedKey(keys.minus,keys.underscore,keys.numPadSubtract) or clickedAt(9,ySize-2) then
							note.setVolumeLevel(note.getVolumeLevel()-0.05)
							drawVolumeBar()

						-- Volume up.
						elseif pressedKey(keys.plus,keys.equals,keys.numPadAdd) or clickedAt(xSize-8,ySize-2) then
							note.setVolumeLevel(note.getVolumeLevel()+0.05)
							drawVolumeBar()

						-- Volume bar clicked.
						elseif (myEvent[1] == "mouse_click" or myEvent[1] == "mouse_drag") and myEvent[3] > 9 and myEvent[3] < xSize-8 and myEvent[4] == ySize - 2 then
							note.setVolumeLevel((myEvent[3]-10)/(xSize-19))
							drawVolumeBar()
						end
					end
				end
				
				-- Play / pause button.
				if lastPauseState ~= note.isPaused() then
					local ind = (note.isPlaying() and not note.isPaused()) and 3 or 4
					if xSize > 49 then
						local t, tC, bC = buttons[1][1][ind], buttons[1][2][ind], buttons[1][3][ind]
						for i=1,3 do
							term.setCursorPos(bump + 23,i)
							termBlit(t[i], tC[i], bC[i])
						end
					else
						local t, tC, bC = buttons[2][1][ind], buttons[2][2][ind], buttons[2][3][ind]
						for i=1,2 do
							term.setCursorPos(6,i+1)
							termBlit(t[i], tC[i], bC[i])
						end
					end
					lastPauseState = note.isPaused()
				end
				
				-- Update other screen stuff.
				if myEvent[1] ~= "timer" then
					term.setTextColour(term.isColour() and colours.black or colours.white)
					term.setBackgroundColour(term.isColour() and colours.lightGrey or colours.black)
					
					-- Clear old progress bar position.
					if lastProgress then
						term.setCursorPos(lastProgress,ySize-1)
						term.write((lastProgress == 2 or lastProgress == xSize - 1) and "|" or "=")
						lastProgress = nil
					end

					-- Song timers.
					if note.isPlaying() then
						term.setCursorPos(xSize-5,ySize-2)
						
						local mins = tostring(math.min(99,math.floor(note.getSongSeconds()/60)))
						local secs = tostring(math.floor(note.getSongSeconds()%60))
						term.write((#mins > 1 and "" or "0")..mins..":"..(#secs > 1 and "" or "0")..secs)

						term.setCursorPos(2,ySize-2)
						if note.isPaused() and bit.band(curCount,1) == 1 then
							term.write("     ")
						else
							mins = tostring(math.min(99,math.floor(note.getSongPositionSeconds()/60)))
							secs = tostring(math.floor(note.getSongPositionSeconds()%60))
							term.write((#mins > 1 and "" or "0")..mins..":"..(#secs > 1 and "" or "0")..secs)
						end

						-- Progress bar position.
						term.setTextColour(term.isColour() and colours.blue or colours.white)
						term.setBackgroundColour(colours.black)
						lastProgress = 2+math.floor(((xSize-3) * note.getSongPosition() / note.getSongLength()))
						term.setCursorPos(lastProgress,ySize-1)
						term.write(dot)
					else
						term.setCursorPos(2,ySize-2)
						term.write("00:00")
						term.setCursorPos(xSize-5,ySize-2)
						term.write("00:00")
					end

					-- Scrolling marquee.
					if marquee then
						term.setTextColour(term.isColour() and colours.black or colours.white)
						term.setBackgroundColour(term.isColour() and colours.grey or colours.black)
						term.setCursorPos(1,ySize)

						if marquee == "" then
							term.clearLine()
							marquee = nil
						else
							local thisLine = marquee:sub(marqueePos,marqueePos+xSize-1)
							while #thisLine < xSize do thisLine = thisLine..marquee:sub(1,xSize-#thisLine) end
							term.write(thisLine)
						end
					end
					
					-- File list.
					term.setBackgroundColour(colours.black)
					for y = position == lastPosition and (math.floor(ySize / 2)+1) or 4, position == lastPosition and (math.floor(ySize / 2)+1) or (ySize - 3) do
						local thisLine = y + position - math.floor(ySize / 2) - 1

						if displayList[thisLine] then
							local thisString = displayList[thisLine]
							thisString = fs.isDir(shell.resolve(thisString)) and "["..thisString.."]" or thisString:sub(1,#thisString-4)

							if thisLine == position then
								term.setCursorPos(math.floor((xSize - #thisString - 8) / 2)+1, y)
								term.clearLine()
								term.setTextColour(term.isColour() and colours.cyan or blackText)
								term.write(cursor[curCount][1])
								term.setTextColour(term.isColour() and colours.blue or colours.white)
								term.write(thisString)
								term.setTextColour(term.isColour() and colours.cyan or blackText)
								term.write(cursor[curCount][2])
							else
								term.setCursorPos(math.floor((xSize - #thisString) / 2)+1, y)
								term.clearLine()

								if y == 4 or y == ySize - 3 then
									term.setTextColour(blackText)
								elseif y == 5 or y == ySize - 4 then
									term.setTextColour(term.isColour() and colours.grey or blackText)
								elseif y == 6 or y == ySize - 5 then
									term.setTextColour(term.isColour() and colours.lightGrey or colours.white)
								else term.setTextColour(colours.white) end

								term.write(thisString)
							end
						else
							term.setCursorPos(1,y)
							term.clearLine()
						end
					end

					lastPosition = position
				end
			end
		end
	end
	
	local function beBluetoothSpeaker()
		peripheral.find("modem", rednet.open)
		
		local myName = (not os.getComputerLabel()) and ("Speaker"..math.random(10000)) or os.getComputerLabel()
		rednet.host("MoarPNoteSpeaker", myName)
		print("Hosting remote speaker service as \"" .. myName .. "\".")
		
		local haveVolume, ironnote, curPeripheral, nowPlaying, tick = note.getVolumeLevel() ~= nil, {note.getNoteblocks()}, 1, 0
		
		local x, y = term.getCursorPos()
		term.write(#ironnote .. " speaker(s) available.")
		
		while true do
			while #ironnote == 0 do
				os.pullEvent("peripheral")
				ironnote = {peripheral.find("iron_note")}
				for i = 1, #ironnote do ironnote[i] = ironnote[i].playNote end
				term.setCursorPos(1, y)
				term.clearLine()
				term.write(#ironnote .. " speaker(s) available.")
			end
			
			local myEvent = {os.pullEventRaw()}
			
			if myEvent[1] == "rednet_message" and myEvent[4] == "MoarPNoteSpeaker" then
				if type(myEvent[3]) == "table" then
					for _,note in pairs(myEvent[3]) do
						if nowPlaying == MAX_INSTRUMENTS_PER_NOTE_BLOCK * #ironnote then break end
						ironnote[curPeripheral](note.inst, note.pitch, note.volume)
						curPeripheral = (curPeripheral == #ironnote) and 1 or (curPeripheral + 1)
						nowPlaying = nowPlaying + 1
					end
					if not tick then tick = os.startTimer(0.1) end
				elseif type(myEvent[3]) == "number" then
					note.setVolumeLevel(myEvent[3])
				else rednet.send(myEvent[2], note.getVolumeLevel()) end
			elseif myEvent[1] == "peripheral_detach" or myEvent[1] == "peripheral" then
				ironnote = {peripheral.find("iron_note")}
				for i = 1, #ironnote do ironnote[i] = ironnote[i].playNote end
				if curPeripheral > #ironnote then curPeripheral = 1 end
				term.setCursorPos(1, y)
				term.clearLine()
				term.write(#ironnote .. " speaker(s) available.")
			elseif myEvent[1] == "timer" and myEvent[2] == tick then
				nowPlaying = 0
				tick = nil
			elseif myEvent[1] == "terminate" then
				rednet.unhost("MoarPNoteSpeaker", myName)
				print()
				error()
			end
		end
	end
	
	local function listBluetoothSpeakers()
		peripheral.find("modem", rednet.open)
			
		local servers = {rednet.lookup("MoarPNoteSpeaker")}
		
		print("Available Note servers:")
		if #servers == 0 then print("(None)") end
		for i=1,#servers do print(servers[i]) end
		error()
	end
	
	local function pairBluetoothSpeaker(speakerID)
		peripheral.find("modem", rednet.open)
		note.registerRemoteSpeaker(speakerID)
	end
	
	do local args = {...}
	for i=1,#args do if not args[i] then
		break
	elseif args[i]:lower() == "-r" then
		playmode = 1
	elseif args[i]:lower() == "-n" then
		playmode = 2
	elseif args[i]:lower() == "-m" then
		playmode = 3
	elseif fs.isDir(shell.resolve(args[i])) then
		shell.setDir(shell.resolve(args[i]))
	elseif fs.isDir(args[i]) then
		shell.setDir(args[i])
	elseif fs.exists(shell.resolve(args[i])) then
		local filePath = shell.resolve(args[i])
		shell.setDir(fs.getDir(filePath))
		startSong(filePath)
	elseif fs.exists(shell.resolve(args[i]..".nbs")) then
		local filePath = shell.resolve(args[i]..".nbs")
		shell.setDir(fs.getDir(filePath))
		startSong(filePath)
	elseif fs.exists(args[i]) then
		shell.setDir(fs.getDir(args[i]))
		startSong(args[i])
	elseif fs.exists(args[i]..".nbs") then
		shell.setDir(fs.getDir(args[i]))
		startSong(args[i]..".nbs")
	elseif args[i]:lower() == "-server" then
		beBluetoothSpeaker()
	elseif args[i]:lower() == "-list" then
		listBluetoothSpeakers()
	elseif args[i]:lower() == "-remote" then
		pairBluetoothSpeaker(table.remove(args, i + 1))
	end end end
	
	if playmode > 1 then os.queueEvent("musicFinished") end
	
	enforceScreenSize()
	return parallel.waitForAny(note.songEngine, noteMenu)
end