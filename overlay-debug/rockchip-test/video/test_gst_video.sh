#!/bin/bash

URI=file:///usr/local/test.mp4
if [ "$1" != "" ]
then
    URI=$1
    if [ "${URI:0:1}" != "/" ]
    then
        URI=$(readlink -f $URI)
    fi
fi

if [ "${URI:0:1}" == "/" ]
then
    URI=file://$URI
fi

gst-launch-1.0 uridecodebin uri=$URI ! xvimagesink
