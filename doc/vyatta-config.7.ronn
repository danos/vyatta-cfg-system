vyatta-config(7) -- boot time parameter
=======================================

## SYNOPSIS

`vyatta-config=URL`

## DESCRIPTION

`vyatta-config` allows passing of Vyatta configuration to the livecd or an
installed image. The required `URL` argument points to

* a file with `*.boot` suffix  containing `config.boot` data

* a tarball with `*.tgz|*.tar` suffix  containing the contents of the `/config`
  directory

The boot time parameter is passed via the Linux kernel as any other kernel
boot time parameter or command-line option. This might require changing the
configuration of the boot loader in use (e.g. grub or PXE server).

`vyatta-config` may be passed multiple times.

## EXAMPLES

Building a `config.tar` that uses the default configuration of the image and
on the first boot after running `install image` enables DHCP and SSH service:

    $ mkdir scripts
    $ cat > scripts/vyatta-postconfig-bootup.script <<EOF
    #!/bin/bash
    
    if ! grep -qs vyatta-union /proc/cmdline ; then
      echo "Don't run on livecd"
      exit 0
    fi
    
    echo "Enabling DHCP and SSH service"
    /opt/vyatta/sbin/lu -user configd -- /bin/vcli <<"EOF"
    configure
    for device in /sys/class/net/dp*; do
      device=${device##*/}
      addr=($(list interfaces dataplane ${device} address))
      if [[ -z ${addr[@]} ]]; then
        set interface dataplane ${device} address dhcp
      fi
    done
    set service ssh
    commit
    end_configure
    EOF
    $ tar cf config.tar scripts/

Update the PXE configuration in `/srv/tftpboot/pxelinux.cfg/default`
accordingly to include the `vyatta-config` parameter:

    LABEL 4.2-config
    MENU LABEL 4.2R1
    KERNEL 4.2R1/vmlinuz
    INITRD 4.2R1/initrd.img
    APPEND console=tty0 console=ttyS0 boot=live nopersistent nonetworking noeject fetch=http://192.168.248.1/4.2R1/4.2R1.iso vyatta-config=http://192.168.248.1/config/config.boot
    IPAPPEND 0x2

## SEE ALSO

bootparam(7)
