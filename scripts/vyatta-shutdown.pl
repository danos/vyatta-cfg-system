#!/usr/bin/perl
#
# Module: vyatta-shutdown.pl
#
# **** License ****
#
# Copyright (c) 2019-2021, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013, 2015 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Paul Aitken
# Date: January 2015
# Description: Script to poweroff or reboot, or schedule a poweroff or reboot.
#              NB "shutdown" is a generic term for poweroff or reboot.
#
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Getopt::Long;
use POSIX;
use IO::Prompt;
use Sys::Syslog qw(:standard :macros);
use IPC::Run3;
use File::Slurp qw( write_file );
use JSON;
use Vyatta::RebootReason;

use strict;
use warnings;


#
# Files where poweroff and reboot job info is kept.
#
my $poweroff_job_file = '/var/run/poweroff.job';
my $reboot_job_file = '/var/run/reboot.job';


#
# Silently cancel any pending poweroff or reboot.
#
# Return 0 on success, 1 on failure.
#
sub cancel_shutdown {
    my ($login, $action, $time) = @_;

    my $job_file = $action eq "poweroff" ? $poweroff_job_file : $reboot_job_file;

    # Ensure job file exists and is readable.
    if ( -z "$job_file" || ! -e "$job_file" || ! -f "$job_file" || ! -r "$job_file") {
        return 1;
    }

    open my $file, '<', $job_file or die "cannot open $job_file: $!";
    my $job = <$file>;
    close ($file);

    chomp $job;
    die "Unable to 'atrm $job'"
      unless run3( ["atrm", $job], \undef, \undef, \undef );
    unlink("$job_file")
        or print "Warning: failed to delete $job_file\n";
    syslog("warning", "Shutdown scheduled for [$time] - CANCELED by $login");

    return 0;
}


#
# Parse 'at' output.
#
# Return 1 if error, else return (0, job, time).
#
sub parse_at_output {
    my @lines = @_;

    foreach my $line (@lines) {
        if ($line =~ /Problem/) {
            return (1, '', '');
        } elsif ($line =~ /job (\d+) at (.*)$/) {
            return (0, $1, $2);
        }
    }
    return (1, '', '');
}


#
# Is there a pending poweroff or reboot according to the specified job file?
#
# Return (1, time) if a job exists in the 'at' queue, else return 0.
#
sub is_shutdown_pending_in {
    my $job_file = shift;

    # Ensure job file exists and is readable.
    if ( -z "$job_file" || ! -e "$job_file" || ! -f "$job_file" || ! -r "$job_file") {
        return (0, '');
    }

    my $job = `cat $job_file`;
    chomp $job;

    my $line = `atq $job`;
    if ($line =~ /\d+\s+(.*)\sa root$/) {
        return (1, $1);
    } else {
        return (0, '');
    }
}


#
# Is there a pending poweroff or reboot?
#
# No input args.
# return(1, type, time) if a shutdown is pending, else return 0.
#
sub a_shutdown_is_pending {
    my ($poweroff, $ptime) = is_shutdown_pending_in($poweroff_job_file);
    if ($poweroff) {
        return (1, "poweroff", $ptime);
    }

    my ($reboot, $rtime) = is_shutdown_pending_in($reboot_job_file);
    if ($reboot) {
        return (1, "reboot", $rtime);
    }

    return (0, '', '');
}


#
# Immediate poweroff.
#
sub poweroff_now {
    my $login = shift;
    system("wall The system is going down for system halt\n");
    syslog("warning", "Poweroff now requested by $login");
    log_reboot_reason("CLI poweroff: System was powered off by user $login");
    exec("/sbin/poweroff");
}


#
# Immediate reboot.
#
sub reboot_now {
    my $login = shift;
    system("wall The system is going down for reboot\n");
    syslog("warning", "Reboot now requested by $login");
    log_reboot_reason("CLI reboot: System was rebooted by user $login");
    exec("/sbin/reboot");
}


