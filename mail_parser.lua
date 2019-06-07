-- Imports and dependencies (speed-up the symbols look-up by copying them into a small local namespace that is searched before the huge global namespace)
local mime = require('mime') -- from luasocket, see http://w3.impa.br/~diego/software/luasocket/mime.html
local convert_charsets = require('convert_charsets') -- from convert-charsets, see https://gitlab.com/rychly/convert-charsets
local lower, find, sub, gsub = string.lower, string.find, string.sub, string.gsub
local stdin, stdout, stderr, open, close, read, write = io.stdin, io.stdout, io.stderr, io.open, io.close, io.read, io.write

-- Module declaration
local _M = {}

-- PRIVATE FUNCTIONS

local IteratorStack = {}
IteratorStack.__index = IteratorStack

function IteratorStack:create(iterator)
	local new = {}
	setmetatable(new, self)
	new.iterator = iterator
	new.stack = {}
	new.active = true
	new.counter = 0
	return new
end

function IteratorStack:next()
	if self.active then
		local value = table.remove(self.stack) or self.iterator()
		if value then
			self.counter = self.counter + 1
		end
		return (value:sub(-1) == '\x0D') and value:sub(1, -2) or value
	else
		return nil
	end
end

function IteratorStack:values()
	return function () return self:next() end
end

function IteratorStack:insert(value)
	table.insert(self.stack, value)
	self.counter = self.counter - 1
end

function IteratorStack:close()
	self.active = false
end

local function print_table(table_to_print, prefix)
	for key, value in pairs(table_to_print) do
		if type(value) ~= 'table' then
			print(prefix .. key, value)
		else
			print_table(value, prefix .. key .. ".")
		end
	end
end

local function export_parsed(parsed, directory)
	local lfs = require('lfs')
	lfs.mkdir(directory)
	-- data body
	if parsed['body-name'] then
		local file_out = assert(open(directory .. "/" .. parsed['body-name'], "wb"))
		file_out:write(parsed['body'])
		file_out:close()
		parsed['body'] = nil
	-- text body
	elseif parsed['body-type'] then
		local file_out = assert(open(directory .. "/" .. parsed['body-type']:gsub("/", "."), "w"))
		file_out:write(parsed['body'])
		file_out:close()
		parsed['body'] = nil
	-- parts
	elseif parsed['parts'] then
		for i, part in pairs(parsed['parts']) do
			export_parsed(part, directory .. "/part_" .. i)
		end
		parsed['parts'] = nil
	end
	-- headers
	local file_out = assert(open(directory .. "/headers.txt", "w"))
	for key, value in pairs(parsed) do
		file_out:write(key .. "\t" .. value .. "\n")
	end
	file_out:close()
end

-- PUBLIC FUNCTIONS

function _M.from_charset_to_utf8(charset, text)
	-- TODO: move `gsub("-", "_"):upper()` into convert_charsets.normalize_charset_name
	local to_utf8_mapping_table = convert_charsets.get_mapping_table_to_utf8(convert_charsets.normalize_charset_name(charset:gsub("-", "_"):upper()))
	return convert_charsets.to_utf8(text, to_utf8_mapping_table)
end

function _M.quotation_decode(charset, quotation_type, data)
	local decoded_data = (quotation_type == 'B' and mime.unb64(data)) or (quotation_type == 'Q' and mime.unqp(data)) or data
	return _M.from_charset_to_utf8(charset, decoded_data)
end

function _M.unquote(quoted_string)
	return quoted_string:gsub('=%?([^?]+)%?(.)%?([^?]+)%?=', _M.quotation_decode)
end

