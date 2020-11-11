# Module: RestoreIPV6Addr.pm
# Restore IPv6 addresses from configuration when
# interface is re-enabled
#
# Copyright (c) 2018-2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

package Vyatta::RestoreIPv6Addr;

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use File::Slurp;
use Vyatta::Address;
use Vyatta::Config;
use Vyatta::Interface;
use IPC::Run3;

sub restore_link_local;
sub restore_global;

# Test if IPv6 is disabled on this interface
sub ipv6_disabled {
    my $name     = shift;
    my $disabled = read_file( "/proc/sys/net/ipv6/conf/$name/disable_ipv6",
        err_mode => 'quiet' );
    return if ( !defined($disabled) );

    chomp $disabled;
    return $disabled;
}

# Test if keeping IPv6 addresses on admin down is enabled on this interface
sub ipv6_keep_addr_enabled {
    my $name    = shift;
    my $enabled = read_file( "/proc/sys/net/ipv6/conf/$name/keep_addr_on_down",
        err_mode => 'quiet' );
    return 0 if ( !defined($enabled) );

    chomp $enabled;
    return $enabled;
}

# Wait for dad to complete
sub wait_for_dad {
    my $name = shift;

    # IPv6 creates a link local address as soon as the interface is brought
    # up.  Wait for the link local address before adding other addresses.
    my ( $dad_on, $retry_sec, $retry_n ) =
      Vyatta::Address::ipv6_dad_config($name);

    # Start with a quick retry, before reverting to configured retry interval
    for ( my $retries = 0 ; $$dad_on and $retries < $$retry_n ; $retries++ ) {
        my $link_output = qx(ip -6 addr show dev $name scope link);
        last if length($link_output) && $link_output !~ /tentative/;
        sleep $$retry_sec;
    }
}

# Restore link-local addresses on sub-interfaces
sub restore_link_local_on_sub_intfs {
    my ( $name, $config ) = @_;

    foreach my $vif ( $config->listNodes("vif") ) {
        restore_link_local(
            {
                interfaces => ["$name.$vif"]
            }
        );
    }
}

# Restore link-local addresses on list of interfaces
sub restore_link_local {
    my ($args) = @_;
    foreach my $name ( @{ $args->{interfaces} } ) {
        my $disabled = ipv6_disabled($name);
        next if !defined($disabled);

        my $intf = new Vyatta::Interface($name);
        $intf or die "Unknown interface name/type: $name\n";
        my $config = new Vyatta::Config( $intf->path() );

        # Sub-interfaces may be enabled for IPv6, even if the lower intf is not
        restore_link_local_on_sub_intfs( $name, $config ) || next if $disabled;

        # If link-local address is configured, update it before waiting for DAD
        my $lladdr = $config->returnValue('ipv6 address link-local');
        my @cmd = ("vyatta-ipv6-link-local.pl", "--update", $name, $lladdr);
        run3( \@cmd, \undef, undef, undef ) if ($lladdr);
        restore_link_local_on_sub_intfs( $name, $config );
    }
}

# Restore global addresses on sub-interfaces
sub restore_global_on_sub_intfs {
    my ( $name, $config, $options ) = @_;

    foreach my $vif ( $config->listNodes("vif") ) {
        restore_global(
            {
                interfaces      => ["$name.$vif"],
                no_wait_for_dad => $options->{no_wait_for_dad},
                restore_ll_only => $options->{restore_ll_only},
                force_restore   => $options->{force_restore},
                old_mac         => $options->{old_mac}
            }
        );
    }
}

# Restore global addresses on list of interfaces
sub restore_global {
    my ($args) = @_;
    my @cmd = ();
    foreach my $name ( @{ $args->{interfaces} } ) {
        my $disabled = ipv6_disabled($name);
        next if !defined($disabled);

        my $intf = new Vyatta::Interface($name);
        $intf or die "Unknown interface name/type: $name\n";
        my $config     = new Vyatta::Config( $intf->path() );

        # Sub-interfaces may be enabled for IPv6, even if the lower intf is not
        restore_global_on_sub_intfs( $name, $config, $args ) || next
          if $disabled;

        # Even if not restoring global addr, need delay for dhcpv6 client
        wait_for_dad($name)
          unless $config->exists("disable") || $args->{no_wait_for_dad};
        next if $args->{restore_ll_only};

       # No need to restore global addresses if kernel is keeping them
       # If IPv6 was disabled, force restore to add new addr in config to kernel
        next if ( !$args->{force_restore} && ipv6_keep_addr_enabled($name) );

        foreach my $addr ( $config->returnValues('address') ) {
            next if Vyatta::Address::is_ipv4($addr);
            my $result = qx(ip -6 addr add $addr dev $name 2>&1);
            if ( $? && index( $result, "File exists" ) == -1 ) {
                warn "restore $addr on $name failed ($result)\n";
            }
        }

        foreach my $eui ( $config->returnValues('ipv6 address eui64') ) {
            if ( $args->{old_mac} ) {
                @cmd = ("vyatta-ipv6-eui64.pl", "--delete",
                        $name, $eui, $args->{old_mac});
                run3( \@cmd, \undef, undef, undef );
            }
            @cmd = ("/opt/vyatta/sbin/vyatta-ipv6-eui64.pl",
                    "--create", $name, $eui);
            run3( \@cmd, \undef, undef, undef );
        }

        restore_global_on_sub_intfs( $name, $config, $args );
    }
}

# Restore list of addresses on list of interfaces
sub restore_address {
    restore_link_local(@_);
    restore_global(@_);
}

1;
