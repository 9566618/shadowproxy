#!/usr/bin/env python3
# -*- coding:utf-8 -*-
import sys
import time


APNIC_DELEGATED_LATEST = "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"


def get_apnic_delegated():
    from urllib import request

    u = request.urlopen(APNIC_DELEGATED_LATEST)
    return u.read().decode('utf-8')


def generate_ipset(content, name, location_set, type_set, output_file):

    if 'ipv4' in type_set:
        cidr_trans = {}
        for i in range(0, 32):
            cidr_trans[2 ** (32 - i - 1)] = i + 1

    output_file.write(f"define {name} = {{\n")

    first_entry = True  

    for line in content.splitlines():
        if line.startswith('#'):
            continue

        splits = line.split('|')
        if len(splits) == 7:
            '''
            This is a Record with 7 fields
            '''

            registry, cc, type_, start, value, _, _ = splits
            if registry != 'apnic':
                continue

            if cc in location_set and type_ in type_set:

                if type_ == 'ipv4':
                    '''
                    In the case of IPv4 address the count of hosts for this range. This count does not have to represent a CIDR range.

                    But. It seems that it is always a CIDR range in this particular file.
                    '''
                    mask = cidr_trans[int(value)]
                    cidr = f"{start}/{mask}"
                    if first_entry:
                        first_entry = False
                    else:
                        output_file.write(",\n")
                    output_file.write(f"    {cidr}")

                elif type_ == 'ipv6':
                    '''
                    In the case of an IPv6 address the value will be the CIDR prefix length from the ‘first address’ value of <start>.
                    '''
                    cidr = f"{start}/{value}"
                    if first_entry:
                        first_entry = False
                    else:
                        output_file.write(",\n")
                    output_file.write(f"    {cidr}")

    output_file.write("\n}\n")


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument('--name', '-n', help='Name of ipset',
                        type=str, required=False)
    parser.add_argument('--location', '-l', help='Location to be filtered, like CN',
                        nargs='+', type=str, required=False)
    parser.add_argument('--address-type', '-t', help='Address type, like ipv4, ipv6',
                        nargs='+', type=str, required=False, choices=['ipv4', 'ipv6'])
    parser.add_argument(
        '--output', '-o', help='Output file, default to stdout', type=str, required=False)

    args = parser.parse_args()

    if not any(vars(args).values()):
        print("No arguments provided. Using default settings to generate chnip4.ips and chnip6.ips.")
        name4 = "chnip4"
        name6 = "chnip6"
        location_set = {"CN"}
        type_set_ipv4 = {"ipv4"}
        type_set_ipv6 = {"ipv6"}

        data = get_apnic_delegated()

        with open("chnip4.ips", "w") as fp4:
            generate_ipset(data, name4, location_set, type_set_ipv4, fp4)

        with open("chnip6.ips", "w") as fp6:
            generate_ipset(data, name6, location_set, type_set_ipv6, fp6)

        print("Generated chnip4.ips and chnip6.ips.")
    else:
        name = args.name
        location_set = set(args.location)
        type_set = set(args.address_type)

        data = get_apnic_delegated()

        if hasattr(args, 'output'):
            with open(args.output, 'w') as fp:
                generate_ipset(data, name, location_set, type_set, fp)
        else:
            generate_ipset(data, name, location_set, type_set, sys.stdout)
