# Module: File.pm
# File manipulation functions

# **** License ****
# Copyright (c) 2019-2021, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
# **** End License ****

package Vyatta::File;
use strict;
use warnings;

our @EXPORT = qw(touch mkdir_p rm_rf check_home);
our @EXPORT_OK = qw(show_error);
use base qw(Exporter);

use Fcntl;
use File::Path qw(make_path remove_tree);
use File::Slurp qw(read_file);

# Change file time stamps
# if file does not exist, it is created empty
sub touch {
    my $file = shift;
    my $t = time;

    sysopen (my $f, $file, O_RDWR|O_CREAT)
	or die "Can't touch $file: $!";
    close $f;
    utime $t, $t, $file;
}

# like mkdir -p
# Wrapper of File::Path:make_tree
sub mkdir_p {
    my $path = shift;
    my $err;

    make_path($path, { error => \$err } );

    return @$err;
}

# like rm -rf
# returns an array of errors if any (see File::Path)
sub rm_rf {
    my $path = shift;
    my $err;

    remove_tree($path,  { error => \$err } );

    return @$err;
}

sub show_error {
    for my $diag (@_) {
	my ($f, $msg) = %$diag;
	warn "$f: $msg\n";
    }
}

sub check_home {
    my ($file) = @_;
    my $uid = read_file('/proc/self/loginuid');
    chomp $uid;
    my $home;
    if ($uid) {
        my @pwe = getpwuid($uid);
        $home = $pwe[7] if ( scalar(@pwe) >= 8 );
    }
    return unless defined($home) and length($home) > 1;
    return substr( $file, 0, length($home) ) eq $home;
}

1;
