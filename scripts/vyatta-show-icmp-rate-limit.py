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

print("{:<15} {:<10} {:<20} {:10}".format(
    "ICMP Type", "Limit", "Sent", "Dropped"));
print("{:>70}".format("(1 min   3 min   5 min   total)"));
with Controller() as controller:
    for dp in controller.get_dataplanes():
        with dp:
            data = dp.json_command("icmprl show {}".format(args.af))
            for rl in data['icmp-ratelimit']:
                for type in rl:
                    stats = rl[type]
                    print("{:<15} {:<10} {:<12} {:<7} {:<7} {:<7} {:<7}" .format(
                        type, stats['limit'], stats['sent'],
                        stats['1min_drop'], stats['3min_drop'], stats['5min_drop'], stats['dropped']))

