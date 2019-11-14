#!/usr/bin/perl

# **** License ****
#
# Copyright (c) 2017,2019, 2018 AT&T Intellectual Property.
#    All Rights Reserved.
# Copyright (c) 2014-2017, Brocade Communications Systems, Inc.
#    All Rights Reserved.
#
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****

# Update /etc/rsyslog.d/vyatta-log.conf
# Exit code: 0 - update
#            1 - no change or error

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config::Parse;
use File::Basename;
use File::Compare;
use File::Temp qw/ tempfile /;
use File::Path qw(make_path remove_tree);
use Net::IP;
use NetAddr::IP;
use Sys::Syslog qw(:standard :macros);
use Template;

my $vrf_available;
BEGIN {
    if ( eval { use Vyatta::VrfManager qw(get_vrf_id); } ) {
        $vrf_available = 1;
    }
}

my $SYSLOG_PORT       = "514";
my $SYSLOG_CONF       = '/etc/rsyslog.d/vyatta-log.conf';
my $SYSLOG_TEMPLATE   = '/run/vyatta/rsyslog/vyatta-log.template';
my $SYSLOG_TMPL       = "/tmp/rsyslog.conf.XXXXXX";
my $MESSAGES          = '/var/log/messages';
my $CONSOLE           = '/dev/console';
my $LOGROTATE_CFG_DIR = '/opt/vyatta/etc/logrotate';
my $VRF_CFG_DIR       = '/run/rsyslog/vrf';
my $DEFAULT_VRF_NAME  = 'default';

# Values come from /usr/include/sys/syslog.h
my %FACILITY_VALS = (
    'kernl' => (0<<3),
    'user' => (1<<3),
    'mail' => (2<<3),
    'daemon' => (3<<3),
    'auth' => (4<<3),
    'syslog' => (5<<3),
    'lpr' => (6<<3),
    'news' => (7<<3),
    'uucp' => (8<<3),
    'cron' => (9<<3),
    'authpriv' => (10<<3),
    'ftp' => (11<<3),
    'local0' => (16<<3),
    'local1' => (17<<3),
    'local2' => (18<<3),
    'local3' => (19<<3),
    'local4' => (20<<3),
    'local5' => (21<<3),
    'local6' => (22<<3),
    'local7' => (23<<3)
);

my %SEVERITY_VALS = (
    'emerg' => 0,
    'alert' => 1,
    'crit' => 2,
    'err' => 3,
    'warning' => 4,
    'notice' => 5,
    'info' => 6,
    'debug' => 7,
);

my @SEVERITY_NAMES = (
    'emerg',
    'alert',
    'crit',
    'err',
    'warning',
    'notice',
    'info',
    'debug',
);

my %entries       = ();
my %fac_override  = ();
my %host_src_addr = ();
my @vrf_list      = ();
my @discard_regexs = ();
my $rl_interval;
my $rl_burst;
my $src_intf;

die "$0 expects no arguments\n" if (@ARGV);

sub upstream_vrf {
    return ( !-e "/proc/self/rtg_domain" );
}

sub get_rate_limit_parms {
    my ( $config ) = @_;

    $rl_interval = $config->{'rate-limit'}->{'interval'};
    $rl_burst = $config->{'rate-limit'}->{'burst'};
 
}

sub get_discard_regexs {
    my ( $config ) = @_;

    my $discard = get_node( $config, 'discard' );
    my $msgprop = get_node( $discard, 'msg' );
    my $discardregexlist = $msgprop->{'regex'};

    return unless defined($discardregexlist);

    foreach my $regex (@{ $discardregexlist }) {
        push @discard_regexs, $regex;
    }
}

sub add_target_selector {
    my ( $selector, $target ) = @_;

    $entries{$target}{selector} = [] unless $entries{$target}{selector};
    push @{ $entries{$target}{selector} }, $selector;
}

sub add_target_msgregex {
    my ( $msgregex, $target ) = @_;

    $entries{$target}{msgregex} = [] unless $entries{$target}{msgregex};
    push @{ $entries{$target}{msgregex} }, $msgregex;
}

sub set_target_param {
    my ( $config, $target, $param ) = @_;

    $entries{$target}{$param} = $config->{'archive'}->{$param};
}

sub get_target_param {
    my ( $target, $param ) = @_;
    return $entries{$target}{$param};
}

# This allows overloading local values in CLI
my %facmap = (
    'all'       => '*',
    'sensors'	=> 'local4',
    'dataplane' => 'local6',
    'protocols' => 'local7',
);

