#!/bin/bash
# ------------------------------------------------------------------------
# Author: A. Rengaramalingam
# Script: Service Template Config Generator
# Purpose:
#   Automates the generation of Versa Director device template configs
#   with BGP and TVI mappings for DMZ and Common VR.
#
# Purpose:
#   Automates creation of Versa device template configuration files.
#
# Summary of Logic:
#   - Takes a list of routing-instances, global-vrf-id and starting TVI number.
#   - For each routing-instance:
#       * Creates a PAIR of TVI interfaces:
#           - TVI-EVEN (e.g., tvi-0/804) → Assigned IP 169.254.0.<even>/31
#           - TVI-ODD  (e.g., tvi-0/805) → Assigned IP 169.254.0.<odd>/31
#
#       * Mapping Rules:
#           - TVI-EVEN → added to COMMON_VR routing-instance
#           - TVI-ODD  → added to TEMPLATE-specific routing-instance
#
#       * Zones:
#           - TVI-EVEN → mapped under Provider-Tenant zone
#           - TVI-ODD  → mapped under TENANT_NAME zone
#
#       * Traffic Identification:
#           - TVI-EVEN → tagged under Provider-Tenant
#           - TVI-ODD  → tagged under TENANT_NAME
#
#       * BGP Configuration:
#           - COMMON_VR uses fixed BGP ASN 64515 (peer with TVI-ODD IP).
#           - BGP ID gets dynamically calculated : tvLRTI.Id==global-vrf-id
#             #2034   #set ($BGP_ID = 3000 + $MAX_WAN_RTI + ${tvLRTI.Id})
#             #2035   bgp ${BGP_ID} {
#             -> Implemented as: BGP=$((3000 + 12 + $2))
#
# ------------------------------------------------------------------------
PROVIDER_TENANT="Provider-Tenant"
COMMON_VR="ARMY-COMMON-VR"


COMMON_VR_BGP_ID="3014"  #this is hard coded. Check your Director GUI and ensure this value matches your ARMY-COMMON-VR BGP ID value

echo -e
read -p "Enter your Tenant Name (e.g. Army, AirForce, etc...) : " TENANT_NAME
echo -e  "\e[32mYour Tenant Name is set to:  $TENANT_NAME \e[0m"


echo -e
read -p "Enter your LAN-VR name that will *connect* to ARMY-COMMON-VR: " ROUTING_INSTANCES
echo -e  "\e[32mYour LAN-VR name is set to:  $ROUTING_INSTANCES \e[0m"

echo -e
read -p "Enter your BGP Instance ID to assign to your new LAN-VR (Pick a number 3000-4000: " BGP
echo -e  "\e[32mYour BGP Instance ID of $BGP is set to:  $BGP \e[0m"




if [[ $BGP =~ ^[+-]?[0-9]+$ ]]; then
    echo ""
else
  echo  -e "\e[31m$BGP is not an integer. I am exiting. Please try again. \e[0m"
  exit 0
fi

read -p "Please supply the TVI Index number you would like to use. I will make two interfaces for you. ( e.g. 802, I will make 802 and 803) : " TVI
echo -e  "\e[32mYour base TVI will be is set to:  $TVI  \e[0m"
echo -e

echo -e
echo -e "\e[1;35mDEFAULTS\e[0m"
echo -e
echo -e "\e[35mYour Provider-Tenant name is set to: \e[1;35m $PROVIDER_TENANT \e[0m"
echo -e
echo -e "\e[35mYour COMMON-VR name is set to: \e[1;35m ARMY-COMMON-VR\e[0m"
echo -e








set -- $ROUTING_INSTANCES
    TEMPLATE=$1
	#2034                             #set ($BGP_ID = 3000 + $MAX_WAN_RTI + ${tvLRTI.Id})
	#2035                             bgp ${BGP_ID} {