#
# Poweroff or reboot now.
#
sub do_shutdown_now {
    my ($login, $action) = @_;

    my %actions = ( poweroff    => \&poweroff_now,
                    poweroff_at => \&poweroff_now,
                    reboot      => \&reboot_now,
                    reboot_at   => \&reboot_now,
                  );

    if ( (!defined $action) || (!exists $actions{$action}) ) {
        die "no action specified";
    }

    # Cancel any pending shutdown.
    my ($rc, $type, $time) = a_shutdown_is_pending();
    if ($rc) {
        cancel_shutdown($login, "poweroff", $time);
        cancel_shutdown($login, "reboot", $time);
    }

    # Do the specified shutdown.
    $actions{$action}->($login);

    # We should never get here because the called functions never return
    # -unless we're testing.
    exit 222;
}


#
# Poweroff or reboot at a later time.
#
# Return 0 if a shutdown has been scheduled, else return 1.
#
sub do_shutdown_at {
    my ($login, $action, $at_time, $now) = @_;

    if ( defined $now || (! defined $at_time) || (defined $at_time && "$at_time" eq "now") ) {
        # Immediate shutdown.
        do_shutdown_now($login, $action, $at_time, $now);
    }

    my ($rc, $type, $stime) = a_shutdown_is_pending();
    if ($rc) {
        # A scheduled shutdown trumps a new request.
        print ucfirst ($type), " already scheduled for [$stime]\n";
        return 1;
    }

    if (! -f '/usr/bin/at') {
        die "Package [at] not installed";
    }

    if (! defined $at_time) {
        die "no at_time specified";
    }

    # Check if the time format is valid, then remove that job.
    my @lines = `echo true | at $at_time 2>&1`;
    my ($err, $job, $time) = parse_at_output(@lines);
    if ($err) {
        print "Invalid time format [$at_time]\n";
        return 1;
    }
    die "Unable to 'atrm $job'"
      unless run3( ["atrm", $job], \undef, \undef, \undef );

    $action =~ /(.*)_at/; $action = $1;

    print "\n", ucfirst($action), " scheduled for $time\n\n";
    if (!defined($ENV{VYATTA_PROCESS_CLIENT}) || $ENV{VYATTA_PROCESS_CLIENT} ne 'gui2_rest') {
        if (! prompt("Proceed with $action schedule? [confirm] ", -y1d=>"y")) {
            print ucfirst($action), " canceled\n";
            return 1;
        }
    }

    # Schedule the 'at' job.
    @lines = `echo /sbin/$action | at $at_time 2>&1`;
    ($err, $job, $time) = parse_at_output(@lines);
    if ($err) {
        print "Error: unable to schedule $action\n";
        return 1;
    }

    # Save job file.
    my $job_file = $action eq "poweroff" ? $poweroff_job_file : $reboot_job_file;
    die ucfirst($action), " scheduled, but unable to write to $job_file"
      unless write_file($job_file, $job) == 1;

    print "\n".ucfirst($action)." scheduled for $time\n";
    syslog("warning", ucfirst($action)." scheduled for [$time] by $login");
    log_reboot_reason("Scheduled CLI $action: System $action was scheduled at $time by $login");

    return 0;
}


#
# Immediate poweroff or reboot.
#
# Return 1 on error, else return 0.
#
sub do_shutdown {
    my ($login, $action, $at_time, $now) = @_;

    if ( (defined $now) || (defined $at_time && "$at_time" eq "now") ) {
        # Immediate shutdown trumps any scheduled shutdown.
        do_shutdown_now($login, $action);
    }

    my ($rc, $type, $stime) = a_shutdown_is_pending();
    if ($rc) {
        # A scheduled shutdown trumps a new request.
        print ucfirst ($type), " already scheduled for [$stime]\n";
        return 1;
    }

    if (defined($ENV{VYATTA_PROCESS_CLIENT} && $ENV{VYATTA_PROCESS_CLIENT} eq 'gui2_rest') ||
        prompt("Proceed with $action? (Yes/No) [No] ", -yn1d=>"n")) {
            do_shutdown_at($login, $action, $at_time, $now);
    } else {
        print ucfirst($action), " canceled\n";
        return 1;
    }
}


