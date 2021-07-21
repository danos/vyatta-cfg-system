# Module: PlatformConfig.pm
# Functions to assist with maintenance of platform configuration.
# Derived class of FeatureConfig
#
# Copyright (c) 2018-2021 AT&T Intellectual Property.
#    All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package Vyatta::PlatformConfig;
use strict;
use warnings;
use Vyatta::FeatureConfig;

require Exporter;

my $MOD_NAME      = "PlatformConfig.pm";
my $PLATFORM_CONF = "/etc/vyatta/platform-params.conf";
my $MAIN_SEC_NAME = "Platform";

our @ISA       = qw (Exporter FeatureConfig);
our @EXPORT_OK = qw (set_cfg get_cfg del_cfg);

sub set_cfg {
    my ( $var, $value, $default, $section ) = @_;
    my $cfg;

    if ( !-f $PLATFORM_CONF ) {
        Vyatta::FeatureConfig::setup_cfg_file( $MOD_NAME, $PLATFORM_CONF,
            $MAIN_SEC_NAME );
    }

    if ( !defined($section) ) {
        $section = $MAIN_SEC_NAME;
    }
    Vyatta::FeatureConfig::set_cfg( $PLATFORM_CONF, $section,
        $var, $value, $default );
}

sub get_cfg {
    my ( $attr, $default, $section ) = @_;
	my $value;

	if (defined($default) && $default) {
		$value = Vyatta::FeatureConfig::get_default_cfg( $PLATFORM_CONF, $attr);
	} else {
		if ( !defined($section) ) {
			$section = $MAIN_SEC_NAME;
		}
		$value = Vyatta::FeatureConfig::get_cfg( $PLATFORM_CONF, $section,
												 $attr ); 
	}
	return $value;
}

sub del_cfg {
    my ( $attr, $default, $section ) = @_;
    if ( !defined($section) ) {
        $section = $MAIN_SEC_NAME;
    }
    return Vyatta::FeatureConfig::del_cfg( $PLATFORM_CONF, $section, $attr,
        $default );
}
