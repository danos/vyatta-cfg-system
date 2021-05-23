#!/usr/bin/env python3

# Copyright (c) 2021, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

from argparse import ArgumentParser
from vplaned import Controller
import sys

arg_parser = ArgumentParser()
arg_parser.add_argument('--af', required=True)

args = arg_parser.parse_args()

if args.af != 'v4' and args.af != 'v6':
    print("No address family specified\n")
    sys.exit(1)

with Controller() as controller:
    for dp in controller.get_dataplanes():
        with dp:
            data = dp.string_command("icmprl clear {}".format(args.af))