function _M.parse_content_type(content_type)
	-- missing the content type
	if not content_type then
		return nil, nil, nil
	end
	-- text/* in a charset
	local _, _, text_type, charset = content_type:find('^text/([^;]+);%s*charset="?([^"]+)"?$')
	if text_type then
		return 'text', text_type, charset
	end
	local _, _, text_type = content_type:find('^text/([^;]+)$')
	if text_type then
		return 'text', text_type, nil
	end
	-- multipart/* with a boundary
	local _, _, multipart, boundary = content_type:find('^multipart/([^;]+);%s*boundary="?([^"]+)"?$')
	if multipart then
		return 'multipart', multipart, boundary
	end
	-- other data with a name
	local _, _, major_type, minor_type, name = content_type:find('^([^/]+)/([^;]+);.*name="?([^";]+)"?.-$')
	if major_type then
		return 'data', major_type .. '/' .. minor_type, name
	end
	local _, _, major_type, minor_type = content_type:find('^([^/]+)/([^;]+);?.-$')
	if major_type then
		return 'data', major_type .. '/' .. minor_type, nil
	end
	-- unknown (however, everything should be processed as the cases above)
	return nil, nil, nil
end

function _M.extract_headers(lines, boundary)
	local headers = {}
	local last_header = nil
	for line in lines:values() do
		-- exit on an empty line (the next line is the beginning of a body) or on a boundary (the boundary line needs to be processed so do not skip it)
		if (line == "") then
			break
		end
		if boundary and ((line == '--' .. boundary) or (line == '--' .. boundary .. '--')) then
			lines:insert(line)
			break
		end
		-- parse a new header
		local _, _, header, value = line:find("^([^:%s]+):%s*(.*)$")
		-- parse a continuos header
		local try_continuous = not header
		if try_continuous then
			header = last_header
			_, _, value = line:find("^%s+(.*)$")
		end
		-- process a continuos or new header
		if value then
			header = header:lower()
			value = _M.unquote(value)
			headers[header] = headers[header] and (headers[header] .. (try_continuous and "" or "\n") .. value) or value
			last_header = header
		end
	end
	return headers
end

function _M.extract_body(lines, boundary, encoding)
	local body = ""
	for line in lines:values() do
		-- exit on a boundary (the boundary line needs to be processed so do not skip it)
		if boundary and ((line == '--' .. boundary) or (line == '--' .. boundary .. '--')) then
			lines:insert(line)
			break
		end
		-- process a continuos or new line
		if (encoding == 'quoted-printable') then
			-- mime.unqp do no know how to decode and empty string, so it returns null
			body = body .. ((line:sub(-1) == "=")
				-- if it is continuous then add without the suffix and \n
				and (mime.unqp(line:sub(1, -2)) or "")
				-- if it is non-continuous then add with \n
				or ((mime.unqp(line) or "") .. "\n"))
		elseif (encoding == 'base64') then
			-- base64 can be decoded by individual lines
			body = body .. mime.unb64(line)
		else
			body = body .. line .. "\n"
		end
	end
	return body
end

function _M.parse_parts(lines, boundary, first_content_type, number_of_lines)
	local parts = {}
	for line in lines:values() do
		-- start processing of a part on a boundary entry tag
		if (line == '--' .. boundary) then
			local parsed = _M.parse(lines, boundary, first_content_type, number_of_lines)
			table.insert(parts, parsed)
		-- exit on a boundary exit tag (the boundary line can be consumed here, it wont be needed anymore)
		elseif (line == '--' .. boundary .. '--') then
			break
		end
	end
	return parts
end

function _M.parse(lines, boundary, first_content_type, number_of_lines)
	-- get headers
	local content = _M.extract_headers(lines, boundary)
	-- check the content type
	local detected_type, description, specification = _M.parse_content_type(content["content-type"])
	-- parts in the case of a multipart content (the specification is a boundary)
	if (detected_type == 'multipart') then
		content['parts'] = _M.parse_parts(lines, specification, first_content_type, number_of_lines)
	-- text body in a charset in the case of a text content (the specification is the charset)
	elseif (detected_type == 'text') then
		content['body'] = _M.extract_body(lines, boundary, content["content-transfer-encoding"])
		content['body-type'] = 'text/' .. description
		-- convert from the charset
		if specification then
			content['body'] = _M.from_charset_to_utf8(specification, content['body'])
			content['body-original-charset'] = specification
		end
	-- data body with a name (the specification is the name)
	elseif (detected_type == 'data') then
		content['body'] = _M.extract_body(lines, boundary, content["content-transfer-encoding"])
		content['body-type'] = description
		content['body-name'] = specification
	end
	-- looking only for the first occurence with the matching content type or reading only a limited number of lines
	if (first_content_type and content['body-type'] and content['body-type']:find("^" .. first_content_type .. "$"))
	or (number_of_lines and (lines.counter >= number_of_lines)) then
			lines:close()
	end
	return content
end

-- main method for CLI
function _M.main(arg)
	if (#arg == 0 or arg[#arg] == "--help") then
		stderr:write("Usage: " .. arg[0] .. " <mail-message-file> <output-directory> [first-content-type] [number-of-input-lines]\n")
		stderr:write("Parse a give mail message file and extracts its content into a given output directory.\n")
		stderr:write("Optionally, the parsing and the extraction can stop after:\n")
		stderr:write("* the first (full pattern-matching) occurence of a given MIME content type (i.e., it can be a lua RE pattern without '^' and '$' that are implicit),\n")
		stderr:write("* the reading a given number of input lines (the processing of a content starting on a line before the given number will be finished).\n")
		return 1
	end
	-- process args
	local opt_input, out_directory, first_content_type, number_of_lines = arg[1], arg[2], arg[3], tonumber(arg[4])
	-- read and parse file
	local file_in = (opt_input == "-") and stdin or assert(open(opt_input, "r"))
	local linesIteratorStack = IteratorStack:create(file_in:lines())
	local parsed = _M.parse(linesIteratorStack, nil, first_content_type, number_of_lines)
	file_in:close()
	-- print/export parsed
	export_parsed(parsed, out_directory)
	--print_table(parsed, "")
	stderr:write("Done! Processed " .. linesIteratorStack.counter .. " lines of the input file.")
	return 0
end

return _M
