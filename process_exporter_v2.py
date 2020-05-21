#!/usr/bin/env python
# This script was taken from the VMware Carbon Black public GitHub repository:
# https://github.com/carbonblack/cbapi-python/blob/master/examples/threathunter/process_exporter.py
# and modified by Graham Harvey

import sys

from cbapi.example_helpers import build_cli_parser, get_cb_threathunter_object
from cbapi.psc.threathunter import Process
import json
import csv


def main():
    parser = build_cli_parser("Query processes")
    parser.add_argument("-p", type=str, help="process guid", default=None)
    parser.add_argument("-q", type=str, help="query string", default=None)
    parser.add_argument("-s", type=bool, help="silent mode", default=False)
    parser.add_argument("-n", type=int, help="only output N events", default=None)
    parser.add_argument("-f", type=str, help="output file name", default=None)
    parser.add_argument("-of", type=str, help="output file format: csv, json or list (list of hashes used for binary analysis toolkit input, order is not preserved)", default="json")

    args = parser.parse_args()
    cb = get_cb_threathunter_object(args)

    if not args.p and not args.q:
        print("Error: Missing Process GUID to search for events with")
        sys.exit(1)

    if args.q:
        processes = cb.select(Process).where(args.q)
    else:
        processes = cb.select(Process).where(process_guid=args.p)

    if args.n:
        processes = [p for p in processes[0:args.n]]

    if not args.s:
        for process in processes:
            print("Process: {}".format(process.process_name))
            print("\tPIDs: {}".format(process.process_pids))
            print("\tSHA256: {}".format(process.process_sha256))
            print("\tGUID: {}".format(process.process_guid))

    if args.f is not None:
        if args.of == "json":
            with open(args.f, 'w') as outfile:
                for p in processes:
                    json.dump(p.original_document, outfile)
                    print(p.original_document)
        elif args.of == "csv":
            headers = set()
            headers.update(*(d.original_document.keys() for d in processes))
            with open(args.f, 'w') as outfile:
                csvwriter = csv.DictWriter(outfile, fieldnames=headers)
                csvwriter.writeheader()
                for p in processes:
                    csvwriter.writerow(p.original_document)
        else:
            with open(args.f, 'w') as outfile:
                hashes_list = []
                for process in processes:
                    hashes_list.append(process.process_sha256)
                unique_hashes = list(set(hashes_list))
                for h in unique_hashes:
                    outfile.write((h) + "\n")

if __name__ == "__main__":
    sys.exit(main())
