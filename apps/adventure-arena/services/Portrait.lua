local Portrait = {}

local PREFIX = "apps/adventure-arena/zilscript/"
local MAX_BYTES = 1024 * 1024
local MAX_DIMENSION = 2048
local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Books can choose a picture by ID, but cannot ask the reader to open
-- arbitrary files. A catalog may share an asset folder between editions.
function Portrait.reference(root, slug)
	if type(root) ~= "string" or not root:match("^books/[a-z0-9]+[a-z0-9-]*/[a-z0-9]+[a-z0-9-]*$") then return nil end
	if type(slug) ~= "string" or #slug > 64 or not slug:match("^[a-z0-9][a-z0-9-]*$") then return nil end
	return PREFIX .. root .. "/portraits/" .. slug .. ".png"
end

local function localRead(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local bytes = file:read(MAX_BYTES + 1)
	file:close()
	return bytes
end

local function png(bytes)
	if type(bytes) ~= "string" or #bytes < 45 or #bytes > MAX_BYTES
		or bytes:sub(1, 16) ~= PNG_SIGNATURE .. "\0\0\0\13IHDR"
		or bytes:sub(-12) ~= "\0\0\0\0IEND\174\66\96\130" then
		return false
	end
	local width, height = string.unpack(">I4I4", bytes, 17)
	if width == 0 or width > MAX_DIMENSION or height == 0 or height > MAX_DIMENSION then return false end
	-- Check the chunk boundaries before deferring actual decoding to the printer.
	local offset, imageData = 34, false
	while offset + 11 <= #bytes do
		local length, kind = string.unpack(">I4c4", bytes, offset)
		local nextOffset = offset + 12 + length
		if nextOffset > #bytes + 1 then return false end
		if kind == "IEND" then return imageData and nextOffset == #bytes + 1 end
		if kind == "IDAT" and length > 0 then imageData = true end
		offset = nextOffset
	end
	return false
end

local function base64(bytes)
	local result = {}
	for pos = 1, #bytes, 3 do
		local a, b, c = bytes:byte(pos, pos + 2)
		local triple = (a << 16) | ((b or 0) << 8) | (c or 0)
		local i, j, k, l = (triple >> 18) + 1, ((triple >> 12) & 63) + 1,
			((triple >> 6) & 63) + 1, (triple & 63) + 1
		table.insert(result, ALPHABET:sub(i, i) .. ALPHABET:sub(j, j)
			.. (b and ALPHABET:sub(k, k) or "=") .. (c and ALPHABET:sub(l, l) or "="))
	end
	return table.concat(result)
end

function Portrait.dataURI(path, readFile)
	if type(path) ~= "string" or path:sub(1, #PREFIX) ~= PREFIX then return nil end
	local root, slug = path:sub(#PREFIX + 1):match("^(.*)/portraits/(.*)%.png$")
	if not root or Portrait.reference(root, slug) ~= path then return nil end
	local ok, bytes = pcall(readFile or localRead, path)
	if not ok or not png(bytes) then return nil end
	return "data:image/png;base64," .. base64(bytes)
end

return Portrait
