# Copyright (c) 2021 AT&T Intellectual Property.
#    All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package Vyatta::RebootReason;
use strict;
use warnings;
use File::Slurp qw( write_file read_file );
use IPC::Run3;
use File::Copy;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Configd;

require Exporter;
our @ISA = qw (Exporter);
our @EXPORT =
  qw(log_reboot_reason get_reboot_reason save_rr_log_file get_last_reboot_reason);

my $LOG_DIR       = "/device-cache";
my $RR_LOG_FILE   = "$LOG_DIR/reboot_reason.log";
my $II_LOG_FILE   = "$LOG_DIR/install_image.log";
my $SAVE_LOG_FILE = "/var/log/vyatta/last_reboot_reason.log";

my @LAST_CMD = ( 'last', '-Fxn2', 'shutdown', 'reboot' );
my @LOG_VYATTA_CMD =
  ( 'journalctl', '-b-1', '-t/opt/vyatta/bin/vyatta-shutdown.pl' );
my @LOG_LOGIN_CMD = ( 'journalctl', '-b-1', '-tsystemd-logind' );

my $POWER_OFF    = 1;
my $WARM_REBOOT  = 2;
my $COLD_REBOOT  = 3;
my $IMAGE_CHANGE = 4;
my $SYSTEM_CRASH = 5;
my $OTHER        = 6;

my $UNKNOWN_REASON = "Other: Unknown reason for reboot";
my $UNGRACEFUL_SHUTDOWN =
  "Other: Reboot after ungraceful shutdown, force reset/poweroff, or crash";
my $CRASH_UNAVAIL = "System crash: vmcore and dmesg log not available";
my $POWERKEY      = "Power off: Power key pressed, system was powered down";

sub logit {
    my ( $file, $msg ) = @_;

    unlink($file);
    write_file( $file, $msg );
    return;
}

sub get_running_image {
    my $client = Vyatta::Configd::Client->new();
    my $tree   = $client->tree_get_full_hash("system-image");
    return ( $tree->{'system-image'}->{'running-image'} );
}

sub log_running_image {
    return unless ( -d $LOG_DIR );
    my $running_image = get_running_image();
    logit( $II_LOG_FILE, "$running_image" );
    return;
}

sub log_reboot_reason {
    my ($msg) = @_;

    log_running_image();
    return unless ( -d $LOG_DIR );
    logit( $RR_LOG_FILE, $msg );
    return;
}

sub save_rr_log_file {
    move( $RR_LOG_FILE, $SAVE_LOG_FILE )
      if ( -e $RR_LOG_FILE );
    return;
}

sub check_image_change {
    my ($running_image) = @_;

    my $rr_type   = $OTHER;
    my $rr_reason = $UNKNOWN_REASON;
    return ( $rr_type, $rr_reason ) unless ($running_image);
    return ( $rr_type, $rr_reason ) unless ( -e $II_LOG_FILE );
    my $old_running_image = read_file($II_LOG_FILE);

    if ( $running_image ne $old_running_image ) {
        $rr_reason =
"System image change: New image $running_image, old image $old_running_image";
        return ( $IMAGE_CHANGE, $rr_reason );
    }
    unlink($II_LOG_FILE);
    return ( $rr_type, $rr_reason );
}

sub check_system_crash {
    my $client = Vyatta::Configd::Client->new();
    my $tree   = $client->tree_get_full_hash("system kernel-crash-dump");

    if ( $tree->{'kernel-crash-dump'}->{'enable'} ) {
        my $status = $tree->{'kernel-crash-dump'}->{'status'};
        if ( $status->{'rebooted-after-system-crash'} ) {
            my $rr_type = $SYSTEM_CRASH;
            foreach my $file ( @{ $status->{'crash-dump-files'} } ) {
                if ( $file->{'index'} == 0 ) {
                    my $rr_reason =
"System crash: vmcore and dmesg log saved in $file->{'path'}";
                    return ( $rr_type, $rr_reason );
                }
            }
            return ( $rr_type, $CRASH_UNAVAIL );
        }
    }
    return ( $OTHER, $UNKNOWN_REASON );
}

sub check_hw_reboot {
    my @lines;
    my $err;
    run3( \@LOG_VYATTA_CMD, undef, \@lines, \$err );
    foreach my $line (@lines) {
        chomp($line);
        if ( $line =~ /vyatta-shutdown.pl/ ) {
            my $reason = ( split( /:/, $line ) )[-1];
            if ( $reason =~ /^ All hardware systems reboot/ ) {
                my $rr_reason = "CLI hardware reboot:$reason";
                return ( $COLD_REBOOT, $rr_reason );
            }
        }
    }
    return ( $OTHER, $UNKNOWN_REASON );
}

sub is_graceful_shutdown {
    my @lines;
    my $err;
    my $reboot = 0;
    run3( \@LAST_CMD, undef, \@lines, \$err );
    foreach my $line (@lines) {
        chomp($line);
        $reboot = 1 if ( $line =~ /^reboot/ );
        return 1 if ( $reboot == 1 && $line =~ /^shutdown/ );
    }
    return 0;
}

sub check_poweroff {
    if ( is_graceful_shutdown() ) {
        my @lines;
        my $err;
        run3( \@LOG_LOGIN_CMD, undef, \@lines, \$err );
        foreach my $line (@lines) {
            if ( $line =~ /System is powering down.$/ ) {
                return ( $POWER_OFF, $POWERKEY );
            }
        }
    }
    return ( $OTHER, $UNKNOWN_REASON );
}

sub check_rr_log {
    my $rr_type   = $OTHER;
    my $rr_reason = $UNKNOWN_REASON;
    return ( $rr_type, $rr_reason ) unless ( -e $RR_LOG_FILE );
    $rr_reason = read_file($RR_LOG_FILE);
    if ( $rr_reason =~ /poweroff:/ ) {
        $rr_type = $POWER_OFF;
    } elsif ( $rr_reason =~ /reboot:/ ) {
        $rr_type = $COLD_REBOOT;
    }
    return ( $rr_type, $rr_reason );
}

sub get_reboot_reason {
    my ( $rr_type, $rr_reason ) = check_image_change( get_running_image() );

    if ( $rr_type eq $OTHER ) {
        ( $rr_type, $rr_reason ) = check_system_crash();
        if ( $rr_type eq $OTHER ) {
            ( $rr_type, $rr_reason ) = check_hw_reboot();
            if ( $rr_type eq $OTHER ) {
                ( $rr_type, $rr_reason ) = check_rr_log();
                if ( $rr_type eq $OTHER ) {
                    ( $rr_type, $rr_reason ) = check_poweroff();
                    if ( $rr_type eq $OTHER and !is_graceful_shutdown ) {
                        $rr_type   = $OTHER;
                        $rr_reason = $UNGRACEFUL_SHUTDOWN;
                    }
                }
            }
        }
    }
    logit( $RR_LOG_FILE, $rr_reason );
    return ( $rr_type, $rr_reason );
}

sub get_last_reboot_reason {
    my $rr;
    $rr = read_file($SAVE_LOG_FILE) if ( -e $SAVE_LOG_FILE );
    $rr =~ s/:/ -/g if defined($rr);
    return ( defined($rr) ? $rr : "" );
}

1;
