#!/bin/bash
if [ "$COMMIT_ACTION" == "SET" -o "$COMMIT_ACTION" == "DELETE" ]; then
    service rsyslog restart
fi
