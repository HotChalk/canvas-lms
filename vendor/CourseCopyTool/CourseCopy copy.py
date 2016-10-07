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
# import csv
import requests
import pytz
import os, sys
from datetime import datetime

# Sets the authorization header, the base Ember URL, and the proper date format.

# token = 'HKqiCNWuT5vOXQhgskUACeUdiiG2rCBHm5aJYji8jtYSqaibxZ16kHnFVOnaPMYi'
token = 'KgF9jk/LBTxavFA5b8G2SG0CvnwmT/GZelYMEJn0sJBdShm7OIBhCxn7B1wllMR+J2bfDnwXuf8MAFl/25j/4w=='
auth = {'Authorization': 'Bearer ' + token}
# ember = 'https://hotchalkember.com/api/v1/courses/'
ember = 'http://localhost:3000/api/v1/courses/'


# def dateMatch(date_type):
# 	"""Takes user input for the new start date, then makes sure it is formatted properly."""
# 	global date_shift
# 	date_shift = raw_input('Please enter the %s in the following format: YYYY-MM-DD \n> ' % date_type)
# 	date_regex = re.compile('\d{4}-\d{2}-\d{2}')
# 	if date_regex.match(date_shift) is None:
# 			print 'The date you entered was not in the proper format.'
# 			dateMatch(date_type)

# def datePrompt():
# 	"""Checks if the courses need new start and end dates, and runs the dateMatch function if they do."""
# 	global question
# 	question = raw_input('Would you like to adjust the course due dates during the import process? y/n? \n> ').upper()
# 	if question == 'Y':
# 		dateMatch('new course start date')
# 		sdate = datetime.strptime(date_shift, '%Y-%m-%d')
# 		global new_sdate
# 		new_sdate = pytz.utc.localize(sdate)
# 	elif question == 'N':
# 		pass
# 	else:
# 		print 'Please enter either "y" or "n"'
# 		datePrompt()

# datePrompt()

# Opens the file containing masters and courses to be copied into, then iterates through the copying process.

# with open('C:\\Users\\jonathan.kulakofsky\\Google Drive\\Code\\Python\\CourseCopy_10-3.csv', 'rb') as csvfile:
# 	courses = csv.reader(csvfile)
# 	for row in courses:
# 		if question == 'Y':
# 			r = requests.get(ember + row[0], headers=auth)
# 			a = re.findall(re.compile('\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z'), r.content)
# 			old_sdate = pytz.utc.localize(datetime.strptime(a[0], '%Y-%m-%dT%H:%M:%SZ'))
# 			old_edate = pytz.utc.localize(datetime.strptime(a[1], '%Y-%m-%dT%H:%M:%SZ'))
			
# 			parameters = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': row[0],\
# 			'date_shift_options[shift_dates]': True, 'date_shift_options[old_start_date]': old_sdate,\
# 			'date_shift_options[old_end_date]': old_edate, 'date_shift_options[new_start_date]': new_sdate}
			
# 			r2 = requests.post(ember + row[1] + '/content_migrations', data=parameters, headers=auth)
		
# 		elif question == 'N':
# 			parameters = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': row[0]}
# 			r2 = requests.post(ember + row[1] + '/content_migrations', data=parameters, headers=auth)
			
# 		if str(r2.status_code)[:1] == '2':
# 			print 'Course %s copied successfully.' % row[1]
# 		else:
# 			print 'There was a %s error copying course %s.' % (str(r2.status_code), row[1])


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
if parameters['modify_dates'] == 'Y':
	r = requests.get(ember + parameters['master_id'], headers=auth)	
	print "r.content... "
	print r.content
	# a = re.findall(re.compile('\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z'), r.content)
	# old_sdate = pytz.utc.localize(datetime.strptime(a[0], '%Y-%m-%dT%H:%M:%SZ'))
	# old_edate = pytz.utc.localize(datetime.strptime(a[1], '%Y-%m-%dT%H:%M:%SZ'))
	# print "old_sdate.. " + old_sdate
	# print "old_edate.. " + old_edate

	data = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': parameters['master_id'],\
	'date_shift_options[shift_dates]': True, 'date_shift_options[old_start_date]': parameters['master_start_at'],\
	'date_shift_options[old_end_date]': parameters['master_conclude_at'], 'date_shift_options[new_start_date]': parameters['start_date']}
	# r2 = requests.post(ember + parameters['target_id'] + '/content_migrations', data=data, headers=auth)	

elif parameters['modify_dates'] == 'N':
	data = {'migration_type': 'course_copy_importer', 'settings[source_course_id]': parameters['master_id']}
	# r2 = requests.post(ember + parameters['target_id'] + '/content_migrations', data=data, headers=auth)



# r2 = requests.post(ember + parameters['target_id'] + '/content_migrations', data=data, headers=auth)	

# if str(r2.status_code)[:1] == '2':
# 	print 'Course %s copied successfully.' % parameters['target_id']
# else:
# 	print 'There was a %s error copying course %s.' % (str(r2.status_code), parameters['target_id'])


# int(x [,base])


print("All done!")