# This builds a data structure that maps from target
# to selector list for that target
sub read_config {
    my ( $config, $target ) = @_;

    my $facilitylist = get_node( $config, 'facility' );
    my $msgprop = get_node( $config, 'msg' );
    my $msgregexlist = $msgprop->{'regex'};

    if (!defined($facilitylist) && !defined($msgregexlist)) {
	warn "WARNING: At least one syslog facility or message regex should be configured per target!\n";
	return;
    }

    foreach my $facility (keys %{$facilitylist}) {
        my $loglevel = $facilitylist->{$facility}->{'level'};

        $facility = $facmap{$facility} if ( $facmap{$facility} );
        $loglevel = '*' if ( $loglevel eq 'all' );

        $entries{$target} = {} unless $entries{$target};
        add_target_selector( $facility . '.' . $loglevel, $target );
    }

    foreach my $regex (@{ $msgregexlist }) {
        $entries{$target} = {} unless $entries{$target};
        add_target_msgregex( $regex, $target );
    }

    # This is a file target so we set size and files
    if ($target =~ m:^/var/log/:) {
        set_target_param($config, $target, 'size');
        set_target_param($config, $target, 'files');
    }
}

sub print_outchannel {
    my ( $fh, $channel, $target, $size ) = @_;

    # Verify there is something to print
    return unless ($entries{$target}{selector} || $entries{$target}{msgregex});

    # Force outchannel size to be 1k more than logrotate config to guarantee rotation
    $size = ($size + 5) * 1024;
    print $fh "\$outchannel $channel,$target,$size,/usr/sbin/logrotate ${LOGROTATE_CFG_DIR}/$channel\n";
    if ($entries{$target}{selector}) {
        print $fh join( ';', @{ $entries{$target}{selector} } ), " :omfile:\$$channel\n";
    }
    if ($entries{$target}{msgregex}) {
        foreach my $regex (@{ $entries{$target}{msgregex} }) {
            print $fh ":msg, ereregex, \"${regex}\" :omfile:\$$channel\n";
        }
    }
}

# rsyslog seems to support template names up to 127 characters (see
# doNameLine in runtime/conf.c).
#
# So that leaves 114 characters for host:
# - IPv6 addresses are 39 characters max
# - IPV4 addresses are 15 characters max
# - Linux limits host names to 64 (RFC1123 section 2: MUST)
# - POSIX limits host names to 255 characters (RFC1123 section 2: SHOULD).
#
# We'll just use as much of the host specifiacation as
# possible. Should be sufficient in almost all cases (i.e., only very
# long host names will get truncated).
sub get_override_template_name {
    my ( $host, $severity ) = @_;
    return substr("vyatta_FOR_${severity}_${host}", 0, 127);
}

#
# Process the facility override configuration
#
sub add_override_facility_targets {
    my ( $config, $host, $facility_override ) = @_;

    # Needed for print_templates
    $fac_override{$host} = $facility_override;

    my $facilitylist = get_node( $config, 'facility' );

    return unless defined($facilitylist);

    foreach my $facility (keys %{$facilitylist}) {
        my $loglevel = $facilitylist->{$facility}->{'level'};

        $facility = $facmap{$facility} if ( $facmap{$facility} );

        for (my $sev = $SEVERITY_VALS{$loglevel}; $sev >= 0; --$sev) {
            my $target = "\@${host};" . get_override_template_name($host, $sev);
            $entries{$target} = {} unless $entries{$target};
            add_target_selector($facility . '.=' . $SEVERITY_NAMES[$sev], $target);

            # If bind address defined for host, also use it for override target
            if ( defined($src_intf) ) {
                my $src_addr = $host_src_addr{$host};
                $host_src_addr{$target} = $src_addr if defined($src_addr);
            }
        }
    }
}

#
# Print out command to input for log socket and
# rate limiting parameters
#
sub print_rate_limit_settings {
    my ( $out ) = @_;

    if ( defined($rl_interval) ) {
        print $out <<"END";
\$imjournalRateLimitInterval $rl_interval
\$imjournalRateLimitBurst $rl_burst
END
    }
}

