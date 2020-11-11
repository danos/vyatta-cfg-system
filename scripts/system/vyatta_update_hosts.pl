#!/usr/bin/perl -w
#
# Module: vyatta_update_hosts.pl
#
# **** License ****
#
# Copyright (c) 2019-2020, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2016 Brocade Communications Systems, Inc.
#    All Rights Reserved.
#
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2012-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****
#
# Description:
# Script to update '/etc/hosts' on commit of 'system host-name' and
# 'system domain-name' config.
#

use strict;
use English;
use lib "/opt/vyatta/share/perl5/";

use File::Temp qw(tempfile);
use Vyatta::File qw(touch);
use Vyatta::Config;
use Getopt::Long;
use IPC::Run3;
use File::Copy;

my $HOSTS_CFG;
my $HOSTS_TMPL       = "/tmp/hosts.XXXXXX";
my $HOSTNAME_CFG     = '/etc/hostname';
my $MAILNAME_CFG     = '/etc/mailname';
my $restart_services = 1;

sub set_hostname {
    my ($hostname) = @_;
    run3( ["hostname", $hostname], \undef, undef, undef );
    open( my $f, '>', $HOSTNAME_CFG )
      or die("$0:  Error!  Unable to open $HOSTNAME_CFG for output: $!\n");
    print $f "$hostname\n";
    close($f);
}

sub set_mailname {
    my ($mailname) = @_;
    open( my $f, '>', $MAILNAME_CFG )
      or die("$0:  Error!  Unable to open $MAILNAME_CFG for output: $!\n");
    print $f "$mailname\n";
    close($f);
}

if ( $EUID != 0 ) {
    printf("This program must be run by root.\n");
    exit 1;
}

my $domain_name;
my $vrf_name;
GetOptions(
    "restart-services!" => \$restart_services,
    "vrf=s"             => \$vrf_name
);

my $vc = new Vyatta::Config();

$vc->setLevel('system');
my $host_name = $vc->returnValue('host-name');
$HOSTS_CFG = '/etc/hosts';
if ($vrf_name) {
    $vc->setLevel("routing routing-instance $vrf_name system");
    $HOSTS_CFG = "/run/dns/vrf/$vrf_name/hosts";
}

my $mail_name;
my $hosts_line = "127.0.1.1\t ";

if ( !defined $host_name ) {
    $host_name = 'node';
}
$mail_name = $host_name;

$domain_name = $vc->returnValue('domain-name');
if ( defined $domain_name ) {
    $hosts_line .= $host_name . '.' . $domain_name;
    if ( !$vrf_name ) {
        $mail_name .= '.' . $domain_name;
        run3( ["domainname", $domain_name], \undef, undef, undef );
    }
}
$hosts_line .= " $host_name\t #vyatta entry\n";

my ( $out, $tempname ) = tempfile( $HOSTS_TMPL, UNLINK => 1 )
  or die "Can't create temp file: $!";

if ( !-e $HOSTS_CFG ) {
    touch $HOSTS_CFG;
}
open( my $in, '<', $HOSTS_CFG )
  or die("$0:  Error!  Unable to open '$HOSTS_CFG' for input: $!\n");

while ( my $line = <$in> ) {
    if ( $line =~ m:^127.0.1.1: ) {
        next;
    }
    print $out $line;
}
print $out $hosts_line;

close($in);
close($out);

copy($tempname, $HOSTS_CFG)
  or die "Can't copy $tempname to $HOSTS_CFG";

set_hostname $host_name;
set_mailname $mail_name;

# Restart services that use the system hostname;
# add more ase needed.
if ($restart_services) {
    if ($vrf_name) {
        my @cmd = ("systemctl", "reload-or-restart", "rsyslog\@$vrf_name");
        run3( \@cmd, \undef, undef, undef )
          if ( -d "/run/rsyslog/vrf/$vrf_name" );
    } else {
        my @cmd = ("systemctl", "reload-or-restart", "rsyslog");
        run3( \@cmd, \undef, undef, undef );
    }
    run3( ["systemctl", "condrestart", "snmpd"], \undef, undef, undef );
}
