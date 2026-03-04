#!/bin/bash

set -eu

local dev='@Dev'
local ip='@Ip'
local gw='@Gw'
local dns='@Dns'

ip link set $dev up
ip addr add $ip dev $dev
ip route add default via $gw dev $dev
resolvectl dns $dev $dns
