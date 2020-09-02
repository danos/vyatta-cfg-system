#!/bin/bash
new_zone=$(basename $CONFIGD_PATH)
new_zone=${new_zone//\%2B/+}
new_zone=${new_zone//\%2F//}
if [ -f /usr/share/zoneinfo/posix/$new_zone ]; then
    exit 0
fi

echo "ERROR: $new_zone is not a valid time-zone"
exit 1
