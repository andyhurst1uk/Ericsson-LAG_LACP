################################################################################
# LAG LACP test
################################################################################

################################################################################
# Display and modify the console.
################################################################################

console show
console title "1410 LAG-LACP Test"
console eval {wm geometry . 130x60+100+0}
console eval { .console delete 1.0 end }
wm withdraw .

################################################################################
# Loding package Ericsson DUT API
################################################################################

puts "Loading Package EDutAPI. . .\n" 

package require EDutApi 
#ApiDebugOn
################################################################################
# Source the necessary common functions and configuration files
################################################################################

set 	eSCRIPT_DIR [file dirname [info script]]

source	[file join $eSCRIPT_DIR . INCLUDE common-functions-log.tcl]
source	[file join $eSCRIPT_DIR . INCLUDE utilities.tcl]
##### this loop loads all of the lib files
foreach src_file [glob -dir [file join $eSCRIPT_DIR src] *.tcl] {
    source [file join $eSCRIPT_DIR src $src_file]
}

#source  [file join $eSCRIPT_DIR src 1410_LAG_LACP_conf.tcl]
###### source for N2X
package require AgtClient

################################################################################
# Log file details
################################################################################

# Generate log filename and directory

set TIME	"[string map {/ -} [clock format [clock seconds] \
			-format %d/%m/%y]]_[string map {: -} [clock format [clock seconds] \
			-format %T]]"

set eTEMP_NAME	LAG_LACP_Test\_$TIME

set eLOGS_DIR 	[file join $eSCRIPT_DIR Logs]
set eTEMP_DIR 	[file join $eLOGS_DIR $eTEMP_NAME]
file mkdir $eTEMP_DIR

set eSEQ_LOG [file join $eTEMP_DIR SEQ_LOG.log]


################################################################################
# This is to specify whether to retain the configuration or return to
# Base Line Configuration 
################################################################################

set retainConfig 			$::RETAIN_CONFIGURATION

global DECOMMISSION MAPPER_SLOT_NUMBER  


# Check whether more than one test is switched ON, when caCord is set to Retain the nfig. for the test.

set count [TEST_Scheduled]

if {$retainConfig == 1 && $count > 1} {
        
    Mputs "Error ! - More than ONE test is scheduled to RUN.\n\t  Retain configuration on card option is ENABLED !\
			\n\t  Ensure that ONLY ONE test is scheduled to RUN in this mode. (or) \
			\n\t  Disable Retain Configuration on card option." -c -s
    return 0
}

################################################################################
# General n2x LOGIN Settings
################################################################################

## If testing via a remote PC 
if {$cREMOTE_PC_TEST} {
    AgtSetServerHostname $::cHOST_PC
    }
Mputs "\tConnected to host server: $::cHOST_PC" -c -s
Mputs "\tCurrent sessions open: [AgtListOpenSessions]" -c -s

#set sessionId [AgtOpenSession RouterTester900]
#Mputs "\tThis session ID: $sessionId\n" -c -s
    
if {$OpenOrReconectSession} {
    ## Open a NEW session ##
    set sessionId [AgtOpenSession RouterTester900]
    Mputs "\tThis new session ID: $sessionId\n" -c -s
} else {
    ## reconnect to EXISTING sesssion ##
    AgtConnect $sessionId
    Mputs "\tThis old session ID: $sessionId\n" -c -s
    if {$::cKILL_PROFILES} {
        ## 8.1 Delete all profile handles at the end of each test
        set hProfiles [AgtInvoke AgtProfileList ListHandles]
        Mputs " \n\tRemoved any left over Profiles - $hProfiles" -c -s
        foreach HProfiles $hProfiles {
            AgtInvoke AgtProfileList Remove $HProfiles        
        }
    }
}

