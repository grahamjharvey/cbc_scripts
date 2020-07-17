####!!!! Add your Devices v6 API profile to line 23!!!!####

#!/usr/bin/env python

from cbapi.defense import Device
from cbapi.psc import Device as PSC_Device
from cbapi.psc import CbPSCBaseAPI
from cbapi.example_helpers import build_cli_parser, get_cb_defense_object, get_cb_psc_object
from concurrent.futures import as_completed
import sys
import csv
import json
import os
from datetime import datetime, timedelta


def main():
    parser = build_cli_parser()
    parser.add_argument("--job", action="store", default="examplejob", required=True)

    args = parser.parse_args()

    cb_psc = CbPSCBaseAPI(profile="<YOUR V6 API PROFILE HERE")
    cb = get_cb_defense_object(args)

    sensor_query = cb_psc.select(PSC_Device)

    # gets rid of None Type devices - which i believe  comes from inactives
    clean_devices = [x for x in sensor_query if x.last_contact_time != None]

    #open CSV that contains remediation actions
    with open('./actions.csv', 'r') as f:
        actionList = []
        row_count = 0
        csv_reader = csv.reader(f, delimiter=',')
        for row in csv_reader:
            if (row and row_count > 0):
                actionList.append(row[0] + ";" + row[1])
                #print(str(row[0] + "|" + row[1]))
            row_count += 1

    # Retrieve the list of sensors that are online
    # calculate based on sensors that have checked in during the last five minutes
    now = datetime.utcnow()
    delta = timedelta(minutes=20)
    date_format = '%Y-%m-%dT%H:%M:%S.%f'

    online_sensors = []
    offline_sensors = []
    for sensor in clean_devices:

        datetime_to_str = sensor.last_contact_time
        datetime_rm_z = datetime_to_str.replace("Z", "")
        last_contact = datetime.strptime(datetime_rm_z, date_format)

        if now - last_contact < delta:
            online_sensors.append(sensor)
        else:
            offline_sensors.append(sensor)

    print("The following sensors are offline and will not be queried:")
    for sensor in offline_sensors:
        print("  {0}: {1}  {2}".format(sensor.id, sensor.name, sensor.last_contact_time))

    print("The following sensors are online and WILL be queried:")
    for sensor in online_sensors:
        print("  {0}: {1}  {2}".format(sensor.id, sensor.name, sensor.last_contact_time))

    # import our job object from the jobfile
    job = __import__(args.job)
    #jobobject = job.getjob()

    completed_sensors = []
    futures = {}

    # collect 'future' objects for all jobs
    for sensor in online_sensors:
        print(" ")
        print("LR session to [{0}]".format(sensor.name))
        for action in actionList:
            actionType,command = action.split(";")
            jobobject = job.getjob(action)
            print("Processing command <{0}> for action <{1}>.....".format(actionType, command, sensor.name))
            f = cb.live_response.submit_job(jobobject.run, sensor.id)
            futures[f] = sensor.id

    # iterate over all the futures
    for f in as_completed(futures.keys(), timeout=100):
        if f.exception() is None:
            print("Sensor {0} had result:".format(futures[f]))
            print(f.result())
            completed_sensors.append(futures[f])
        else:
            print("Sensor {0} had error:".format(futures[f]))
            print(f.exception())

    still_to_do = set([s.id for s in online_sensors]) - set(completed_sensors)
    print("The following sensors were attempted but not completed or errored out:")
    for sensor in still_to_do:
        print("  {0}".format(still_to_do))


if __name__ == '__main__':
    sys.exit(main())
