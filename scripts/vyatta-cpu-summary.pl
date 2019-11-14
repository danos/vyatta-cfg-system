#! /usr/bin/perl
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

# implement "show cpu-info"

use strict;
use warnings;

open my $cpuinfo, '<', '/proc/cpuinfo'
  or die "Can't open /proc/cpuinfo : $!";

my %models;
my %packages;
my %cores;

my %map = (
    'model name'  => \%models,
    'physical id' => \%packages,
    'core id'     => \%cores
);

my $cpu = 0;
while (<$cpuinfo>) {
    chomp;
    my ( $tag, $val ) = split /:/;
    if ( !$tag ) {
        ++$cpu;
        next;
    }

    $tag =~ s/\s+$//;
    $val =~ s/^\s+//;

    my $ref = $map{$tag};
    $ref->{$val} = $cpu  if ($ref);
}
close $cpuinfo;

print "Processors ", $cpu, "\n";
print "Packages   ", scalar keys %packages, "\n" if (%packages);
print "Cores      ", scalar keys %cores,    "\n" if (%cores);

# Handle any attempt to run different CPU models 
print "Model      ", join( "       \n", keys %models ), "\n";