################################################################################
# Configure the Bridges using API (EDutApi)
################################################################################
Mputs "\tConfiguring the test Bridges to baseline config for $Test_Type test\n" -c -s
## This section sets up the 2 test NEs and the third transport nE is set
## up separately in a section at the end.
set NENum 1
foreach DUT $::cDUT_IP_ADDRESSES {
    
    Mputs "\n\tConnecting to Bridge $NENum - IP: $DUT\n" -c -s
    if {![Edut connect oms1410 NE$NENum $DUT]} {
	Mputs "Error Connecting to Bridge $NENum - IP: $DUT" -c -s
	return
    }
    
    Mputs "\n\tFor NE$NENum the [Edut NE$NENum getswversion]\n" -c -s
    
    # Decomissioning the Bridge
    
    if {$DECOMMISSION } {
        Mputs "\tDecommissioning Bridge $NENum - IP: $DUT " -c -s
        if {![Edut ne$NENum decommission]} {
            Mputs "\tError occured while Decomissioning Bridge $NENum" -c -s
            return
        }
        after 2000
    } else {
        Mputs "\tDecommissioning Bridge. . . Skipped. . ." -c -s
    }
    
    # configure cards in shelf
    
    if {$DECOMMISSION } {
        Mputs "\n\tAdding the Controller & Data Cards to bridge $NENum\n\tPlease wait... This might take some time. . .\n" -c -s
	    
        if {![Edut ne$NENum card add 1x10ge_sc 1]} {
            Mputs "Error - Adding the controller card on bridge $NENum\n" -c -s
            return
        }
        
        if {![Edut ne$NENum card add 1x10ge_sc 2]} {
            Mputs "Error - Adding the controller card on bridge $NENum\n" -c -s
            return
        }
        
        ### Adding Mappers
        Mputs "\tAdding 2 Data Cards to bridge\n" -c -s
        if {![Edut ne$NENum card add 10xge_32mapper [set NE${NENum}_slot1]]} { 
            Mputs "Error - Adding the mapper card on bridge num $NENum\n" -c -s
            return
        }
        
        if {![Edut ne$NENum card add 10xge_sm [set NE${NENum}_slot2]]} { 
            Mputs "Error - Adding the 10xge_sm card on bridge num $NENum\n" -c -s
            return
        }
        
        ##### Adding and setting up SDH cards and physical ports
        for {set i 1} {$i <= 4} {incr i} {
            if {[info exists NE${NENum}_SDH_slot$i]} {
                Mputs "\tAdding number $i STM 8 - SDH Card to bridge\n" -c -s
                
                if {![Edut ne$NENum card add 8xstm [set NE${NENum}_SDH_slot$i]]} { 
                Mputs "Error - Adding the SDH card on bridge num $NENum\n" -c -s
                return
                }
                
                if {![Edut ne$NENum card amend sdhrate [set NE${NENum}_SDH_slot$i]/1 stm16]} { 
                Mputs "Error - Amending the SDH card rate on bridge num $NENum\n" -c -s
                return
                }
                
                 if {![Edut ne$NENum card amend sfp [set NE${NENum}_SDH_slot$i]/1]} { 
                Mputs "Error - Amending the SDH card rate on bridge num $NENum\n" -c -s
                return
                }
                
            } else {
                break
            }
        }
    }   
    Mputs "\tConfiguring the Bridge Num $NENum in 802.1ad mode\n" -c -s
     
    if {![Edut connect oms1410bridge bridge$NENum]} {
        Mputs "Error Connecting to the Bridge num $NENum . . ." -c -s
        return
    }
    
    if {![Edut bridge$NENum amend $::bridgeMode]} {
        Mputs "Error Configuring the Bridge Num $NENum in 802.1ad mode.../Check the bridge configuration" -c -s
        return
    }
    ############################# Adding ports for test and default paths##############
    
    Mputs "\tEnabling the Port(s) on bridge num $NENum\n" -c -s
    for {set i 1} {$i <= 2} {incr i} {
        
        for {set port 1} {$port <= 12} {incr port} {
            Mputs "\tAdding the Port [set NE${NENum}_slot$i]/$port" -c -s
            if {![Edut bridge$NENum port add [set NE${NENum}_slot$i]/$port]} {
                Mputs "Error : Configuring the port [set NE${NENum}_slot$i]/$port on bridge $NENum" -c -s
                return
            }
            if {$port <= 10} {
                ###### Setting port to 'Advertise All' so that Auto neg will work
                if {[catch {Edut bridge$NENum port amend [set NE${NENum}_slot$i]/$port -operatingmode all} addPortToLAGResult1]} {
                    EDutApi::errorMsg "Unable to reset operating mode to all"
                }
            }
        }   
    }
    
    for {set port 11} {$port <= 12} {incr port} {
        Mputs "\tAdding the WAN X connection on WAN port $port" -c -s
        
        if {$port == 11} {
            set i 1    
        } else {
            set i 2
        }
        #Mputs "i = $i [set NE${NENum}_slot$i] $port [set NE${NENum}_SDH_slot$i]" -c -s
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 111000 sdh [set NE${NENum}_SDH_slot$i] 1 111000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 1 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 112000 sdh [set NE${NENum}_SDH_slot$i] 1 112000 ]} {
             Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 2 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 113000 sdh [set NE${NENum}_SDH_slot$i] 1 113000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 3 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 114000 sdh [set NE${NENum}_SDH_slot$i] 1 114000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 4 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 121000 sdh [set NE${NENum}_SDH_slot$i] 1 121000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 5 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 122000 sdh [set NE${NENum}_SDH_slot$i] 1 122000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 6 on bridge $NENum" -c -s
            return
        }
        
        if {![Edut ne$NENum xconn add ether [set NE${NENum}_slot1] $port 123000 sdh [set NE${NENum}_SDH_slot$i] 1 123000 ]} {
            Mputs "Error : Setting the X conn on [set NE${NENum}_slot$i] $port on 7 on bridge $NENum" -c -s
            return
        }
    }
    
    Mputs "\n\tConfiguring the transport VlanS\n" -c -s
    
    #### Set up Transport Vlan on all NEs to cTRANSPORT_VLAN
    if {![Edut bridge$NENum vlan add  $::cTRANSPORT_VLAN1]} {
    Mputs "Error : Configuring the transport Vlan for bridge $NENum" -c -s
    return
    }    
    
    if {![Edut bridge$NENum vlan add  $cTRANSPORT_VLAN2]} {
    Mputs "Error : Configuring the transport Vlan for bridge $NENum" -c -s
    return
    }
    
    Mputs "\tAdding test set ports to transport Vlan" -c -s
    set i 1
    for {set slot 1} {$slot <= 2} {incr slot} {
        for {set port 1} {$port <= 10} {incr port} {
            if {![regexp "[set NE${NENum}_slot$slot]/$port\\M" [array get LAG_NE${NENum}_Ports] trash]} {
                if {$i >= 9} {
                    Mputs "\tAdding port [set NE${NENum}_slot$slot]/$port to Vlan $::cTRANSPORT_VLAN2" -c -s
                    if {![Edut bridge$NENum vlan addport [set NE${NENum}_slot$slot]/$port $::cTRANSPORT_VLAN2]} {
                        Mputs "Error : Could not add port [set NE${NENum}_slot$slot]/$port to vlan $::cTRANSPORT_VLAN2" -c -s
                        return
                    }
                     
                    if {![Edut bridge$NENum vlan amend $::cTRANSPORT_VLAN2 [set NE${NENum}_slot$slot]/$port -taggingenable enabled]} {
                        Mputs "Error : Could not add port [set NE${NENum}_slot$slot]/$port to vlan $::cTRANSPORT_VLAN2" -c -s
                        return 0
                    }
                    incr i
                } else {
                    Mputs "\tAdding port [set NE${NENum}_slot$slot]/$port to Vlan $::cTRANSPORT_VLAN1" -c -s
                    if {![Edut bridge$NENum vlan addport [set NE${NENum}_slot$slot]/$port $::cTRANSPORT_VLAN1]} {
                        Mputs "Error : Could not add port [set NE${NENum}_slot$slot]/$port to vlan $::cTRANSPORT_VLAN1" -c -s
                        return
                    }
                    if {![Edut bridge$NENum vlan amend $::cTRANSPORT_VLAN1 [set NE${NENum}_slot$slot]/$port -taggingenable enabled]} {
                        Mputs "Error : Could not add port [set NE${NENum}_slot$slot]/$port to vlan $::cTRANSPORT_VLAN1" -c -s
                        return 0
                    }
                    incr i
                }
            } 
        }
    }
    
    #Mputs "\n\tConfiguring Policer Profiles\n" -c -s
    #
    #if {![Edut bridge$NENum policer add profile_1g -cir 999 -cbs 100 -eir 1 -ebs 100 -colourmode aware -couplingflag cir-eir]} {
    #Mputs "Error : Configuring policer profiles" -c -s
    #return
    #}
    incr NENum
}

