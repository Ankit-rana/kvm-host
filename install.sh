#!/bin/bash
# ****************************************************************************
# Filename: install.sh
#
# Description:
#
#  Script to install kvm-host on baremetal
#
# Creation Date:  October 2015
#
# Author:         Ankit Rana
#
# Do NOT modify or remove this copyright and confidentiality notice!
#
# Copyright (c) 2014 - $Date: 2014/10/23 $ Seagate Technology, LLC.
#
# The code contained herein is CONFIDENTIAL to Seagate Technology, LLC.
# Portions are also trade secret. Any use, duplication, derivation, distribution
# or disclosure of this code, for any reason, not expressly authorized is
# prohibited. All other rights are expressly reserved by Seagate Technology, LLC.
# ****************************************************************************

#------------------------------------------------------------------------------

function install_config(){  
	
	git clone https://github.com/Ankit-rana/kvm-host.git
	cd kvm-host
	virsh define kvm1oem.xml
	virsh define kvm100.xml
	virsh define kvm101.xml
	virsh define kvm102.xml
	virsh define kvm103.xml
	
} # install_config()

function install_storage(){

} # install_storage()

#------------------------------------------------------------------------------
# Main script

#write your code here


#------------------------------------------------------------------------------
# End of Script
#------------------------------------------------------------------------------
