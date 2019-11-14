#!/bin/bash
zones=( $(find /usr/share/zoneinfo/posix -type f -follow | sed -e 's:/usr/share/zoneinfo/posix/::') )
new_zone=$(basename $CONFIGD_PATH)
new_zone=${new_zone/\%2B/+}
new_zone=${new_zone/\%2F//}
for zone in ${zones[@]}; do
    if [[ $new_zone == $zone ]]; then
        exit 0
    fi
done

echo "ERROR: $new_zone is not a valid time-zone"
exit 1
