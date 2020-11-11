#! /usr/bin/perl

# **** License ****
#
# Copyright (c) 2019-2020, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2016 Brocade Communications Systems, Inc.
#    All Rights Reserved.
#
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****

# Update console configuration in /etc/inittab and grub
# based on Vyatta configuration

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;
use File::Compare;
use File::Copy;
use File::Temp qw/ tempfile /;
use File::Path qw(make_path remove_tree);
use IPC::Run3;

my $BASE_ENVIRONMENT_DIR = "/etc";

die "$0 expects no arguments\n" if (@ARGV);

# if file is unchanged, do nothing and return false
# otherwise update to new version
sub update {
    my ( $old, $new ) = @_;

    if ( compare( $old, $new ) != 0 ) {
        move( $new, $old )
          or die "Can't move $new to $old";
        return 1;
    }
    else {
        unlink($new);
        return;
    }
}

# This function creates an environment file used by the overridden
# serial-getty@.service file. This environment file defines
# BAUD_RATE_LIST which contains the ordered baud rate list with
# the configured baud rate at the beginning. The function
# returns 1 if the environment file is new or different from the last
# environment file. It returns 0 if the new environment file is the same
# as the current environment file.
sub create_environment_file {
    my ( $dev_type, $device, $speed ) = @_;

    my $environment_dir = "$BASE_ENVIRONMENT_DIR/$dev_type-getty/$device";
    make_path( $environment_dir, { verbose => 0, mode => oct("0755") } );

    my $environment_file = "$environment_dir/$dev_type-getty.env";
    my $template         = "$environment_dir/$dev_type-getty.env.XXXXXX";

    my ( $out, $tempname ) = tempfile($template)
      or die "Can't create temp file: $!";

    chmod 0644, $tempname;

    print $out <<"END";
BAUD_RATE_LIST=$speed
END

    close $out
      or die "Can't output $tempname: $!";

    if ( -e $environment_file && compare( $environment_file, $tempname ) == 0 )
    {
        unlink($tempname);
        return 0;
    }

    rename $tempname, $environment_file;
    return 1;
}

my $INITTAB = "/etc/inittab";
my $TMPTAB  = "/tmp/inittab.$$";

sub get_current_getty_units {
    my ($type) = @_;
    my $cmd;
    open( $cmd, '-|',
"systemctl list-units --no-legend --full --plain -t service $type-getty*"
    ) or die "$!\n";
    my $get_unit = sub {
        my ($line) = @_;
        my @fields = split( / /, $line );
        return $fields[0];
    };
    return map { $get_unit->($_) => 1 } <$cmd>;
}

sub get_config_getty_units {
    my $config   = new Vyatta::Config("system console device");
    my $get_unit = sub {
        my ($tty) = @_;
        my $tty_unit = "serial-getty@" . $tty . ".service";
        $tty_unit = "modem-getty@" . $tty . ".service"
          if ( $config->exists("$tty modem") );
        return $tty_unit;
    };
    return map { $get_unit->($_) => 1; } $config->listNodes();
}

sub get_cmdline_getty_units {
    my $fh;
    open( $fh, "<", "/proc/cmdline" ) or return;
    my $get_unit = sub {
        my ($elem) = @_;
        my $console;
        $console = "serial-getty\@" . $1 . ".service"
          if $elem =~ /console=(tty(USB|S)*[0-9]+)[,]*/;
        return $console;
    };
    return
      map { $get_unit->($_) => 1; } grep { /console=.*/ } split( " ", <$fh> );
}

sub getty_is_running {
    my ( $getty, $cur_gettys, $cur_modem_gettys ) = @_;
    return 1
      if ( $getty =~ /serial-getty@.*/ )
      && exists( $cur_gettys->{$getty} );
    return 1
      if ( $getty =~ /modem-getty@.*/ )
      && exists( $cur_modem_gettys->{$getty} );
    return;
}

sub get_getty_type {
    my ($getty) = @_;
    return "modem"
      if ( $getty =~ /modem-getty@.*/ );
    return "serial";
}

sub get_device_name {
    my ($getty) = @_;
    my ($val)   = $getty =~ /.*-getty\@(.*).service/;
    return $val;
}

sub update_getty {
    my ( $getty, $cur_gettys, $cur_modem_gettys, $config ) = @_;
    my $device = get_device_name($getty);
    my $speed  = $config->returnValue("$device speed");
    $speed = "115200"
      if !defined($speed);
    my $dev_type = get_getty_type($device);
    my $new_environment = create_environment_file( $dev_type, $device, $speed );
    my $running = getty_is_running( $getty, $cur_gettys, $cur_modem_gettys );
    return if ( $running && !$new_environment );
    my @cmd = ("systemctl", "--no-block", "restart",
               "$dev_type-getty\@$device.service");
    run3( \@cmd, \undef, undef, undef );
}