#
# Print out socket forwarding confiuration
#
sub print_socket_forward_conf {

    return if upstream_vrf();

    my ( $fh ) = @_;

    get_current_vrfs_list();
    if (@vrf_list) {
        print $fh "module(load=\"omczmq\")\n";
        print $fh "action(\n";
        print $fh "\tname=\"rsyslog_com\"\n";
        print $fh "\ttemplate=\"SystemdUnitTemplate\"\n";
        print $fh "\ttype=\"omczmq\"\n";
        print $fh "\tendpoints=\"\@ipc:///var/run/vyatta/rsyslog/rsyslog.pub\"\n";
        print $fh "\tsocktype=\"PUB\"\n)\n";
    }  
}

sub print_discard_rules {

    return if !@discard_regexs;

    my ( $out ) = @_;

    foreach my $regex (@discard_regexs) {
        print $out ":msg, ereregex, \"${regex}\" stop\n";
    }
}

#
# Print out configured facility override templates
#
sub print_override_templates {
    my ( $fh ) = @_;
    # Use _SYSTEMD_UNIT with SYSLOG_IDENTIFIER so that full unit name is printed,
    # eg: sshd@blue.service - this is structured data from imjournal, so the properties
    # are case-sensitive
    my $fmt = '<%pri%>1 %timestamp:::date-rfc3339% %$!_HOSTNAME% %$!_SYSTEMD_UNIT:1:32% %syslogtag:1:32% %msgid% %structured-data%%msg:::sp-if-no-1st-sp%%msg%';
    foreach my $host ( keys %fac_override ) {
        for (my $sev = 0; $sev < 8; ++$sev) {
            my $prival = $FACILITY_VALS{$fac_override{$host}} | $sev;
            print $fh '$template ' .  get_override_template_name($host, $sev) . ",\"<${prival}>${fmt}\",casesensitive\n";
        }
    }
}

#
# Get a config node
#
sub get_node {
    my ( $config, $tag ) = @_;
    if ( ref($config) eq "HASH" ) {
        return $config->{$tag}
            if ref($config->{$tag}) eq "HASH";
    }
    return;
}

#
# Process the global logging destination configuration
#
sub get_global_logging_config {
    my ( $config ) = @_;

    my $globalcfg = get_node( $config, 'global' );
    read_config( $globalcfg, $MESSAGES )
        if (defined( $globalcfg));
}

#
# process console logging destination configuration
#
sub get_console_logging_config {
    my ( $config ) = @_;

    my $consolecfg = get_node( $config, 'console' );
    read_config( $consolecfg , $CONSOLE )
        if (defined( $consolecfg));
}

#
# Process source interface for remote hosts configuration
#
sub get_src_intf_config {
    my ($config) = @_;

    $src_intf = $config->{'source-interface'};
}

#
# Process remote host logging destination configuration
#
sub get_host_logging_config {
    my ( $config ) = @_;

    my $hostlist = get_node( $config, 'host' );
    if (defined($hostlist)) {
        foreach my $host (keys %{$hostlist}) {
            if ( defined($src_intf) ) {
                my $host_ifaddr = new NetAddr::IP $host;
                my ($host_addr) = Net::IP::ip_splitprefix($host_ifaddr);
                my $src_addr =
                  Net::IP::ip_is_ipv6($host_addr)
                  ? "SRC_IP6ADDR"
                  : "SRC_IPADDR";

                $host_src_addr{$host} = $src_addr;
            }
            my $hostcfg = $hostlist->{$host};
            my $override = $hostcfg->{'facility-override'};
            if (defined($override)) {
                add_override_facility_targets($hostcfg, $host, $override);
            } else {
                read_config( $hostcfg, $host );
            }
        }
    }
}

# 
# process a user defined file logging destination configuration
#
sub get_file_logging_config {
    my ( $config ) = @_;

    my $filelist = get_node( $config, 'file' );
    if (defined($filelist)) {
        foreach my $file (keys %{$filelist}) {
            my $target = '/var/log/user/' . $file;
            read_config( $filelist->{$file}, $target );
        }
    }
}

#
# process a "user" logging destination
#
sub get_user_logging_config {
    my ( $config ) = @_;

    my $userlist = get_node( $config, 'user' );
    if (defined($userlist)) {
        foreach my $user (keys %{$userlist}) {
            my $user_target = $user;
            $user_target = '*' if ($user eq 'all');
            read_config( $userlist->{$user}, ':omusrmsg:'. $user_target );
        }
    }
}

sub get_target_port {
    my ( $host ) = @_;

    my $target = $host;
    my $port = $SYSLOG_PORT;

    # Target examples: 1.1.1.1, 1.1.1.1:514, [1::1], [1::1]:514
    my @hostandport = split( /:([^:\]]+)$/, $target );
    if ( defined( $hostandport[1] ) ) {
        $target = $hostandport[0];
        $port   = $hostandport[1];
    }
    $target =~ s/[\[\]]//g;

    return ($target, $port);
}

