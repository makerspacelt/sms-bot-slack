require "luci.sys"
require "luci.jsonc"
require "nixio"

local config = require "root.sms.config"
local sclient = require("ssl.https")


nixio.openlog("sms-sender")

nixio.syslog("info", "Child ready")
local userId = arg[1]
local text = arg[2]
local callback = arg[3]
local channelId = arg[4]

nixio.syslog("info", "userId: " .. userId)
nixio.syslog("info", "text: " .. text)
nixio.syslog("info", "callback: " .. callback)

function exit()
	nixio.closelog()
	os.exit()
end

function sendSms(phone, text)
	return luci.sys.call("echo -n '" .. text .. "' | gnokii --sendsms " .. phone)
end

function respond(url, msg)
	local request_body = luci.jsonc.stringify({text = msg})
	nixio.syslog("info", "Responding with body: " .. request_body)

	local res, code = sclient.request{
		url = url,
		method = "POST",
		headers = {
						["Content-Type"] = "application/json";
						["Content-Length"] = #request_body;
				},
		source = ltn12.source.string(request_body),
	}

	nixio.syslog("info", "Response sent - Code: " .. tostring(code) .. " Res: " .. tostring(res))
end

function getUser(user)
	local response_body = {}
		local request_body = "user=" .. user

		local res, code, response_headers = sclient.request{
				url = "https://slack.com/api/users.info",
				method = "POST",
				headers = {
						["Content-Type"] = "application/x-www-form-urlencoded";
						["Content-Length"] = #request_body;
						["Authorization"] = "Bearer " .. config.slack.oauth;
				},
				source = ltn12.source.string(request_body),
				sink = ltn12.sink.table(response_body),
		}

		nixio.syslog("info", "User requested from slack")

	if code == 200 and type(response_body) == "table" then
		return luci.jsonc.parse(table.concat(response_body))
	else
		return nil
	end
end

function getChannel(channel)
	local response_body = {}
		local request_body = "channel=" .. channel

		local res, code, response_headers = sclient.request{
				url = "https://slack.com/api/conversations.info",
				method = "POST",
				headers = {
						["Content-Type"] = "application/x-www-form-urlencoded";
						["Content-Length"] = #request_body;
						["Authorization"] = "Bearer " .. config.slack.oauth;
				},
				source = ltn12.source.string(request_body),
				sink = ltn12.sink.table(response_body),
		}

		nixio.syslog("info", "Channel info requested from slack")

	if code == 200 and type(response_body) == "table" then
		return luci.jsonc.parse(table.concat(response_body))
	else
		return nil
	end
end

nixio.syslog("info", "Retrieving user info")
local userObj = getUser(userId)
local channelObj = getChannel(channelId)

if not userObj.ok or userObj.user.profile.phone == nil or userObj.user.profile.phone == '' then
	nixio.syslog("error", "Invalid user/no number trying to inform user")
	respond(callback, "ERROR!: User has no phone/invalid user")
	exit()
end

if channelObj.ok and channelObj.channel.name and channelObj.channel.name ~= '' then
	text = text .. " #" .. channelObj.channel.name
end

nixio.syslog("info", "Sending sms to: " .. tostring(userObj.user.profile.phone) .. " text: " .. text)
local status = sendSms(userObj.user.profile.phone, text)

if status ~= 0 then
	nixio.syslog("err", "SMS sendig failed informing user...")
	respond(callback, "ERROR: Someone didn't pay for phone, sms sending failed (" .. tostring(status) .. ")")
else
	nixio.syslog("info", "SMS sendig success informing user...")
	respond(callback, "SMS delivered")
end

exit()

