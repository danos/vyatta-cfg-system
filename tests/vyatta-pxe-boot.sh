#!/bin/bash
# unit test for pxe boot env

bogus_input=/tmp/.input
BOOTFILE=/tmp/.config.boot
source "$(pwd)/../scripts/vyatta-pxe-boot"

_create_bogus_input () {

    echo "$1" > $bogus_input
}

_create_config () {

    cat > $BOOTFILE <<EOF
interfaces {
    dataplane dp0s4 {
        address 192.168.3.12/29
        description test
    }
} 
EOF
}

function testGettingBootInterface() {

    #We expect a null return if there is no BOOTIF 
    PXE_BOOT_MAC=$(_get_boot_mac /proc/cmdline)
    assertEquals '' "$PXE_BOOT_MAC"

    #We expect a proper 48-bit mac address
    _create_bogus_input "FOO BAR BOOTIF=00:11:22:33:44:55 LOREM IPSUM"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "00:11:22:33:44:55" "$PXE_BOOT_MAC"

    #Too long, expect null
    _create_bogus_input "FOO BAR BOOTIF=00:11:22:33:44:55:66:77 LOREM IPSUM"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "" "$PXE_BOOT_MAC"

    #Too short, expect null
    _create_bogus_input "FOO BAR BOOTIF=00:11:22:33 LOREM IPSUM"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "" "$PXE_BOOT_MAC"

    #What if there is two BOOTIF, we pick the last one
     _create_bogus_input "FOO BAR BOOTIF=00:11:22:33:44:55 Isengard BOOTIF=00:11:22:33:44:66 LOREM IPSUM"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "00:11:22:33:44:66" "$PXE_BOOT_MAC"
 
    #What if there is two BOOTIF, we pick the last one, but the last one is malformed?
    #We're out of luck, bc the sed command picks the last mac. We expect null
     _create_bogus_input "FOO BAR BOOTIF=00:11:22:33:44:55 Isengard BOOTIF=00:11:22:66 LOREM IPSUM"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "" "$PXE_BOOT_MAC"

    #
    _create_bogus_input "console=tty0 console=ttyS0 boot=live nopersistent nonetworking noeject fetch=http://192.168.248.1/2015-03-05/livecd-dataplane_2015-03-05-0315-da98de2_amd64.iso initrd=2015-03-05/initrd.img BOOT_IMAGE=2015-03-05/vmlinuz BOOTIF=01-52-54-00-b2-e7-c8"
    PXE_BOOT_MAC=$(_get_boot_mac $bogus_input)
    assertEquals "52:54:00:b2:e7:c8" "$PXE_BOOT_MAC"
}

function testWritingConfig () {
 
    _create_config
    
    #interface not configured, expecting dp0s1 to be added
    cp /tmp/.config.boot /tmp/.config.boot.bak
    _write_to_config dp0s1 $BOOTFILE
    echo "Added Interface to config:"
    diff /tmp/.config.boot.bak /tmp/.config.boot
    assertFalse 'Expected output differs.' $?

    #interface already configured, expecting no change
    cp /tmp/.config.boot /tmp/.config.boot.bak
    _write_to_config dp0s4 $BOOTFILE
    diff /tmp/.config.boot.bak /tmp/.config.boot
    assertTrue 'Expected output differs.' $?
}

# load functions and run shUnit2
[ -n "${ZSH_VERSION:-}" ] && SHUNIT_PARENT=$0
. shunit2
