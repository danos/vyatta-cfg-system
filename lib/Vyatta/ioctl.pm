# Author: John Southworth <john.southworth@vyatta.com>
# Date: 2012
# Description: vyatta ioctl functions

# **** License ****
# Copyright (c) 2018-2021 AT&T Intellectual Property
# All rights reserved.
#
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
# **** End License ****

package Vyatta::ioctl;

use strict;
use warnings;
use Socket;

{
    local $^W = 0;
    require 'sys/ioctl.ph'; ## no critic
}

our @EXPORT = qw(get_terminal_size);
use base qw(Exporter);

# returns (rows, columns) for terminal size;
sub get_terminal_size {

    # undefined if not terminal attached
    my $TTY;
    if ( defined $ENV{'vyatta_origin_tty'} ) {
        open( $TTY, '>', $ENV{'vyatta_origin_tty'} )
          or return;
    } else {
        open( $TTY, '>', '/dev/tty' )
          or return;
    }

    my $winsize = '';

    # undefined if output not going to terminal
    return unless ( ioctl( $TTY, &TIOCGWINSZ, $winsize ) );
    close($TTY);

    my ( $rows, $cols, undef, undef ) = unpack( 'S4', $winsize );
    return ( $rows, $cols );
}

1;
