-- Imports and dependencies (speed-up the symbols look-up by copying them into a small local namespace that is searched before the huge global namespace)
local mime = require('mime') -- from luasocket, see http://w3.impa.br/~diego/software/luasocket/mime.html
local convert_charsets = require('convert_charsets') -- from convert-charsets, see https://gitlab.com/rychly/convert-charsets
local gsub = string.gsub
local stderr = io.stderr

-- Module declaration
local mail_parser = {} -- Public namespace

-- PUBLIC FUNCTIONS

function mail_parser.quotation_decode(charset, quotation_type, data)
	local to_utf8_mapping_table = convert_charsets.get_mapping_table_to_utf8(convert_charsets.normalize_charset_name(charset))
	local decoded_data = (quotation_type == 'B' and mime.unb64(data)) or (quotation_type == 'Q' and mime.unqp(data)) or data
	return convert_charsets.to_utf8(decoded_data, to_utf8_mapping_table)
end

function mail_parser.unquote(quoted_string)
	return quoted_string:gsub('=%?([^?]+)%?(.)%?([^?]+)%?=', mail_parser.quotation_decode)
end

function mail_parser.extract_headers(lines, start_line_number, boundary)
	local headers, end_line_number = {}, nil
	local last_header = nil
	for i = start_line_number or 1, #lines do
		local line = lines[i]
		-- exit on an empty line (the next line is the beginning of a body) or on a boundary
		if (line == "") then
			end_line_number = i + 1
			break
		elseif boundary and line:find(boundary, 1, true) then
			end_line_number = i
			break
		end
		-- process a continuos or new header
		local _, _, header, value = line:find("^()%s+(.*)$") or line:find("^([^:]+): *(.*)$")
		header = (header ~= "") and header or last_header
		if header then
			header = header:lower()
			value = mail_parser.unquote(value)
			headers[header] = headers[header] and (headers[header] .. "\n" .. value) or value
			last_header = header
		end
	end
	return headers, end_line_number
end

-- TODO: extract_body, parse_part, parse

-- main method for CLI
function mail_parser.main(arg)
	if (#arg == 0 or arg[#arg] == "--help") then
		stderr:write("Usage: " .. arg[0] .. " TBA\n")
		stderr:write("TBA.\n")
		return 1
	end
	return 0
end

return mail_parser
