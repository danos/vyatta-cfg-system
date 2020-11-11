#!/usr/bin/perl
#
# Module: vyatta_update_resolv.pl
#
# **** License ****
# Copyright (c) 2019-2020, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2016 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Marat Nepomnyashy
# Date: December 2007
# Description: Script to update '/etc/resolv.conf'
#	on commit of 'system domain-search domain' config.
#
# **** End License ****
#

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;

use Getopt::Long;
use IPC::Run3;

my $has_vrf;

BEGIN {
    if ( eval { require Vyatta::VrfManager; 1 } ) {
        $has_vrf = 1;
    }
}

my $dhclient_script = 0;
my $dhclient_tmp_file_dir = "var/lib/dhcp";
my $intf = undef;
my $vrf_name;
my $resolv_conf_path;
my $config_prefix;

GetOptions(
    "dhclient-script=i" => \$dhclient_script,
    "interface=s"       => \$intf,
    "vrf=s"             => \$vrf_name,
);

# use proper Configd API base on whether it is called from dhclient script
my $returnValues = ( $dhclient_script ? "returnOrigValues" : "returnValues" );
my $returnValue  = ( $dhclient_script ? "returnOrigValue"  : "returnValue" );
my $listNodes    = ( $dhclient_script ? "listOrigNodes"    : "listNodes" );
my $exists       = ( $dhclient_script ? "existsOrig"       : "exists" );

# find out which vrf the interface belongs to
sub get_vrf_name {
    my $intf = shift;
    return 'default' unless $has_vrf;
    return eval { Vyatta::VrfManager::get_interface_vrf( $intf ) };
}

# main
if ( ($dhclient_script == 1) &&
     (defined $intf) ) { # calling from dhclient script
    $vrf_name = get_vrf_name ( $intf );
}

if ( ! defined $vrf_name ) {
    $vrf_name = "default";
}

if ( $vrf_name eq "default") {
    $config_prefix = "system";
    $resolv_conf_path = "/etc/resolv.conf";
} else {
    $config_prefix = "routing routing-instance $vrf_name system";
    $resolv_conf_path = "/run/dns/vrf/$vrf_name/resolv.conf";
    if ((! -e "/run/dns/vrf/$vrf_name") ||
        (! -d "/run/dns/vrf/$vrf_name") ) {
        system "mkdir -p /run/dns/vrf/$vrf_name";
    }
}

`touch $resolv_conf_path`;

my $vc = new Vyatta::Config();

$vc->setLevel("$config_prefix");

my @domains;
my $domain_name = undef;

@domains = $vc->$returnValues('domain-search domain');
$domain_name = $vc->$returnValue('domain-name');

if ($dhclient_script == 0 && @domains > 0 && $domain_name && length($domain_name) > 0) {
    my @loc;
    if ($vc->returnOrigValues('domain-search domain') > 0) {
	@loc = ["system","domain-name"];
    }
    else {
	@loc = ["system","domain-search","domain"];
    }
    Vyatta::Config::outputError(@loc,"System configuration error.  Both \'domain-name\' and \'domain-search\' are specified, but only one of these mutually exclusive parameters is allowed.");
    exit(1);
}

my $doms = '';
foreach my $domain (@domains) {
	if (length($doms) > 0) {
		$doms .= ' ';
	}
	$doms .= $domain;
}

# find dhclient resolv.conf files in a vrf
my @dhcp_interfaces_resolv_files;
opendir( my $dirh, "/$dhclient_tmp_file_dir" );
if ( defined($dirh) ) {
    for my $fname ( readdir($dirh) ) {
        if ( $fname =~ /^dhclient-v[46]-(\w+(\.\d+)?)-resolv\.conf$/ ) {
            push @dhcp_interfaces_resolv_files, $fname
              if ( get_vrf_name($1) eq $vrf_name );
        }
    }
    closedir($dirh);
}

# add domain names received from dhcp client to domain search in /etc/resolv.conf if domain-name not set in CLI
if (!defined($domain_name)) {
  if ($#dhcp_interfaces_resolv_files >= 0) {
    for my $each_file (@dhcp_interfaces_resolv_files) {
       chomp $each_file;
       my $find_search = `grep "^search" /$dhclient_tmp_file_dir/$each_file 2> /dev/null | wc -l`;
       if ($find_search == 1) {
            my $search_string = `grep "^search" /$dhclient_tmp_file_dir/$each_file`;
            my @dhcp_domains = split(/\s+/, $search_string, 2);
            my $dhcp_domain = $dhcp_domains[1];
            chomp $dhcp_domain;
            $doms .= ' ' . $dhcp_domain;
       }
    }
  }
}

my $search = '';
if (length($doms) > 0) {
	$search = "search\t\t$doms\n";
}

my $domain = '';
if ($domain_name && length($domain_name) > 0) {
	$domain = "domain\t\t$domain_name\n";
}

