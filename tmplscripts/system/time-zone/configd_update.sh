#!/opt/vyatta/bin/cliexec
LTF="/usr/share/zoneinfo"
case "$VAR(@)" in
    [Ll][Oo][Ss]*) LTF="$LTF/US/Pacific" ;;
    [Dd][Ee][Nn]*) LTF="$LTF/US/Mountain" ;;
    [Hh][Oo][Nn][Oo]*) LTF="$LTF/US/Hawaii" ;;
    [Nn][Ee][Ww]*) LTF="$LTF/US/Eastern" ;;
    [Cc][Hh][Ii][Cc]*) LTF="$LTF/US/Central" ;;
    [Aa][Nn][Cc]*) LTF="$LTF/US/Alaska" ;;
    [Pp][Hh][Oo]*) LTF="$LTF/US/Arizona" ;;
    GMT*) LTF="$LTF/Etc/$VAR(@)" ;;
    *) LTF="$LTF/$VAR(@)" ;;
esac
if [ -f "$LTF" ]; then
    ln -fs $LTF /etc/localtime
else
    echo "Invalid timezone"
    exit 1
fi
