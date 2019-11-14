#!/usr/bin/perl
#
# Module: vyatta-monitor.pl
#
# Copyright (c) 2018-2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;
use Sys::Hostname;

# Positional args, "label", followed by the match pattern
my $nargs = $#ARGV +1;
if ($nargs < 2) {
	print "Usage: $0 label pattern0 [pattern1]...\n";
	exit 1;
}

# Label is the first arg.
my $label = shift @ARGV;

# Look for matches against the remaining args
# match against "foo: " as well as "foo[<pid>]: "

my $prev_match = undef;
my $str;

my $timestamp;
my $host = hostname;

while ( my $line = <STDIN>) {
	foreach my $a (@ARGV) {
		# Match all text up until hostname, which is a timestamp
		$timestamp = q{};
		if ($line =~ /^(.*?)$host/) {
			$timestamp = $1;	
		}
		# Get & print the repeat count
		if (defined($prev_match)) {
			if ($line =~ /last message repeated/) {
				$str = substr($line, $-[0]);
				print "$timestamp$label: $str";
			}
			$prev_match = undef;
		}

		if ($line =~ /$a(\[\d+\])?/) {
			$str = substr($line, $-[0]);
			print "$timestamp$label: $str";
			$prev_match = 1;
		}
	}
}