#
# Get target and template from facility-override host:
# Host format: @<hostip>;<template>
#
sub get_override_target_template {
    my ( $host ) = @_;

    $host =~ s/^@//g;
    return split( /;/, $host );
}

#
# Return the action statement appropriate for the VRF implementation and source
# address
#
sub get_action {
    my ( $host, $vrf ) = @_;
    my $dev = defined($vrf) ? " Device=\"vrf$vrf\"" : '';
    my $target = $host;

    if (upstream_vrf()) {
        my $port;
        # Use SYSTEMD_UNIT with SYSLOG_INDENTIFIER so that full unit name is printed,
        # eg: sshd@blue.service
        my $template_str = ' Template="SystemdUnitTemplate"';

        if ( $host =~ /^:/ ) {
            # Target is a user terminal of the form :omusrmsg:<user>
            return "\t$target\n";
        } elsif ( $host =~ m/^@/ ) {
            my ( $ohost, $template ) = get_override_target_template($host);
            if ( defined($ohost) ) {
                ( $target, $port ) = get_target_port($ohost);
                $template_str = " Template=\"$template\""
                  if ( defined($template) );
            } else {
                $target = $host;
                $port = $SYSLOG_PORT;
            }
        } else {
            ( $target, $port ) = get_target_port($host);
        }
        if ( defined($vrf) && $target =~ /[a-zA-Z]/ ) {
            my $rconfig = new Vyatta::Config;
            $rconfig->setLevel("routing routing-instance $vrf system");
            my @hosts = $rconfig->listNodes("static-host-mapping host-name");
            my $ip;
            foreach my $host (@hosts) {
                if ( $target eq $host ) {
                    $ip = $rconfig->returnValue(
                        "static-host-mapping host-name $host inet");
                }
            }
            $target = $ip if ( defined($ip) );
        }

        my $addr = $host_src_addr{$host};
        my $addr_str =
          defined($addr) ? " Ipfreebind=\"1\" Address=\"$addr\"" : "";

        my $action =
            "action(Type=\"omfwd\" Protocol=\"udp\" Port=\"$port\""
          . $dev
          . $addr_str
          . $template_str;
        return "\t$action Target=\"$target\")\n";
    } else {
        return "\t\@$target\n";
    }
}
#
# Write out the actual rsyslog configuration file. This file is
# created as a temp file. This function returns 0 if the created
# file is the same as an existing file. It copies the temp file over
# the existing file if it is different and returns 1.
#
sub write_rsyslog_config_file {
    my ( $config_file, $vrf ) = @_;

    my ($out, $tempname) = tempfile($SYSLOG_TMPL, UNLINK => 1)
        or die "Can't create temp file: $!";

    if ( $config_file =~ /\.template$/i ) {
        print $out "# Do not edit, file generated by $0\nSRC_INTF $src_intf\n";
    }

    if ( $config_file eq $SYSLOG_CONF || $config_file eq $SYSLOG_TEMPLATE ) {
        print_rate_limit_settings($out);
        print_socket_forward_conf($out);
        print_discard_rules($out);
        print $out '$IncludeConfig /var/run/rsyslog/vrf/*/rsyslog.d/*.conf',
            "\n\n" if upstream_vrf();
    }

    print_override_templates($out);

    my $files;
    my $size;
    foreach my $target ( keys %entries ) {
        if ($target eq $MESSAGES) {
            $size = get_target_param($target, 'size');
            $files = get_target_param($target, 'files');
            print_outchannel($out, 'global', $target, $size);
            system("/opt/vyatta/sbin/vyatta_update_logrotate.pl $files $size 1") == 0
                or die "Can't genrate global log rotation config: $!";
        } elsif ($target =~ m:^/var/log/user/:) {
            my $file = basename($target);
            $size = get_target_param($target, 'size');
            $files = get_target_param($target, 'files');
            print_outchannel($out, 'file_' . $file, $target, $size);
            system("/opt/vyatta/sbin/vyatta_update_logrotate.pl $file $files $size 1") == 0
                or die "Can't genrate global log rotation config: $!";
        } else {
            if ($entries{$target}{selector}) {
                print $out join( ';', @{ $entries{$target}{selector} } ),
	               get_action( $target, $vrf );
            }
            if ($entries{$target}{msgregex}) {
                foreach my $regex (@{ $entries{$target}{msgregex} }) {
                    print $out ":msg, ereregex, \"${regex}\"",
                        get_action( $target, $vrf );
                }
            }
        }
    }

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
# Write out the actual rsyslog configuration file. If source interface config is
# present, a template file is created, which is used to update the config file
# at the time of config and then due to address updates notified via netplug.
#
sub write_rsyslog_config_files {
    my ( $config_file, $template_file, $vrf ) = @_;
    my $vrf_str = defined($vrf) ? "--vrf=$vrf" : "";
    my $errmsg;
    my $ret = 0;

    if ( defined($src_intf) && %host_src_addr ) {
        write_rsyslog_config_file($template_file, $vrf);
        $errmsg =
qx(/opt/vyatta/sbin/vyatta_syslog_template.pl --src-intf=$src_intf $vrf_str);
        $ret = $? >> 8;
        print "$errmsg" if defined($errmsg) && $errmsg;
    } else {
        $ret = write_rsyslog_config_file($config_file, $vrf);
        unlink $template_file;
    }
    return $ret;
}

#
# Write the base syslog configuration file. This file uses
# the template at the end of this source file. The template
# is modified with the vrf name provided. 
#
sub write_rsyslog_base_config_file {
    my ( $base_config_file, $vrf ) = @_;
    my $vars = {
        vrf => $vrf
    };

    my ($out, $tempname) = tempfile($SYSLOG_TMPL, UNLINK => 1)
        or die "Can't create temp file: $!";

    my $curpos = tell(DATA);

    my $tt = new Template( PRE_COMP => 1 );
    $tt->process( \*DATA, $vars, $tempname);

    seek DATA, $curpos, 0;

    close $out
        or die "Can't output $tempname: $!";

    # Don't need to do anything, save time on boot
    if (  -z $tempname || -e $base_config_file && compare( $base_config_file, $tempname ) == 0 ) {
         unlink($tempname);
         return 0;
    }

    system("cp $tempname $base_config_file") == 0
        or die "Can't copy $tempname to $base_config_file: $!";
    chmod 0644, $base_config_file;

    unlink($tempname);
    return 1;


}

#
# Setup the configuration file for a local
# log destinations
#
sub create_local_rsyslog_config {

    undef %entries;
    undef %fac_override;

    my $config = new Vyatta::Config::Parse("system syslog");
    $config = $config->{'syslog'};

    get_global_logging_config( $config );
    get_console_logging_config( $config );
    get_file_logging_config ( $config );
    get_user_logging_config ( $config );
    get_src_intf_config($config);
    get_host_logging_config ( $config );
    get_rate_limit_parms( $config );
    get_discard_regexs( $config );
    my $ret = write_rsyslog_config_files( $SYSLOG_CONF, $SYSLOG_TEMPLATE );
    system ("service rsyslog restart")
        if ($ret == 1);

}

#
# Create the service environment file to specify the
# the rsyslog conf file location, PID file location,
# and the VRF rdid. This file is used by rsyslog@.service.
#
sub write_service_environment_file {
    my ( $filepath, $vrf ) = @_;

    open(my $fh, '>', $filepath) 
        or die "Could not open syslog service environment file '$filepath'";
    
    my $rdid = "1";
    $rdid = get_vrf_id($vrf)
        if ($vrf_available && $vrf ne 'default');

    print $fh "RSYSLOG_CONF_FILE=\"-f $VRF_CFG_DIR/$vrf/rsyslog.conf\"\n";
    print $fh "RSYSLOG_PID_FILE=\"-i $VRF_CFG_DIR/$vrf/rsyslog.pid\"\n";
    print $fh "RSYSLOG_RDID=\"$rdid\"\n";

    close $fh;
}

#
# Create a vrf rsyslog configuration for a
# host declaration.
# 
sub create_vrf_rsyslog_config {
    my ( $config, $vrf ) = @_;

    undef %entries;
    undef %fac_override;

    my $base_config_file = "$VRF_CFG_DIR/$vrf/rsyslog.conf";
    my $config_path      = "$VRF_CFG_DIR/$vrf/rsyslog.d";
    my $env_file         = "$VRF_CFG_DIR/$vrf/rsyslog.env";
    my $work_path        = "$VRF_CFG_DIR/$vrf/rsyslog_work";
    my $template_path    = "/run/vyatta/rsyslog/vrf/$vrf";

    get_src_intf_config($config);
    get_host_logging_config ( $config );
    my $count = keys %entries;

    return 0
        if ($count == 0);

    make_path( $config_path,   { verbose => 0, mode => oct("0755") } );
    make_path( $template_path, { verbose => 0, mode => oct("0755") } );
    my $ret = write_rsyslog_config_files( "$config_path/vyatta-log.conf",
        "$template_path/vyatta-log.template", $vrf );

    if ( !upstream_vrf() ) {
        write_rsyslog_base_config_file( $base_config_file, $vrf )
            if ( $ret == 1 );

        make_path( $work_path, { verbose => 0, mode => oct("0755") } );
        write_service_environment_file( $env_file, $vrf ) if !upstream_vrf();

        if ( $ret == 1 ) {
            if ( grep( /^$vrf$/, @vrf_list ) ) {
                system("service rsyslog\@$vrf restart");
            } else {
                system("service rsyslog\@$vrf start");
            }
        }
    } elsif ( $ret == 1 ) {
        system("service rsyslog restart");
    }
    remove_vrf_from_list ( $vrf );
}

# 
# Process the vrf-centric rsyslog configuration 
#
sub process_vrf_specific_host_configs {

    my $config = new Vyatta::Config::Parse("routing");
    if ( defined( $config ) ) {
        $config = $config->{'routing'};
        my $vrflist = get_node( $config, 'routing-instance' );
        if (defined($vrflist)) {
            foreach my $vrf (keys %{$vrflist}) {

                my $systemcfg = $vrflist->{$vrf};
                $systemcfg = get_node($systemcfg, 'system');
                next if !defined($systemcfg);
                $systemcfg = get_node($systemcfg, 'syslog');
                next if !defined($systemcfg);
                 
		create_vrf_rsyslog_config($systemcfg, $vrf);
            }
        } 
    }
}

#
# Stop and remove all rsyslog instances in the
# vrf list. They are no longer configured.
#
sub remove_unconfigured_vrf_hosts {

    #
    # Remove all vrfs that are in the vrf list
    #
    for (0..$#vrf_list){
        
       #
       # Stop the associated rsyslog instance
       #
       system ("service rsyslog\@$vrf_list[$_] stop");

       #
       # Remove all the vrf configuration files by removing the
       # vrf tree.
       #
       remove_tree("$VRF_CFG_DIR/$vrf_list[$_]");

    }
    if ( upstream_vrf() && scalar(@vrf_list) ) {
       system ("service rsyslog restart");
    }

}

#
# Get the list of current vrfs with defined rsyslog hosts
#
sub get_current_vrfs_list {

    @vrf_list = glob "$VRF_CFG_DIR/*";
    for (0..$#vrf_list){
        $vrf_list[$_] =~ s/^$VRF_CFG_DIR\///g;
    }    

}

#
# Remove the indicated vrf from the vrf list
#
sub remove_vrf_from_list {
    my ( $vrf ) = @_;

    @vrf_list = grep(!/^$vrf$/, @vrf_list);

}

get_current_vrfs_list();
process_vrf_specific_host_configs();
remove_unconfigured_vrf_hosts();
create_local_rsyslog_config();

exit 1;

__DATA__
#  /run/rsyslog/vrf/[% vrf %]/rsyslog.conf	Configuration file for rsyslog.
#
#			For more information see
#			/usr/share/doc/rsyslog-doc/html/rsyslog_conf.html


#################
#### MODULES ####
#################

module(load="imczmq")
input(
	type="imczmq"
	socktype="SUB"
	topics="<"
	endpoints=">ipc:///var/run/vyatta/rsyslog/rsyslog.pub"
)

#$ModLoad imklog   # provides kernel logging support
#$ModLoad immark  # provides --MARK-- message capability

# provides UDP syslog reception
#$ModLoad imudp
#$UDPServerRun 514

# provides TCP syslog reception
#$ModLoad imtcp
#$InputTCPServerRun 514


###########################
#### GLOBAL DIRECTIVES ####
###########################

# Use high precision timestamp format
$ActionFileDefaultTemplate RSYSLOG_FileFormat

# Filter duplicated messages
$RepeatedMsgReduction on

#
# Set the default permissions for all log files.
#
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022

#
# Where to place spool and state files
#
$WorkDirectory /run/rsyslog/vrf/[% vrf %]/rsyslog_work

#
# Include all config files in /run/rsyslog/vrf/[% vrf %]/rsyslog.d/
#
$IncludeConfig /run/rsyslog/vrf/[% vrf %]/rsyslog.d/*.conf


###############
#### RULES ####
###############



