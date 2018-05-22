# SMS Bot for slack

This is a simple lua script intended to work on openwrt based routers with luci on uhttpd.
With proper slack configuration this will react to slash commands and use gnokii to send SMS
This script will also log everything with logger via nixio module

## Requirements

 - gnokii (For SMS sending obvious)
 - luci (For the whole api)
 - luasec (Make HTTPS requests)
 - uhttpd-mod-lua (For inline uhttpd lua execution)

## Config

**config.lua** holds data for slack bot verification token, and oauth token for talking with slack API

## Slack permissions needed

 - channels:read
 - im:read
 - users:read

## Limitations due to lua understanding

While deploying make sure that **line 5** on both **index.lua** and **send.lua** contain proper file path location for config require *example: /usr/local/sms/config.lua* would look like `local config = require "usr.local.sms.config"`

Also another path is under **index.lua** line **127** which donates call to send.lua file

These will probably be streamlined some day

## Warning

Please, please check your uhttpd settings before putting this live, incorrect cgi script could end with directory listing and option to download config.lua witch will expose your slack tokens.