# update /etc/resolv.conf for name-servers received from dhcp client, only done when dhclient-script calls this script
if ($dhclient_script == 1) {
  my @current_dhcp_nameservers;
  my $restart_ntp = 0;

  # code below to add new name-servers received from dhcp client

  if ($#dhcp_interfaces_resolv_files >= 0) {
    my $ns_count = 0;
    for my $each_file (@dhcp_interfaces_resolv_files) {
       chomp $each_file;
       my $find_nameserver = `grep nameserver /$dhclient_tmp_file_dir/$each_file 2> /dev/null | wc -l`;
       if ($find_nameserver > 0) {
            my @nameservers = `grep nameserver /$dhclient_tmp_file_dir/$each_file`;
            for my $each_nameserver (@nameservers) {
               my @nameserver = split(/ /, $each_nameserver, 2);
               my $ns = $nameserver[1];
               chomp $ns;
               $current_dhcp_nameservers[$ns_count] = $ns;
               $ns_count++;
               my @search_ns_in_resolvconf = `grep $ns $resolv_conf_path`;
               my $ns_in_resolvconf = 0;
               if (@search_ns_in_resolvconf > 0) {
                  foreach my $ns_resolvconf (@search_ns_in_resolvconf) {
                       my @resolv_ns = split(/\s+/, $ns_resolvconf);
                       my $final_ns = $resolv_ns[1];
                       chomp $final_ns;
                       if ($final_ns eq $ns) {
                           $ns_in_resolvconf = 1;
                       }
                  }
               }
               if ($ns_in_resolvconf == 0) {
		   open (my $rf, '>>', $resolv_conf_path)
		       or die "$! error trying to overwrite";
		   print $rf "nameserver\t$ns\n";
		   close $rf;
		   $restart_ntp = 1;
               }
            }
       }
    }
  }

  # code below to remove old name-servers from /etc/resolv.conf that were not received in this response from dhcp-server

  my @nameservers_dhcp_in_resolvconf = `grep 'nameserver' $resolv_conf_path | grep -v '# system'`;
  my @dhcp_nameservers_in_resolvconf;
  my $count_nameservers_in_resolvconf = 0;
  for my $count_dhcp_nameserver (@nameservers_dhcp_in_resolvconf) {
     my @dhcp_nameserver = split(/nameserver/, $count_dhcp_nameserver);
     $dhcp_nameserver[1]=~s/^\s+|\s+$//g;
     $dhcp_nameservers_in_resolvconf[$count_nameservers_in_resolvconf] = $dhcp_nameserver[1];
     $count_nameservers_in_resolvconf++;
  }
  if ($#current_dhcp_nameservers < 0) {
    for my $dhcpnameserver (@dhcp_nameservers_in_resolvconf) {
        my $cmd = ["sed", "-i", "'/$dhcpnameserver/d'", $resolv_conf_path];
        run3( $cmd, \undef, undef, undef );
        $restart_ntp = 1;
    }
  } else {
         for my $dhcpnameserver (@dhcp_nameservers_in_resolvconf) {
            my $found = 0;
            for my $currentnameserver (@current_dhcp_nameservers) {
               if ($dhcpnameserver eq $currentnameserver){
                  $found = 1;
               }
            }
            if ($found == 0) {
              my $cmd = ["sed", "-i", "'/$dhcpnameserver/d'", $resolv_conf_path];
              run3( $cmd, \undef, undef, undef );
              $restart_ntp = 1;
            }

        }
   }
 if ($restart_ntp == 1) {
     # this corresponds to what is done in name-server/node.def as a fix for bug 1300
     my $cmd_ntp_restart = "if [ -f /etc/ntp.conf ] && grep -q '^server' /etc/ntp.conf; then /usr/sbin/invoke-rc.d ntp try-restart >&/dev/null; fi &";
     system($cmd_ntp_restart);
 }
}

# The following will re-write '/etc/resolv.conf' line by line,
# replacing the 'search' specifier with the latest values,
# or replacing the 'domain' specifier with the latest value.

my @resolv;
if (-e $resolv_conf_path) {
    open (my $f, '<', $resolv_conf_path)
	or die("$0:  Error!  Unable to open $resolv_conf_path for input: $!\n");
    @resolv = <$f>;
    close ($f);
}


my $foundSearch = 0;
my $foundDomain = 0;

my $already_marked = `grep "file generated by $0 do not edit" $resolv_conf_path 2> /dev/null | wc -l`;
open (my $r, '>', $resolv_conf_path)
    or die("$0:  Error!  Unable to open $resolv_conf_path for output: $!\n");

if ($already_marked == 0) {
        print {$r} "# file generated by $0 do not edit\n";
}

foreach my $line (@resolv) {
	if ($line =~ /^search\s/) {
		$foundSearch = 1;
		if (length($search) > 0) {
			print {$r} $search;
		}
	} elsif ($line =~ /^domain\s/) {
		$foundDomain = 1;
		if (length($domain) > 0) {
			print {$r} $domain;
		}
	} else {
		print {$r} $line;
	}
}
if ($foundSearch == 0 && length($search) > 0) {
	print {$r} $search;
}
if ($foundDomain == 0 && length($domain) > 0) {
	print {$r} $domain;
}

close ($r);
