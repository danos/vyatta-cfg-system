#!/bin/bash
find /usr/share/zoneinfo/posix -type f -follow | sed -e 's:/usr/share/zoneinfo/posix/::'
