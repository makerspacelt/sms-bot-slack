require "luci.http"
require "luci.ltn12"
require "nixio"

local config = require "root.sms.config"

function handle_request(env)
	nixio.openlog("sms-sender-request")

	local renv = {
		CONTENT_LENGTH  = env.CONTENT_LENGTH,
		CONTENT_TYPE    = env.CONTENT_TYPE,
		REQUEST_METHOD  = env.REQUEST_METHOD,
		REQUEST_URI     = env.REQUEST_URI,
		PATH_INFO       = env.PATH_INFO,
		SCRIPT_NAME     = env.SCRIPT_NAME:gsub("/+$", ""),
		SCRIPT_FILENAME = env.SCRIPT_NAME,
		SERVER_PROTOCOL = env.SERVER_PROTOCOL,
		QUERY_STRING    = env.QUERY_STRING
	}

	local k, v
	for k, v in pairs(env.headers) do
		k = k:upper():gsub("%-", "_")
		renv["HTTP_" .. k] = v
	end

	local len = tonumber(env.CONTENT_LENGTH) or 0
	local function recv()
		if len > 0 then
			local rlen, rbuf = uhttpd.recv(4096)
			if rlen >= 0 then
				len = len - rlen
				return rbuf
			end
		end

		return nil
	end

	local send = uhttpd.send
	local req = luci.http.Request(
		renv, recv, luci.ltn12.sink.file(io.stderr)
	)

	local co = coroutine.create(httpdispatch)
	local headerCache = { }
	local active = true

	nixio.syslog("info", "Request received. Parsing...")
	while coroutine.status(co) ~= "dead" do
		local res, id, data1, data2 = coroutine.resume(co, req)

		if not res then
			send("Status: 500 Internal Server Error\r\n")
			send("Content-Type: text/plain\r\n\r\n")
			send(tostring(id))
			break
		end

		if active then
			if id == 1 then
				send("Status: ")
				send(tostring(data1))
				send(" ")
				send(tostring(data2))
				send("\r\n")
			elseif id == 2 then
				headerCache[data1] = data2
			elseif id == 3 then
				for k, v in pairs(headerCache) do
					send(tostring(k))
					send(": ")
					send(tostring(v))
					send("\r\n")
				end
				send("\r\n")
			elseif id == 4 then
				send(tostring(data1 or ""))
			elseif id == 5 then
				active = false
			end
		end
	end

	nixio.closelog()
end


function httpdispatch(request, prefix)
	local http = require "luci.http"

	http.context.request = request

	local token = http.formvalue("token")
	if not token or token ~= config.slack.verification then
		nixio.syslog("err", "Reqeust doesn't look like slack, aborting...")

		http.status(500, "Internal Server Error")
        http.prepare_content("text/plain")
        http.write(message)
        http.close()

        return
	end

	http.status(200, "OK")
	http.prepare_content("text/plain")

	local callback = http.formvalue("response_url")
	local testData = http.formvalue("text");
	local channel  = http.formvalue("channel_id")

	if not testData or testData == '' then
		http.write("ERROR: usage @user text")
		http.close()
		return
	end

	local user, name, text = string.match(http.formvalue("text"), "\<@(.+)|(.+)\> (.+)$")
	if (not user or not text or not name) then
		http.write("ERROR: usage @user text")
		http.close()
		return
	end

	io.popen('/usr/bin/lua /root/sms/send.lua "' .. user .. '" "' .. text .. '" "' .. callback .. '" "' .. channel .. '"')

	http.write("Roger! Sending sms to " .. name .. "\n\r")
	http.close()
end