#
# Cancel a poweroff or reboot.
#
# Return 0 if the shutdown was cancelled, else return 1.
#
sub do_shutdown_cancel {
    my ($login, $action, $at_time) = @_;

    my ($rc, $type, $time) = a_shutdown_is_pending();

    $action =~ /(.*)_cancel/; $action = $1;

    if (!cancel_shutdown($login, $action, $time)) {
        print ucfirst($1), " canceled\n";
        return 0;
    } else {
        print "No $action to cancel\n";
        return 1;
    }
}


#
# Show poweroff or reboot.
#
# Return 0 if the requested action can be shown, else 1.
#
sub do_shutdown_show {
    my ($login, $action) = @_;

    my ($rc, $type, $time) = a_shutdown_is_pending();

    $action =~ /(.*)_show/; $action = $1;

    if ($rc) {
        if ( "$action" eq "$type" ) {
            $rc = 0; # Specified action is pending.
        } else {
            print "No $action pending\n";
        }
        print ucfirst($type), " scheduled for [$time]\n";
        return $rc;
    } else {
        print "No ", $action, " currently scheduled\n";
        return 1;
    }
}

sub encode_json_output {
    my $output = shift;
    print encode_json( { 'vyatta-system-reboot-v1:msg' => $output } );
}

#
# Reboot system handler for reboot, reboot now
# and reboot hardware.
#
sub do_reboot {
    my ($login, $reboot_type) = @_;
    my ($output, $err);

    if ($reboot_type eq "now") {
        $output = "The system is going down for reboot\n";
        encode_json_output($output);
        syslog("warning", "Reboot now requested by $login");
        log_reboot_reason("CLI reboot: System was rebooted by user $login");
        exec("/sbin/reboot");
    } elsif ($reboot_type eq "hardware") {
        syslog("warning", "All hardware systems reboot requested by $login");
        log_reboot_reason("CLI reboot: All hardware systems reboot requested by user $login");
        my @cmd = ("/usr/bin/ipmitool", "raw", "0x3c", "0x24", "0x01", "0x00");
        run3 (\@cmd, undef, \$output, \$err);
        if ($? != 0) {
            syslog("warning", "Reboot hardware operation failed: $err");
            die("Operation is not supported by the firmware!\n");
        }
        $output = "All hardware systems will be rebooted\n";
        encode_json_output($output);
    }
    exit 0;
}

#
# Decode JSON input from RPC/Netconf.
#
sub parse_json_input {
    my $login = shift;

    my $input = join( '', <STDIN> );
    my $rpc = decode_json($input);
    my $reboot_type = $rpc->{"type"};
    do_reboot($login, $reboot_type);
}

#
# main
#
my ($action, $at_time, $now);
GetOptions("action=s"   => \$action,
           "at_time=s"  => \$at_time,
           "now!"       => \$now,
);

my %actions = ( poweroff        => \&do_shutdown,
                reboot          => \&do_shutdown,
                poweroff_at     => \&do_shutdown_at,
                reboot_at       => \&do_shutdown_at,
                poweroff_cancel => \&do_shutdown_cancel,
                reboot_cancel   => \&do_shutdown_cancel,
                poweroff_show   => \&do_shutdown_show,
                reboot_show     => \&do_shutdown_show,
                parse_input     => \&parse_json_input,
              );

#
# Sanity checks.
#
if (! defined $action) {
    die "no action specified";
}

exists $actions{$action} or
    die "unrecognised action '$action'";

if ( (defined $at_time) && (defined $now) ) {
    die "'--at_time' and '--now' are mutually exclusive";
}

#
# OK, we're good to go.
#
openlog($0, "", LOG_USER);
my $login = getlogin() || getpwuid($<) || "unknown";

my $rc = $actions{$action}->($login, $action, $at_time, $now);

closelog();
exit $rc;