# BGP=$((3000 + 12 + $2))
    shift 2

    # --- Recalculate values for each iteration ---
    last_two=$((10#$(echo $TVI | tail -c 3)))
    IP_EVEN="169.254.0.$last_two/31"
    IP_ODD="169.254.0.$((last_two + 1))/31"
    TVI_EVEN=$TVI
    TVI_ODD=$((TVI + 1))


echo -e
echo -e "\e[1;33mCOPY AND PASTE THE INFO BELOW INTO THE DIRECTOR's CLI IN CONFIG MODE. THEN TYPE COMMIT\e[0m"


#outfile="${TEMPLATE}.cfg"
        # --- Default Bare minimum Service Template Org & Services ---
        echo "set devices template $TEMPLATE config orgs org $PROVIDER_TENANT appliance-owner"
        echo "set devices template $TEMPLATE config orgs org $PROVIDER_TENANT services [ sdwan ]"
        echo "set devices template $TEMPLATE config orgs org-services $PROVIDER_TENANT class-of-service qos-policies qos-policy-group Default-Policy"
        echo "set devices template $TEMPLATE config orgs org-services $PROVIDER_TENANT class-of-service app-qos-policies app-qos-policy-group Default-Policy"
        echo "set devices template $TEMPLATE config orgs org-services $PROVIDER_TENANT sd-wan policies sdwan-policy-group Default-Policy"
        echo "set devices template $TEMPLATE config orgs org-services $PROVIDER_TENANT security access-policies access-policy-group Default-Policy"
        echo "set devices template $TEMPLATE config service-node-groups service-node-group default-sng id 0"
        echo "set devices template $TEMPLATE config service-node-groups service-node-group default-sng type internal"
        echo "set devices template $TEMPLATE config service-node-groups service-node-group default-sng services [ sdwan ]"

        # --- Interfaces ---
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} description \"COMMON-VR Split Tunnel interface between $COMMON_VR and $TEMPLATE\""
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} enable true"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} type paired"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} paired-interface tvi-0/${TVI_ODD}"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} unit 0 enable true"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_EVEN} unit 0 family inet address $IP_EVEN"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} description \"LAN side Split Tunnel Interface between $COMMON_VR and $TEMPLATE\""
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} enable true"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} type paired"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} paired-interface tvi-0/${TVI_EVEN}"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} unit 0 enable true"
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/${TVI_ODD} unit 0 family inet address $IP_ODD"

        # --- tvi Interface Mapping base ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} interfaces [ tvi-0/${TVI_EVEN}.0 ]"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE interfaces [ tvi-0/${TVI_ODD}.0 ]"

        # --- Zone Mapping base ---
        echo "set devices template $TEMPLATE config orgs org-services ${PROVIDER_TENANT} objects zones zone L-ST-$ROUTING_INSTANCES-COMMON_VR interface-list [ tvi-0/${TVI_EVEN}.0 ]"
        echo "set devices template $TEMPLATE config orgs org-services ${TENANT_NAME} objects zones zone L-ST-$ROUTING_INSTANCES-COMMON_VR interface-list [ tvi-0/${TVI_ODD}.0 ]"

        # --- traffic-identification Mapping base ---
        echo "set devices template $TEMPLATE config orgs org ${PROVIDER_TENANT} traffic-identification using [ tvi-0/${TVI_EVEN}.0 ]"
        echo "set devices template $TEMPLATE config orgs org ${TENANT_NAME} traffic-identification using  [ tvi-0/${TVI_ODD}.0 ]"

        # --- Routing Instance base ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} instance-type vrf"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE instance-type vrf"

        # --- Common BGP ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} enable-alarms"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} local-as as-number 64515"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ST-Group-with-$ROUTING_INSTANCES type externa
l"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ST-Group-with-$ROUTING_INSTANCES family inet
unicast"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ST-Group-with-$ROUTING_INSTANCES neighbor 169
.254.0.$((last_two + 1)) peer-as 64514 local-address 169.254.0.$last_two"

        # --- Template-Specific BGP ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP local-as as-number 64514"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP group ST-Group-with-CommonVR type external"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP group ST-Group-with-CommonVR family inet unicast"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP group ST-Group-with-CommonVR peer-as 64515"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP group ST-Group-with-CommonVR local-address 169.254.0.$((last_two + 1)
)"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $TEMPLATE protocols bgp bgp $BGP group ST-Group-with-CommonVR neighbor 169.254.0.$last_two"

