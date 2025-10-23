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
#
# ------------------------------------------------------------------------

# -- GET WORKFLOWS TEMPLATE NAME
echo -e
read -p "Enter your Workflows device template name : " DEVICE_TEMPLATE
echo -e  "\e[32mYour Workflow device template name is set to:  $DEVICE_TEMPLATE \e[0m"
CONFIG_FILE="/home/Administrator/${DEVICE_TEMPLATE}.cfg"
echo "show configuration devices template ${DEVICE_TEMPLATE} | display set relative | save /home/Administrator/${DEVICE_TEMPLATE}.cfg" | ncs_cli
if [ ! -f "${CONFIG_FILE}" ]; then
    echo ""
    echo  -e "\e[1;31m Could not fetch details of template : ${DEVICE_TEMPLATE}  \e[0m"
    echo  -e "\e[1;31m Please provide the correct workflows template name \e[0m"
    echo ""
    return 1
fi 
echo "✅ Saving device template : /home/Administrator/${DEVICE_TEMPLATE}.cfg"

# -- GET COMMON VR NAME, THIS VR WILL BE DIFFERENT PER TENANT
echo -e
read -p "Enter your COMMON VR name in $TENANT_NAME: " COMMON_VR
echo -e  "\e[32mYour LAN-VR name is set to:  $COMMON_VR \e[0m"
IS_ROUTING_INSTANCE=$(grep " ${COMMON_VR} " "$CONFIG_FILE"  \
        | grep routing-instance | grep instance-type  \
        | awk '{print $8}' \
        )
if [[ -z "$IS_ROUTING_INSTANCE" ]]; then
    echo  -e "\e[31m Please check routing instance:${COMMON_VR} is created in WORKFLOWS, also ensure tunnel is configured on this routing instance  \e[0m"
    return 1
fi

COMMON_VR_BGP_ID=($(grep "${COMMON_VR}" "$CONFIG_FILE" | grep bgp | grep router-id | awk '{print $12}'))


#--------------------------------------------------------------------------
echo -e
echo -e "\e[1;35m   *****    INFORMATION DERIVED     *****         \e[0m"
echo -e "\e[1;35mCommon VR Details:\e[0m"
echo -e "\e[35m  NAME : \e[1;35m$COMMON_VR\e[0m"
echo -e "\e[35m  BGP ID : \e[1;35m$COMMON_VR_BGP_ID\e[0m"
echo -e
#--------------------------------------------------------------------------

echo -e
echo -e "\e[1;33mCOPY AND PASTE THE INFO BELOW INTO THE DIRECTOR's CLI IN CONFIG MODE. THEN TYPE COMMIT\e[0m"
echo -e 

        # --- Common BGP ---
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} routing-options static route rti-static-route-list 0.0.0.0/0 0.0.0.0 none no-install discard"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} policy-options redistribution-policy Default-Policy-To-BGP term T5-Static match protocol static"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} policy-options redistribution-policy Default-Policy-To-BGP term T5-Static action filter accept"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} prefix-list Default-Route-Prefix seq 1 address-family ipv4 unicast address-mask 0.0.0.0/0"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} routing-peer-policy Export-Only-Default term T1-Default match ip nlri prefix-list Default-Route-Prefix"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} routing-peer-policy Export-Only-Default term T1-Default action filter accept"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} routing-peer-policy Export-Only-Default term T1-Default action rib-bgp-ecmp false"

        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} enable-alarms"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ST_Group type external"
        echo "set devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ST_Group export Export-Only-Default"

