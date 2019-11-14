#!/usr/bin/perl
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2015-2016 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use Getopt::Long;
use POSIX qw(strftime);

#Print a packages license usiang less
sub _less_pkg_license {
    my $pkg      = shift;
    my $filename = "/usr/share/doc/$pkg/copyright";
    system("less $filename");
}

sub _write_licenses_to_file {
    system("dpkg --get-selections | awk '{ print \$1 }' > /tmp/pkgs");
    my $license_dest = shift;
    system("truncate --size=0 $license_dest");

    open( my $fh, '<:encoding(UTF-8)', "/tmp/pkgs" )
      or die "Could not open file '/tmp/pkgs' $!";

    while ( my $pkg = <$fh> ) {
        chomp $pkg;
        if ( ":amd64" eq substr( $pkg, -6, 6 ) ) {
            $pkg = substr( $pkg, 0, -6 );
        }
        open( my $d, ">>", "$license_dest" )
          or die "Could not open destination file\n";
        if ( open( my $s, "<", "/usr/share/doc/$pkg/copyright" ) ) {
            print {$d}
"\n\nv=================== package: $pkg ===================v\n\n\n";
            while ( my $tmp = <$s> ) {
                chomp $tmp;
                print {$d} $tmp, $/;
            }
        }
        else {
            print "No license info for package $pkg\n";
        }
    }
    system("rm -rf /tmp/pkgs &> /dev/null");
    print "Wrote license info to $license_dest\n";
}

sub _write_licenses_to_stdout {
    system("dpkg --get-selections | awk '{ print \$1 }' > /tmp/pkgs");

    open( my $fh, '<:encoding(UTF-8)', "/tmp/pkgs" )
      or die "Could not open file '/tmp/pkgs' $!";

    while ( my $pkg = <$fh> ) {
        chomp $pkg;
        if ( ":amd64" eq substr( $pkg, -6, 6 ) ) {
            $pkg = substr( $pkg, 0, -6 );
        }
        system(
"echo -e \"\n\nv=================== package: $pkg ===================v\n\n\n\""
        );
        system("cat /usr/share/doc/$pkg/copyright");
    }
    system("rm -rf /tmp/pkgs &> /dev/null");
}

sub _list_packages {
	system("dpkg -l | cut -d' ' -f3 | tail -n +6");
}

my ( $print_pkg, $write_licenses_file, $write_licenses_stdout, $list_pkgs );

GetOptions(
    "print-pkg=s"           => \$print_pkg,
    "write-licenses-file=s" => \$write_licenses_file,
    "write-licenses-stdout" => \$write_licenses_stdout,
    "list-packages"         => \$list_pkgs,
);

_less_pkg_license($print_pkg)                 if defined($print_pkg);
_write_licenses_to_file($write_licenses_file) if defined($write_licenses_file);
_write_licenses_to_stdout($write_licenses_stdout)
  if defined($write_licenses_stdout);
_list_packages()	if defined($list_pkgs);