sub update_systemd {
    my $config           = new Vyatta::Config("system console device");
    my %cur_gettys       = get_current_getty_units("serial");
    my %cur_modem_gettys = get_current_getty_units("modem");
    my %config_gettys    = get_config_getty_units();
    my %cmdline_gettys   = get_cmdline_getty_units();

    for my $tty_unit ( keys(%config_gettys), keys(%cmdline_gettys) ) {
        update_getty( $tty_unit, \%cur_gettys, \%cur_modem_gettys, $config );
    }

    for my $tty_unit ( keys(%cur_gettys), keys(%cur_modem_gettys) ) {

        next if exists( $config_gettys{$tty_unit} );
        next if exists( $cmdline_gettys{$tty_unit} );

        # stop the unconfigured device
        my @cmd = ("systemctl", "--no-block", "stop", $tty_unit);
        run3( \@cmd, \undef, undef, undef );

        # remove the environment file
        my ($dev_type) = $tty_unit =~ m/^(.*)-/;
        my ($device)   = $tty_unit =~ m/\@(.*)\./;
        remove_tree("$BASE_ENVIRONMENT_DIR/$dev_type-getty/$device");
    }
    return;
}

sub update_inittab {
    $comm = read_file('/proc/1/comm');
    return update_systemd() if ($comm and ($comm =~ /systemd/));

    open( my $inittab, '<', $INITTAB )
      or die "Can't open $INITTAB: $!";

    open( my $tmp, '>', $TMPTAB )
      or die "Can't open $TMPTAB: $!";

    # Clone original inittab but remove all references to serial lines
    print {$tmp} grep { !/^T|^# Vyatta/ } <$inittab>;
    close $inittab;

    my $config = new Vyatta::Config;
    $config->setLevel("system console device");

    print {$tmp} "# Vyatta console configuration (do not modify)\n";

    my $id = 0;
    foreach my $tty ( $config->listNodes() ) {
        my $speed = $config->returnValue("$tty speed");
        $speed = 9600 unless $speed;

        printf {$tmp} "T%d:23:respawn:", $id;
        if ( $config->exists("$tty modem") ) {
            printf {$tmp} "/sbin/mgetty -x0 -s %d %s\n", $speed, $tty;
        }
        else {
            printf {$tmp} "/sbin/getty -L %s %d vt100\n", $tty, $speed;
        }

        # id field is limited to 4 characters
        if ( ++$id >= 1000 ) {
            warn "Ignoring $tty only 1000 serial devices supported\n";
            last;
        }
    }
    close $tmp;

    if ( update( $INITTAB, $TMPTAB ) ) {

        # This is same as telinit q - it tells init to re-examine inittab
        kill 1, 1;
    }
}

my $GRUBCFG = "/boot/grub/grub.cfg";
my $GRUBTMP = "/tmp/grub.cfg.$$";

sub update_grub_env {
    my $config  = new Vyatta::Config("system console");
    my $console = $config->returnValue("serial-boot-console");

    return set_boot_console("tty0") unless defined($console);

    my $speed = $config->returnValue("device $console speed");
    my $unit;
    $unit = $1 if ( $console =~ /ttyS([0-3])/ );
    return set_boot_console( $console, $unit, $speed );
}

sub set_boot_console {
    my ( $console, $unit, $speed ) = @_;
    my @cmd = ();

    return unless ( -w '/boot/grub/grubenv' );

    @cmd = ("grub-editenv", "-", "set", "boot_console=$console");
    run3( \@cmd, \undef, undef, undef );
    if ( defined $unit ) {
        @cmd = ("grub-editenv", "-", "set", "serial_unit=$unit");
        run3( \@cmd, \undef, undef, undef );
    }
    else {
        @cmd = ("grub-editenv", "-", "unset", "serial_unit");
        run3( \@cmd, \undef, undef, undef );
    }
    if ( defined $speed ) {
        @cmd = ("grub-editenv", "-", "set", "serial_speed=$speed");
        run3( \@cmd, \undef, undef, undef );
    }
    else {
        @cmd = ("grub-editenv", "-", "unset", "serial_speed");
        run3( \@cmd, \undef, undef, undef );
    }
}

update_inittab;
update_grub_env;

exit 0;

