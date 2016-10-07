# FIRST INSTALL PYTHON MODULOS
# use console
# pip install requests 
# pip install pytz 

# This program is built to automate the course copy process for the use case
# when there is more than one course master each of which needs to be copied
# into at least one live course.  The CSV that this program reads from should
# be formatted into two columns of data.  The first column has the ID for the
# course master, and the second column has the ID for the course that the
# master will be copied into.  Additionally, this program offers the user the
# option of shifting the start and end dates of the new courses while the
# master is being copied in.

import re
import requests
import pytz
import os, sys
from datetime import datetime

# Sets the authorization header, the base Ember URL, and the proper date format.
token = 'HKqiCNWuT5vOXQhgskUACeUdiiG2rCBHm5aJYji8jtYSqaibxZ16kHnFVOnaPMYi'
auth = {'Authorization': 'Bearer ' + token}
# ember = 'https://hotchalkember.com/api/v1/courses/'
ember = 'http://localhost:3000/api/v1/courses/'

# loop on parameters and create an dictionary with the data
# use the dictionary for trigger the course copy routine
parameters = {}
count = 0
for arg in sys.argv:
	if (count > 0):
		item = arg.split(':',1)		
		parameters[item[0]]=item[1]
	count+=1

# print "parameters... " 
# print parameters

# parameters
if parameters['due_dates'] == 1:
	# r = requests.get(ember + parameters['master_id'], headers=auth)	
	# print "r.content... "
	# print r.content

	# a = re.findall(re.compile('\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z'), r.content)
	# old_sdate = pytz.utc.localize(datetime.strptime(a[0], '%Y-%m-%dT%H:%M:%SZ'))
	# old_edate = pytz.utc.localize(datetime.strptime(a[1], '%Y-%m-%dT%H:%M:%SZ'))
	# print "old_sdate.. " + old_sdate
	# print "old_edate.. " + old_edate

	data = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': parameters['master_id'],\
	'date_shift_options[shift_dates]': True, 'date_shift_options[old_start_date]': parameters['master_start_at'],\
	'date_shift_options[old_end_date]': parameters['master_conclude_at'], 'date_shift_options[new_start_date]': parameters['new_start_date']}	

elif parameters['due_dates'] == 0:
	data = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': parameters['master_id']}	

# call the course copy on LMS
# r2 = requests.post(ember + parameters['target_id'] + '/content_migrations', data=data, headers=auth)	

# process the result from LMS
# if str(r2.status_code)[:1] == '2':
# 	print 'Course %s copied successfully.' % parameters['target_id']
# else:
# 	print 'There was a %s error copying course %s.' % (str(r2.status_code), parameters['target_id'])

print("All done!")