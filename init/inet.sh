#!/bin/bash

set -eu

dev='@Dev'
ip='@Ip'
gw='@Gw'
dns='@Dns'

ip link set $dev up
ip addr add $ip dev $dev
ip route add default via $gw dev $dev
resolvectl dns $dev $dns
