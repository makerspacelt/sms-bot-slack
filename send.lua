require "luci.sys"
require "luci.jsonc"
require "nixio"

local config = require "root.sms.config"
local sclient = require("ssl.https")

nixio.openlog("sms-sender")
nixio.syslog("info", "Child ready")

local callerId = arg[1]
local userId = arg[2]
local text = arg[3]
local callback = arg[4]
local channelId = arg[5]

local channelText = ""
local footerText = " - Makerspace.lt @ slack"
local bodyText = " wants to talk with you"

nixio.syslog("info", "callerId: " .. callerId)
nixio.syslog("info", "toUserId: " .. userId)
nixio.syslog("info", "callback: " .. callback)
nixio.syslog("info", "channelId: " .. channelId)

function exit()
	nixio.closelog()
	os.exit()
end

function sendSms(phone, text)
	-- return luci.sys.call("echo -n '" .. text .. "' | gnokii --sendsms " .. phone)
	return luci.sys.call("/root/sms/send.sh '" .. phone ..  "' '" .. text .."'")
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
	
	nixio.syslog("info", "User " .. user  .. " requested from slack, status: " .. code) 
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

	nixio.syslog("info", "Channel " .. channel  .. " requested from slack, status: " .. code)

	if code == 200 and type(response_body) == "table" then
		return luci.jsonc.parse(table.concat(response_body))
	else
		return nil
	end
end

local callerObj = getUser(callerId)
local userObj = getUser(userId)
local channelObj = getChannel(channelId)

if not callerObj.ok then
	nixio.syslog("err", "Invalid caller object")
	respond(callback, "ERROR!: Who are you?")
	exit()
end
nixio.syslog("info", "Caller: " .. callerObj.user.profile.display_name_normalized)

if not userObj.ok or userObj.user.profile.phone == nil or userObj.user.profile.phone == '' then
	nixio.syslog("err", "Invalid user/no number trying to inform user")
	respond(callback, "ERROR!: User has no phone/invalid user")
	exit()
end
nixio.syslog("info", "User: " .. userObj.user.profile.display_name_normalized)

if channelObj.ok then
	if channelObj.channel.is_im then
		channelText = " in private!"
	else
		channelText = " in #" .. channelObj.channel.name_normalized
	end	
end

text = "@" .. callerObj.user.profile.display_name_normalized .. bodyText .. channelText .. footerText
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