############### Third NE for transport #########################################

    Mputs "\n\tConnecting to Bridge 3 - IP: $::cTRANSPORT_DUT_IP\n" -c -s
    if {![Edut connect oms1410 NE3 $::cTRANSPORT_DUT_IP]} {
	Mputs "Error Connecting to Bridge 3 - IP: $::cTRANSPORT_DUT_IP" -c -s
	return
    }
    
    # Decomissioning the Bridge

    if {$DECOMMISSION } {
        Mputs "\tDecommissioning Bridge 3 - IP: $::cTRANSPORT_DUT_IP" -c -s
        if {![Edut ne3 decommission]} {
            Mputs "\tError occured while Decomissioning Bridge 3" -c -s
            return
        }
        after 2000
    } else {
        Mputs "\tDecommissioning Bridge. . . Skipped. . ." -c -s
    }

    # configure cards in shelf

    if {$DECOMMISSION } {
        
        Mputs "\n\tAdding the Controller & Mapper Card to bridge 3\n\tPlease wait... This might take some time. . .\n" -c -s
     
        if {![Edut ne3 card add 4XSTM4_SC 1]} {
            Mputs "Error - Adding the controller card on bridge 3\n" -c -s
            return
        }
        
        #if {![Edut ne3 card add 4XSTM4_SC 2]} {
        #    Mputs "Error - Adding the controller card on bridge 3\n" -c -s
         #   return
        #}
        
        Mputs "\tAdding number 1 SM Card to bridge\n" -c -s
        if {![Edut ne3 card add 10xge_sm [set NE3_slot1]]} { 
        Mputs "Error - Adding the mapper card on bridge num 3\n" -c -s
        return
        }
    }

    Mputs "\tConfiguring the Bridge Num 3 in 802.1ad mode\n" -c -s
     
    if {![Edut connect oms1410bridge bridge3]} {
        Mputs "Error Connecting to the Bridge num 3 . . ." -c -s
        return
    }

    if {![Edut bridge3 amend $::bridgeMode]} {
        Mputs "Error Configuring the Bridge Num 3 in 802.1ad mode.../Check the birdge configuration" -c -s
        return
    }

    ############################# Adding ports for test and default paths##############

    Mputs "\tEnabling the Port(s) on bridge num 3\n" -c -s
        
    for {set port 1} {$port <= 4} {incr port} {
        Mputs "\tAdding the Port $LAG_NE3_Ports($port)" -c -s
        if {![Edut bridge3 port add $LAG_NE3_Ports($port)]} {
            Mputs "Error : Configuring the port $LAG_NE3_Ports($port) on bridge 3" -c -s
            return
        }
    }
     
        if {![Edut bridge3 port amend $LAG_NE3_Ports(1) -capabilitylayer l1]} {
            Mputs "Error : Configuring the port $LAG_NE3_Ports(1) on bridge 3 to L1" -c -s
            return
        }
        
        if {![Edut bridge3 port amend $LAG_NE3_Ports(2) -capabilitylayer l1]} {
            Mputs "Error : Configuring the port $LAG_NE3_Ports(2) on bridge 3 to L1" -c -s
            return
        }
        
        if {![Edut bridge3 port amend $LAG_NE3_Ports(3) -capabilitylayer l1vlan-mux]} {
            Mputs "Error : Configuring the port $LAG_NE3_Ports(3) on bridge 3 to l1vlan-mux]" -c -s
            return
        }
        
        if {![Edut bridge3 port amend $LAG_NE3_Ports(3) -addvlanmuxport $LAG_NE3_Ports(1)]} {
            Mputs "Error : Could not add muxport $LAG_NE3_Ports(1) to port $LAG_NE3_Ports(3)" -c -s
            return
        }
        
        if {![Edut bridge3 port amend $LAG_NE3_Ports(4) -capabilitylayer l1vlan-mux]} {
            Mputs "Error : Configuring the port $LAG_NE3_Ports(4) on bridge 3 to l1vlan-mux" -c -s
            return
        }
        

        if {![Edut bridge3 port amend $LAG_NE3_Ports(4) -addvlanmuxport $LAG_NE3_Ports(2)]} {
            Mputs "Error : Could not add muxport $LAG_NE3_Ports(2) to port $LAG_NE3_Ports(4)" -c -s
            return
        }

