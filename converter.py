#  Bill's Super Awesome Vixen to Arduino/AVR/C script
#		www.billporter.info
#
#	This script parses a Vixen Sequence file and outputs a .cpp file with an array
#      of the data that makes up the actual sequence; formatted for Arduino/AVR microcontrollers.
#      Use it to embed short light shows in your next Arduino project.
# 
#	Make sure you call this script with the vixen sequence filename you want to 
#   convert as an argument. Like this: 
#			path>python Vixeno.py show.vix
#
import base64
import sys
import pynbs
import struct
import numpy
from xml.dom import minidom

filein = sys.argv[1]

print ('Opening %s ' % filein)
#open and parse Vixen file
xmldoc = minidom.parse(filein)
itemlist = xmldoc.getElementsByTagName('EventValues')
vixenshow = itemlist[0].childNodes[0].nodeValue
# print (itemlist[0].childNodes[0].nodeValue)

itemlist = xmldoc.getElementsByTagName('Channel') 
channels = len(itemlist)

eventperiod = xmldoc.getElementsByTagName('EventPeriodInMilliseconds')
frameduration = itemlist[0].childNodes[0].nodeValue

#decode base64 endoding. Result is binary
vixenbinary = base64.b64decode(vixenshow)
#breakup binary string to array
outputarray = list(vixenbinary)

#figure out number of samples in the show
samples = int(len(outputarray) / channels)

print('Found %d Channels and %d frames for %d total bytes of memory' % (channels, samples, channels*samples))

new_file = pynbs.new_file(song_name='Fantasy In The sky')
outputformattedarray = []
outputformattedarray = numpy.array_split(outputarray,channels)


notearray = []
for i in range(samples):
    for j in range(channels):
        temp = outputformattedarray[j][i]
        if(temp > 0):
            ins = 4
            if(j > 15):
                ins = 3
            if(j > 31):
                ins = 2
            notearray.append(pynbs.Note(tick=i, layer=j, instrument=ins, key=((j%16) + 33))) 
new_file.header.tempo=1000/int(eventperiod[0].firstChild.nodeValue)
new_file.notes.extend(notearray)
new_file.save('new_file.nbs')
