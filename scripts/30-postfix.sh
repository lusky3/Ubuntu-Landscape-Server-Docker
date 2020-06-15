#!/bin/bash
#
# Description: Configure Postfix as the MTA
#
if [[ -n $(postconf | grep "mydomain = ec2.internal") ]]; then
    postconf -e "mydomain=$DOMAIN"
fi