-- Imports and dependencies (speed-up the symbols look-up by copying them into a small local namespace that is searched before the huge global namespace)
local mime = require('mime') -- from luasocket, see http://w3.impa.br/~diego/software/luasocket/mime.html
local convert_charsets = require('convert_charsets') -- from convert-charsets, see https://gitlab.com/rychly/convert-charsets
local lower, find, sub, gsub = string.lower, string.find, string.sub, string.gsub
local stdin, stdout, stderr, open, close, read, write = io.stdin, io.stdout, io.stderr, io.open, io.close, io.read, io.write

-- Module declaration
local mail_parser = {} -- Public namespace

-- PUBLIC FUNCTIONS

function mail_parser.from_charset_to_utf8(charset, text)
	-- TODO: move `gsub("-", "_"):upper()` into convert_charsets.normalize_charset_name
	local to_utf8_mapping_table = convert_charsets.get_mapping_table_to_utf8(convert_charsets.normalize_charset_name(charset:gsub("-", "_"):upper()))
	return convert_charsets.to_utf8(text, to_utf8_mapping_table)
end

function mail_parser.quotation_decode(charset, quotation_type, data)
	local decoded_data = (quotation_type == 'B' and mime.unb64(data)) or (quotation_type == 'Q' and mime.unqp(data)) or data
	return mail_parser.from_charset_to_utf8(charset, decoded_data)
end

function mail_parser.unquote(quoted_string)
	return quoted_string:gsub('=%?([^?]+)%?(.)%?([^?]+)%?=', mail_parser.quotation_decode)
end

function mail_parser.extract_headers(lines, start_line_number, boundary)
	local headers, end_line_number = {}, #lines + 1
	local last_header = nil
	for i = start_line_number or 1, #lines do
		local line = lines[i]
		-- exit on an empty line (the next line is the beginning of a body) or on a boundary (the boundary line needs to be processed so do not skip it)
		if (line == "") then
			end_line_number = i + 1
			break
		end
		if boundary and ((line == '--' .. boundary) or (line == '--' .. boundary .. '--')) then
			end_line_number = i
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
			value = mail_parser.unquote(value)
			headers[header] = headers[header] and (headers[header] .. (try_continuous and "" or "\n") .. value) or value
			last_header = header
		end
	end
	return headers, end_line_number
end

function mail_parser.extract_body(lines, start_line_number, boundary, encoding)
	local body, end_line_number = "", #lines + 1
	for i = start_line_number or 1, #lines do
		local line = lines[i]
		-- exit on a boundary
		if boundary and ((line == '--' .. boundary) or (line == '--' .. boundary .. '--')) then
			end_line_number = i
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
	return body, end_line_number
end

function mail_parser.parse_content_type(content_type)
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

function mail_parser.parse_parts(lines, start_line_number, boundary)
	local parts, end_line_number = {}, #lines + 1
	local i = start_line_number or 1
	while (i <= #lines) do
		-- start processing of a part on a boundary entry tag
		if (lines[i] == '--' .. boundary) then
			local parsed, sub_end_line_number = mail_parser.parse(lines, i + 1, boundary)
			table.insert(parts, parsed)
			i = sub_end_line_number
		-- exit on a boundary exit tag
		elseif (lines[i] == '--' .. boundary .. '--') then
			end_line_number = i
			break
		else
			i = i + 1
		end
	end
	return parts, end_line_number
end

function mail_parser.parse(lines, start_line_number, boundary)
	local content, end_line_number
	-- get headers
	content, end_line_number = mail_parser.extract_headers(lines, start_line_number, boundary)
	-- check the content type
	local detected_type, description, specification = mail_parser.parse_content_type(content["content-type"])
	-- parts in the case of a multipart content (the specification is a boundary)
	if (detected_type == 'multipart') then
		content['parts'], end_line_number = mail_parser.parse_parts(lines, end_line_number, specification)
	-- text body in a charset in the case of a text content (the specification is the charset)
	elseif (detected_type == 'text') then
		content['body'], end_line_number = mail_parser.extract_body(lines, end_line_number, boundary, content["content-transfer-encoding"])
		content['body-type'] = 'text/' .. description
		-- convert from the charset
		if specification then
			content['body'] = mail_parser.from_charset_to_utf8(specification, content['body'])
			content['body-original-charset'] = specification
		end
	-- data body with a name (the specification is the name)
	elseif (detected_type == 'data') then
		content['body'], end_line_number = mail_parser.extract_body(lines, end_line_number, boundary, content["content-transfer-encoding"])
		content['body-type'] = description
		content['body-name'] = specification
	end
	return content, end_line_number
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

-- main method for CLI
function mail_parser.main(arg)
	if (#arg == 0 or arg[#arg] == "--help") then
		stderr:write("Usage: " .. arg[0] .. " <mail-message-file> <output-directory>\n")
		stderr:write("Parse a give mail message file and extracts its content into a given output directory.\n")
		return 1
	end
	local opt_input, out_directory = arg[1], arg[2]
	-- read file
	local file_in, lines = (opt_input == "-") and stdin or assert(open(opt_input, "r")), {}
	for line in file_in:lines() do
		table.insert(lines, (line:sub(-1) == '\x0D') and line:sub(1, -2) or line)
	end
	file_in:close()
	-- process file
	local parsed, count = mail_parser.parse(lines, nil, nil)
	export_parsed(parsed, out_directory)
	--print_table(parsed, "")
	return 0
end

return mail_parser
