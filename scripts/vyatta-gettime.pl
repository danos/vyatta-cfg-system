#!/usr/bin/perl
#
# Module: vyatta-gettime.pl
#
# **** License ****
#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Stephen Hemminger
# Date: March 2009
# Description: Script to read time for shutdown
#
# **** End License ****
#

use strict;
use warnings;
use Date::Format;

sub gettime {
    my $t = shift;

    return time2str( "%R", time ) if ( $t eq 'now' );
    return $t if ( $t =~ /^[0-9]+:[0-9]+/ );
    $t = substr( $t, 1 ) if ( $t =~ /^\+/ );
    return time2str( "%R", time + ( $_ * 60 ) ) if ( $t =~ /^[0-9]+/ );

    die "invalid time format: $t\n";
}

# decode shutdown time
for (@ARGV) {
    print gettime($_), "\n";
}
