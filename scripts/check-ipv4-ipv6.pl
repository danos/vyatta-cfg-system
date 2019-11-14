#! /usr/bin/perl
#
# Trivial script to check for valid IPv4 or IPv6 address
#
# **** License ****
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****

use strict;
use warnings;
use NetAddr::IP;

foreach my $addr (@ARGV) {
    die "$addr: not valid a valid IPv4 or IPv6 address\n"
	unless new NetAddr::IP $addr;
}
