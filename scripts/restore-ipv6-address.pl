#! /usr/bin/perl
#
# Copyright (c) 2017-2019, AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2007-2016, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Script to restore IPv6 addresses from configuration when
# interface is re-enabled

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Getopt::Long;
use Vyatta::Config;
use Vyatta::RestoreIPv6Addr;

my $no_wait_for_dad;
my $restore_ll_only;
my $force_restore;
my $old_mac;

sub usage {
    print "Usage: $0 [--no-wait-for-dad] [--restore-ll-only] [--force-restore]",
      " [--old-mac <mac>] [<ifname>]\n";
    exit 1;
}

GetOptions(
    "no-wait-for-dad" => \$no_wait_for_dad,
    "restore-ll-only" => \$restore_ll_only,
    "force-restore"   => \$force_restore,
    "old-mac=s"       => \$old_mac,
) or usage();

sub restore_addresses {
    Vyatta::RestoreIPv6Addr::restore_address(
        {
            interfaces      => [@_],
            no_wait_for_dad => $no_wait_for_dad,
            restore_ll_only => $restore_ll_only,
            force_restore   => $force_restore,
            old_mac         => $old_mac
        }
    );
}

if (@ARGV) {
    restore_addresses(@ARGV);
} else {
    my $config     = new Vyatta::Config;
    my @interfaces = ();
    foreach my $iftype ( $config->listNodes("interfaces") ) {
        push( @interfaces, $config->listNodes("interfaces $iftype") );
    }
    restore_addresses(@interfaces);
}
