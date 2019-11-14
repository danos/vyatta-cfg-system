#!/bin/bash
sh -c \
    "/usr/bin/setterm -blank 0 -powersave off -powerdown 0 </dev/console >/dev/console 2>&1"
