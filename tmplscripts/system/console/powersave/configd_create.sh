#!/bin/bash
sh -c \
    "/usr/bin/setterm -blank 15 -powersave powerdown -powerdown 60 </dev/console >/dev/console 2>&1"