################################################################################
# Test # 1 # Configuration variations tests
################################################################################
## Sending keep Alive to maintain sessionIds
set nelist [list ne1 ne2 ne3]
Mputs "\tSending Session Id Keep alive to NEs $nelist\n" -c -s
if {[catch {sessionKeepAlive $nelist}]} {
    Mputs "ERROR : Could not ping one of the NEs" -c -s
}

if {[TEST_Run 1.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test1.0_REP.log]  
    
    ##### Run individual subsections of the test
    
    set result "PASS"
    ###Section for speed test then list ports to test
    set section_result [PerformTest1 speed $testPortA $testPortB]
    
    if {$result == "PASS" && $section_result == "FAIL"} {
        set result FAIL
    }
    ###Section for Duplex test
    set section_result [PerformTest1 duplex $testPortA $testPortB]
    
    if {$result == "PASS" && $section_result == "FAIL"} {
        set result FAIL
    }
    ####Section for LAN-WAN test
    set section_result [PerformTest1 LANWAN $testPortA $testPortB]
    
    if {$result == "PASS" && $section_result == "FAIL"} {
        set result FAIL
    }
    ###Section for L1-L2 test
    set section_result [PerformTest1 layer $testPortA $testPortB]
    
    if {$result == "PASS" && $section_result == "FAIL"} {
        set result FAIL
    }
    ###Section for VLAN test      ?????
    set section_result [PerformTest1 vlan $testPortA $testPortB]
    
    if {$result == "PASS" && $section_result == "FAIL"} {
        set result FAIL
    }
    
    TEST_AddResult 1.0 $result
}

