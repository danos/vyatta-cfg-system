#!/usr/bin/env python3

# Copyright (c) 2021, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

from argparse import ArgumentParser
from vplaned import Controller
from vyatta import configd
import sys

arg_parser = ArgumentParser()
arg_parser.add_argument('--af', required=True)

args = arg_parser.parse_args()

cfg = configd.Client()

if args.af == 'v4':
    node = "system ip icmp rate-limit state"
elif args.af == 'v6':
    node = "system ipv6 icmp rate-limit state"
else:
    print("Invalid address family specified\n")
    sys.exit(1)

try:
    data = cfg.tree_get_full_dict(node)
    data = data['state']
except:
    sys.exit(1)

print("{:<23} {:<5} {:<10} {:10}".format(
    "ICMP Type", "Limit", "Sent", "Dropped"));
print("{:>77}".format("(1 min     3 min     5 min     total)"));

with Controller() as controller:
    for dp in controller.get_dataplanes():
        with dp:
            for rl in data['icmp-types']:
                    type = rl['icmp-type']
                    print("{:<23} {:<5} {:<10} {:<9} {:<9} {:<9} {:<9}" .format(
                        type,
                        rl['limit'],
                        rl['sent'],
                        rl['dropped-1-min'],
                        rl['dropped-3-min'],
                        rl['dropped-5-min'],
                        rl['dropped']))

