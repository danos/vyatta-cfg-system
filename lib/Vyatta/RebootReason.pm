# Copyright (c) 2021 AT&T Intellectual Property.
#    All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

package Vyatta::RebootReason;
use strict;
use warnings;
use File::Slurp qw( write_file read_file );
use IPC::Run3;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Configd;

require Exporter;
our @ISA    = qw (Exporter);
our @EXPORT = qw(log_reboot_reason get_reboot_reason save_rr_log_file);

my $LOG_DIR       = "/device-cache";
my $RR_LOG_FILE   = "$LOG_DIR/reboot_reason.log";
my $II_LOG_FILE   = "$LOG_DIR/install_image.log";
my $SAVE_LOG_FILE = "/var/log/vyatta/last_reboot_reason.log";

my @LAST_CMD = ( '/usr/bin/last', '-xFR' );
my @LOG_CMD  = ( 'journalctl',    '-b-1' );

my $POWER_OFF    = 1;
my $WARM_REBOOT  = 2;
my $COLD_REBOOT  = 3;
my $IMAGE_CHANGE = 4;
my $SYSTEM_CRASH = 5;
my $OTHER        = 6;

my $UNKNOWN_REASON = "Other: Unknown reason for reboot";
my $CRASH_UNAVAIL  = "System crash: vmcore and dmesg log not available";

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
    rename( $RR_LOG_FILE, $SAVE_LOG_FILE )
      if ( -e $RR_LOG_FILE );
    return;
}

sub check_image_change {
    my ($running_image) = @_;

    return 0 unless ( -e $II_LOG_FILE );
    my $old_running_image = read_file($II_LOG_FILE);

    my $check = 0;
    if ( $running_image ne $old_running_image ) {
        logit( $RR_LOG_FILE,
"System image change: New image $running_image, old image $old_running_image"
        );
        $check = 1;
    }
    unlink($II_LOG_FILE);
    return $check;
}

sub process_last_output {
    my @lines;
    run3( \@LAST_CMD, undef, \@lines );
    my $reboot = 0;
    foreach my $line (@lines) {
        if ( $line =~ /^reboot/ ) {
            if ( $reboot == 0 ) {
                $reboot = 1;
                next;
            }
            return $SYSTEM_CRASH;
        }
        return $COLD_REBOOT
          if ( $reboot == 1 and $line =~ /^shutdown/ );
    }
    return 0;
}

sub check_reason {
    my ( $rr_type, $rr_reason ) = @_;

    if (   !defined($rr_type)
        || !defined($rr_reason)
        || $rr_type < 1
        || $rr_type > 6 )
    {
        $rr_type   = $OTHER;
        $rr_reason = $UNKNOWN_REASON;
    }
    elsif (defined($rr_type)
        && $rr_type == $SYSTEM_CRASH
        && !defined($rr_reason) )
    {
        $rr_type   = $SYSTEM_CRASH;
        $rr_reason = $CRASH_UNAVAIL;
    }
    return ( $rr_type, $rr_reason );
}

sub get_syscrash_info {
    my $rr_type   = $SYSTEM_CRASH;
    my $rr_reason = $CRASH_UNAVAIL;
    my @lines;
    run3( \@LOG_CMD, undef, \@lines );
    foreach my $line (@lines) {
        if ( $line =~ /kdump-tools: saved vmcore in/ ) {
            my $path = ( split( / /, $line ) )[-1];
            chomp($path);
            $rr_reason = "System crash: vmcore and dmesg log saved in $path";
            last;
        }
    }
    return ( check_reason( $rr_type, $rr_reason ) );
}

sub get_reboot_reason_from_log {
    my $rr_type;
    my $rr_reason;
    if ( check_image_change( get_running_image() ) ) {
        $rr_type = $IMAGE_CHANGE;
    }
    return ( check_reason( $rr_type, $rr_reason ) )
      unless ( -e $RR_LOG_FILE );
    $rr_reason = read_file($RR_LOG_FILE);
    if ( $rr_reason =~ /poweroff:/ ) {
        $rr_type = $POWER_OFF;
    }
    elsif ( $rr_reason =~ /reboot:/ ) {
        $rr_type = $COLD_REBOOT;
    }
    return ( check_reason( $rr_type, $rr_reason ) );
}

sub get_reboot_reason {
    my $rr_type;
    my $rr_reason;
    if ( process_last_output() == $SYSTEM_CRASH ) {
        ( $rr_type, $rr_reason ) = get_syscrash_info();
    }
    else {
        ( $rr_type, $rr_reason ) = get_reboot_reason_from_log();
    }
    ( $rr_type, $rr_reason ) = check_reason( $rr_type, $rr_reason );
    logit( $RR_LOG_FILE, $rr_reason );
    return ( $rr_type, $rr_reason );
}

1;
