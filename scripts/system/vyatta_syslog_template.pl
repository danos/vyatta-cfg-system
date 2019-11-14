#!/usr/bin/perl

# **** License ****
#
# Copyright (c) 2018-2019 AT&T Intellectual Property.
#    All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use File::Compare;
use File::Path qw(make_path remove_tree);
use File::Temp qw/ tempfile /;
use Getopt::Long;
use Sys::Syslog qw(:standard :macros);

my $SYSLOG_TMPL      = "/tmp/rsyslog.template.XXXXXX";
my $DEFAULT_VRF_NAME = 'default';

my $op_mode = 0;
my $src_intf;
my $vrf;

GetOptions(
    "op-mode"    => \$op_mode,
    "src-intf=s" => \$src_intf,
    "vrf=s"      => \$vrf
) or usage();

sub usage {
    print <<EOF;
Usage:	$0 --src-intf <ifname> [--vrf <vrf>] [--op-mode]
EOF
    exit 1;
}

#
# Get source addresses for a given source interface
#
# Obtain these operationally rather than via config so as to get actual addrs
# for all cases, e.g for IPv4 DHCP, or IPv6 DHCPv6, SLAAC or EUI64 addrs. Note
# that no chvrf is needed for iproute2 cmds with upstream VRF solution, and VRF
# of interface is checked elsewhere.
#
sub get_src_addrs {
    my $ifname = shift;
    my ( $ipaddr, $ip6addr ) = ( undef, undef );
    my $cmd = "ip addr show scope global dev $ifname";

    open my $ipcmd, '-|'
      or exec $cmd
      or die "ip addr command failed: $!";
    if ( ( <$ipcmd> // '' ) !~ /,UP/ ) {
        return ( undef, undef );
    }
    while (<$ipcmd>) {
        my ( $proto, $ifaddr ) = split;
        next unless ( $proto =~ /inet/ );
        my ($addr) = ( $ifaddr =~ /([^\/]+)/ );
        if ( $proto eq 'inet' ) {
            next if defined($ipaddr);
            $ipaddr = $addr;
        } elsif ( $proto eq 'inet6' ) {
            next if defined($ip6addr);
            $ip6addr = $addr;
        }
    }
    close $ipcmd;

    return ( $ipaddr, $ip6addr );
}

# main
my $config_path;
my $config_file;
my $template_file;
my $src_intf_match = 0;
my ( $src_ipaddr,       $src_ip6addr );
my ( $src_ipaddr_match, $src_ip6addr_match );
my $vrf_str;

usage() unless defined($src_intf);

if ( !defined($vrf) || $vrf eq $DEFAULT_VRF_NAME ) {
    $config_file   = "/etc/rsyslog.d/vyatta-log.conf";
    $template_file = "/run/vyatta/rsyslog/vyatta-log.template";
    $vrf_str       = "";
} else {
    $config_path   = "/run/rsyslog/vrf/$vrf/rsyslog.d";
    $config_file   = "$config_path/vyatta-log.conf";
    $template_file = "/run/vyatta/rsyslog/vrf/$vrf/vyatta-log.template";
    make_path( $config_path, { verbose => 0, mode => oct("0755") } );
    $vrf_str = " in vrf $vrf";
}

# Template file is only present if source interface configured
if ( !( -f $template_file ) ) {
    exit 0 if $op_mode;
    die "Template file not found: $template_file\n";
}

# Write to a temp file first, which allows a comparison with current config file
# if it exists. This approach avoids rsyslog being unnecessarily restarted.
my ( $out, $tmp_file ) = tempfile( $SYSLOG_TMPL, UNLINK => 1 )
  or die "Can't create temp file: $!";

open my $in, '<', $template_file
  or die "Can't open $template_file: $!";

while (<$in>) {
    if (/SRC_INTF/) {
        my $intf = (split / /,$_)[1];
        $intf =~ s/^\s+|\s+$//g;
        last if ( $src_intf ne $intf );
        $src_intf_match = 1;
        ( $src_ipaddr, $src_ip6addr ) = get_src_addrs($src_intf);
    } elsif ( !$src_intf_match ) {

        # Ignore any lines preceding that giving the source interface
        next;
    } elsif (/SRC_IPADDR/) {

        # Only add host forwarding if have a source address of the same AF
        if ( defined($src_ipaddr) ) {
            $_ =~ s/SRC_IPADDR/$src_ipaddr/;
            print $out $_;
            $src_ipaddr_match = 1;
        } else {
            $src_ipaddr_match = 0;
        }
    } elsif (/SRC_IP6ADDR/) {

        # Only add host forwarding if have a source address of the same AF
        if ( defined($src_ip6addr) ) {
            $_ =~ s/SRC_IP6ADDR/$src_ip6addr/;
            print $out $_;
            $src_ip6addr_match = 1;
        } else {
            $src_ip6addr_match = 0;
        }
    } else {
        print $out $_;
    }
}

close $in  or die "Can't close $config_file: $!";
close $out or die "Can't output $tmp_file: $!";

my $src_intf_str = "$src_intf$vrf_str";

# Logging occurs regardless of op_mode setting, whereas output to console is
# only in cfg mode and not op mode.
my $expl_str = "";

openlog( "syslog", "", LOG_USER );
if ( defined($src_ipaddr_match) ) {
    if ($src_ipaddr_match) {
        syslog( LOG_INFO,
                "Logging to IPv4 hosts enabled using source address "
              . "$src_ipaddr on interface $src_intf_str\n" );
        $expl_str = "         It is confirmed though that logging to IPv4 "
          . "hosts is enabled.\n ";
    } else {
        syslog( LOG_WARNING,
                "Logging to IPv4 hosts disabled until $src_intf_str has an "
              . "IPv4 address and is up" );
    }
}
if ( defined($src_ip6addr_match) ) {
    if ($src_ip6addr_match) {
        syslog( LOG_INFO,
                "Logging to IPv6 hosts enabled using source address "
              . "$src_ip6addr on interface $src_intf_str\n" );
        $expl_str = "         It is confirmed though that logging to IPv6 "
          . "hosts is enabled.\n ";
    } else {
        syslog( LOG_WARNING,
                "Logging to IPv6 hosts disabled until $src_intf_str has an "
              . "IPv6 address and is up" );
    }
}
closelog();

if ( !$op_mode ) {
    if ( defined($src_ipaddr_match) && !$src_ipaddr_match ) {
        print "Warning: Logging to IPv4 hosts disabled until source interface "
          . "$src_intf_str\n         has an IPv4 address and is up.\n$expl_str";
    }
    if ( defined($src_ip6addr_match) && !$src_ip6addr_match ) {
        print "Warning: Logging to IPv6 hosts disabled until source interface "
          . "$src_intf_str\n         has an IPv6 address and is up.\n$expl_str";
    }
}

if ( !$src_intf_match ) {
    unlink($tmp_file);
    exit 0;
}

if ( -e $config_file && compare( $config_file, $tmp_file ) == 0 ) {
    unlink($tmp_file);
    exit 0;
}

system("cp $tmp_file $config_file") == 0
  or die "Can't copy $tmp_file to $config_file: $!";
chmod 0644, $config_file;

unlink($tmp_file);
exit 1;
