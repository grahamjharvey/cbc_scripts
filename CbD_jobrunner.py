#!/usr/bin/env python

#from cbapi.psc.defense import *
#from cbapi.example_helpers import build_cli_parser, get_cb_defense_object
from cbapi.example_helpers import build_cli_parser
from concurrent.futures import as_completed
import sys
import csv
import json
import os
from datetime import datetime, timedelta
from cbapi.example_helpers import build_cli_parser, get_cb_defense_object
from cbapi.psc.defense import Device

def main():
    parser = build_cli_parser()
    parser.add_argument("--job", action="store", default="examplejob", required=True)

    args = parser.parse_args()

    sensorList = []
    cb = get_cb_defense_object(args)

    if os.path.isfile('hosts.csv'):
    	#open CSV that contains DeviceID and HostName
    	with open('hosts.csv', 'r') as f:
    		row_count = 0
    		csv_reader = csv.reader(f, delimiter=',')
    		for row in csv_reader:
        		if (row and row_count > 0):
                		sensorList.append(row[0] + "|" + row[1])
        		row_count += 1

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

    online_sensors = []
    offline_sensors = []
    now = datetime.utcnow()
    delta = timedelta(minutes=10)

    if len(sensorList) > 0:
	print("Attempting to communicate with sensors in hosts.csv......")
	for sensor in sensorList:
		sensorID,sensorHostName = sensor.split("|")
        	#devices = list(cb.select(Device).where("hostNameExact:{0}".format(sensorHostName)))
		device = cb.select(Device,sensorID)
		if device:	
			if now - device.lastContact < delta:
				online_sensors.append(device)
                	else:
                   		offline_sensors.append(device)
    else:
	print("Retrieving all check-in sensors......")
        sensor_query = cb.select(Device)
    	# Retrieve the list of sensors that are online
    	# calculate based on sensors that have checked in during the last five minutes
    	now = datetime.utcnow()
    	delta = timedelta(minutes=5)

    	for sensor in sensor_query:
        	if now - sensor.lastContact < delta:
            		online_sensors.append(sensor)
        	else:
            		offline_sensors.append(sensor)

    print("The following sensors are offline and will not be queried:")
    for sensor in offline_sensors:
       	print("  {0}: {1}".format(sensor.deviceId, sensor.name))

    print("The following sensors are online and WILL be queried:")
    for sensor in online_sensors:
	#print(sensor)
       	print("  {0}: {1}".format(sensor.deviceId, sensor.name))

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
       		f = cb.live_response.submit_job(jobobject.run, sensor)
       		futures[f] = sensor.deviceId
	print(" ")

    # iterate over all the futures
    for f in as_completed(futures.keys(), timeout=30000):
        if f.exception() is None:
            print("Sensor {0} had result:".format(futures[f]))
            print(f.result())
            completed_sensors.append(futures[f])
        else:
            print("Sensor {0} had error:".format(futures[f]))
            print(f.exception())


    still_to_do = set([s.deviceId for s in online_sensors]) - set(completed_sensors)
    print("The following sensors were attempted but not completed or errored out:")
    for sensor in still_to_do:
        print("  {0}".format(still_to_do))
    

if __name__ == '__main__':
    sys.exit(main())