################################################################################
# Test # 2 # INTRA card LAG - One system Id
################################################################################

if {[TEST_Run 2.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
    
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest2_0 8 LAG_NE1_Ports LAG_NE2_Ports]
     
    ####Create second LAG on both NEs and X ports/LAG and check impact. 
        
    TEST_AddResult 2.0 $result
}

################################################################################
# Test # 3 # INTER card LAG - Two system Id
################################################################################

if {[TEST_Run 3.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pairs on NEs and traffic rates
    set result [PerformTest3_0 LAG_NE1_Ports LAG_NE2_Ports]

        
    TEST_AddResult 3.0 $result
}

################################################################################
# Test # 4 # Group manipulation by removal of link
################################################################################

if {[TEST_Run 4.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
    
    #### Performing provocative section of test where LAG are
    #### created and links removed.
    set result [PerformTest4_0 LAG_NE1_Ports LAG_NE2_Ports]
        
    TEST_AddResult 4.0 $result
}

################################################################################
# Test # 5 # Group manipulation by change of port speed
################################################################################

if {[TEST_Run 5.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest5_0 2 LAG_NE1_Ports LAG_NE2_Ports LAG_NE3_Ports]
        
    TEST_AddResult 5.0 $result
}

################################################################################
# Test # 6 # Group manipulation by change of Auto Neg state
################################################################################

if {[TEST_Run 6.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest6_0 2 LAG_NE1_Ports LAG_NE2_Ports]
        
    TEST_AddResult 6.0 $result
}

################################################################################
# Test # 7 # Denial of service tests
################################################################################

if {[TEST_Run 7.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest7_0 3 LAG_NE1_Ports LAG_NE2_Ports]
        
    TEST_AddResult 7.0 $result
}

################################################################################
# Test # 8 # Group member mismatch tests
################################################################################

if {[TEST_Run 8.0]} {

    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 

    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest8_0 LAG_NE1_Ports LAG_NE2_Ports]

    TEST_AddResult 8.0 $result
}

################################################################################
# Test # 9 # Group disruption due to power fails
################################################################################

if {[TEST_Run 9.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest9_0 LAG_NE1_Ports LAG_NE2_Ports] 
        
    TEST_AddResult 9.0 $result
}

################################################################################
# Test # 10 # Multicast traffic
################################################################################

if {[TEST_Run 10.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest10_0 LAG_NE1_Ports LAG_NE2_Ports] 
        
    TEST_AddResult 10.0 $result
}

################################################################################
# Test # 11 # For future use
################################################################################

if {[TEST_Run 11.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest11_0 LAG_NE1_Ports LAG_NE2_Ports] 
    
    TEST_AddResult 11.0 $result
}

################################################################################
# Test # 12 # For future use
################################################################################

if {[TEST_Run 12.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest12_0 LAG_NE1_Ports LAG_NE2_Ports] 
    
    TEST_AddResult 12.0 $result
}

################################################################################
# Test # 13 # Test case to cover MEF QinQ 802.1p xSTP and IGMP
################################################################################

if {[TEST_Run 13.0]} {
    
    # Specify Report Log directory path for this test
    set eREP_LOG [file join $eTEMP_DIR test2.0_REP.log] 
        
    ####Section for lag pair3 on NEs and traffic rates
    set result [PerformTest13_0 LAG_NE1_Ports LAG_NE2_Ports] 
    
    TEST_AddResult 13.0 $result
}

##############################################################
# KDisconnecting N2X session
##############################################################
### Input options are disconnect - kill
if {![closeOrKillN2Xsession kill]} {
    Mputs "Not able to disconnect from the current session" -c -s
}

##############################################################
# Summerise the test results
##############################################################

TEST_Summerise

Mputs "\n\n-TEST COMPLETED-" -c -s

after 5000

exit

