#!/usr/bin/perl

# **** License ****
#
# Copyright (c) 2018-2019 AT&T Intellectual Property.
#    All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use File::Compare;
use File::Temp qw/ tempfile /;
use Vyatta::Config::Parse;

my $rl_interval;
my $rl_burst;

my $JOURNALD_CONF = '/etc/systemd/journald.conf.d/10-vyatta-rate-limit.conf';
my $JOURNALD_TMPL = "/tmp/journald.conf.XXXXXX";

sub get_rate_limit_parms {
    my ($config) = @_;

    if ( defined($config->{'rate-limit'}) ) {
	$rl_interval = $config->{'rate-limit'}->{'interval'} . "s";
	$rl_burst    = $config->{'rate-limit'}->{'burst'};
    }
}

#
# Print out rate limiting parameters
#
sub print_rate_limit_settings {
    my ($out) = @_;

    if ( defined($rl_interval) ) {
        print $out <<"END";
[Journal]
RateLimitInterval=$rl_interval
RateLimitBurst=$rl_burst
END
    }
}

#
# Write out the actual journal configuration file. This file is
# created as a temp file. This function returns 0 if the created
# file is the same as an existing file. It copies the temp file over
# the existing file if it is different and returns 1.
#
sub write_journald_config_file {
    my ($config_file) = @_;

    my ( $out, $tempname ) = tempfile( $JOURNALD_TMPL, UNLINK => 1 )
      or die "Can't create temp file: $!";

    print_rate_limit_settings($out);

    close $out
      or die "Can't output $tempname: $!";

    if ( -e $config_file && compare( $config_file, $tempname ) == 0 ) {
        unlink($tempname);
        return 0;
    }

    system("cp $tempname $config_file") == 0
      or die "Can't copy $tempname to $config_file: $!";
    chmod 0644, $config_file;

    unlink($tempname);
    return 1;
}

#
# Setup the configuration file
#
sub create_journald_config {
    my $config = new Vyatta::Config::Parse("system journal");
    $config = $config->{'journal'};

    get_rate_limit_parms($config);
    my $ret = write_journald_config_file($JOURNALD_CONF);
    system("service systemd-journald restart")
      if ( $ret == 1 );

}

create_journald_config();
