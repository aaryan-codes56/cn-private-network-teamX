#!/bin/bash
# Flush the macOS client DNS cache (Extension B: "flush and observe the immediate change")
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "$(date +%H:%M:%S)  macOS DNS cache flushed"
