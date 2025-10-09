
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


# -- GET TENANT NAME INPUT
echo -e
read -p "Enter your Tenant Name (e.g. Army, AirForce, etc...) : " TENANT_NAME
echo -e  "\e[32mYour Tenant Name is set to:  $TENANT_NAME \e[0m"
IS_TENANT=$(grep " ${TENANT_NAME} " "$CONFIG_FILE"  \
        | grep "orgs org " | grep "services"  \
        | awk '{print $8}' \
        )
if [[ -z "$IS_TENANT" ]]; then
    echo  -e "\e[1;31m Could not fetch details for tenant name : ${TENANT_NAME} in workflows template : ${DEVICE_TEMPLATE}  \e[0m"
    echo  -e "\e[1;31m Please provide the correct tenant name.\e[0m"
    return 1
fi

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



# -- GET LAN VRF NAME
echo -e
read -p "Enter your LAN-VR name that will *connect* to ${COMMON_VR}: " ROUTING_INSTANCE
echo -e  "\e[32mYour LAN-VR name is set to:  $ROUTING_INSTANCE \e[0m"
IS_ROUTING_INSTANCE=$(grep " ${ROUTING_INSTANCE} " "$CONFIG_FILE"  \
        | grep routing-instance | grep instance-type  \
        | awk '{print $8}' \
        )
if [[ -z "$IS_ROUTING_INSTANCE" ]]; then
    echo  -e "\e[31m Please check routing instance:${ROUTING_INSTANCE} is created in WORKFLOWS, also ensure tunnel is configured on this routing instance  \e[0m"
    return 1
fi


PROVIDER_TENANT=($(grep "appliance-owner" "$CONFIG_FILE" | awk '{print $8}'))

COMMON_VR_BGP_ID=($(grep "${COMMON_VR}" "$CONFIG_FILE" | grep bgp | grep router-id | awk '{print $12}'))

# -- GET BGP ID AND TVI used on the lan routing instance --
BGP=$(grep "${ROUTING_INSTANCE}" "$CONFIG_FILE"  \
        | grep routing-instance | grep router-id  \
        | awk '{print $12}' \
        )
#Find the tvi number attached to the lan vr routing instance
#TVI_ODD
RI_TVI=$(grep "${ROUTING_INSTANCE}" "$CONFIG_FILE"  \
        | grep routing-instance | grep interfaces  \
        | awk '{print $11}' | cut -d/ -f2 | cut -d. -f1 \
        )
if [[ -z "$RI_TVI" ]]; then
    echo -e
    echo "Did not find any tunnel interface attached to routing instance : ${ROUTING_INSTANCE}"
    echo "Please create tunnels in workflows first"
    echo -e
    return 1
fi


#Find the tvi number attached to the lan vr routing instance
#TVI_EVEN
TRANSPORT_VR_TVI=$(($(grep "${ROUTING_INSTANCE}" "$CONFIG_FILE"  \
        | grep routing-instance | grep interfaces  \
        | awk '{print $11}' | cut -d/ -f2 | cut -d. -f1 \
        ) - 1))

#GET IP of these tvi interfaces
RI_TVI_IP=$(grep "tvi-0/${RI_TVI}" "$CONFIG_FILE"  \
        | grep interfaces | grep address  \
        | awk '{print $NF}' | cut -d/ -f1 \
        )
TRANSPORT_VR_TVI_IP=$(grep "tvi-0/${TRANSPORT_VR_TVI}" "$CONFIG_FILE"  \
        | grep interfaces | grep address  \
        | awk '{print $NF}' | cut -d/ -f1 \
        )

ROUTING_INSTANCE_BGP_GROUP_NAME=$(grep "${ROUTING_INSTANCE}" "$CONFIG_FILE"  \
        | grep routing-instance | grep "$TRANSPORT_VR_TVI_IP"   \
        | awk '{print $14}'\
        | head -n1
        )

set -- $ROUTING_INSTANCE
    TEMPLATE=$ROUTING_INSTANCE
    shift 2

#FINDING underlay transport VR name which originally had the tunnel end point
TRANSPORT_VR=$(grep "tvi-0/${TRANSPORT_VR_TVI}" "$CONFIG_FILE"  \
        | grep routing-instance  \
        | awk '{print $8}'\
        | head -n1
        )
TRANSPORT_VR_BGP_ID=$(grep "${TRANSPORT_VR}" "$CONFIG_FILE"  \
        | grep routing-instance | grep router-id  \
        | awk '{print $12}'\
        | head -n1
        )
if [[ -z "$TRANSPORT_VR" ]]; then
    echo "TRANSPORT_VR is not found for the paired tvi interface, it is probably already moved"
fi
TRANSPORT_VR_BGP_GROUP_NAME=$(grep "${TRANSPORT_VR}" "$CONFIG_FILE"  \
        | grep routing-instance | grep "$RI_TVI_IP"    \
        | awk '{print $14}'\
        | head -n1
        )





#--------------------------------------------------------------------------
echo -e
echo -e "\e[1;35m   *****    INFORMATION DERIVED     *****         \e[0m"
echo -e "\e[35mProvider Tenant name : \e[1;35m$PROVIDER_TENANT\e[0m"
echo -e

echo -e "\e[1;35mUnderlay Transport VR Details:\e[0m"
echo -e "\e[35m  NAME : \e[1;35m$TRANSPORT_VR\e[0m"
echo -e "\e[35m  BGP ID : \e[1;35m$TRANSPORT_VR_BGP_ID\e[0m"
echo -e "\e[35m  GROUP Name : \e[1;35m$TRANSPORT_VR_BGP_GROUP_NAME\e[0m"
echo -e

echo -e "\e[1;35mCommon VR Details:\e[0m"
echo -e "\e[35m  NAME : \e[1;35m$COMMON_VR\e[0m"
echo -e "\e[35m  TVI : \e[1;35m$TRANSPORT_VR_TVI\e[0m"
echo -e "\e[35m  TVI_IP : \e[1;35m$TRANSPORT_VR_TVI_IP\e[0m"
echo -e "\e[35m  BGP ID : \e[1;35m$COMMON_VR_BGP_ID\e[0m"
echo -e

echo -e "\e[1;35mLAN VR Details:\e[0m"
echo -e "\e[35m  TVI : \e[1;35m$RI_TVI\e[0m"
echo -e "\e[35m  TVI_IP : \e[1;35m$RI_TVI_IP\e[0m"
echo -e "\e[35m  BGP ID : \e[1;35m$BGP\e[0m"
echo -e "\e[35m  ROUTING_INSTANCE_BGP_GROUP_NAME : \e[1;35m$ROUTING_INSTANCE_BGP_GROUP_NAME\e[0m"
echo -e
#--------------------------------------------------------------------------

echo -e
echo -e "\e[1;33mCOPY AND PASTE THE INFO BELOW INTO THE DIRECTOR's CLI IN CONFIG MODE. THEN TYPE COMMIT\e[0m"
echo -e
echo -e "\e[1;33mREMEMBER: YOU MUST CREATE SERVICE TEMPLATE WITH NAME : ${TEMPLATE} IN THE UI \e[0m"
echo -e
echo -e


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
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/$TRANSPORT_VR_TVI description \"COMMON-VR Split Tunnel interface between $COMMON_VR and $ROUTING_INSTANCE\""
        echo "set devices template $TEMPLATE config interfaces tvi tvi-0/$RI_TVI description \"LAN side Split Tunnel Interface between $COMMON_VR and $ROUTING_INSTANCE\""

        # --- tvi Interface Mapping base ---
        # -- Remove tunnel binding from workflows template
        if [[ -n "$TRANSPORT_VR" ]]; then
            echo "delete devices template ${DEVICE_TEMPLATE} config routing-instances routing-instance ${TRANSPORT_VR} interfaces tvi-0/$TRANSPORT_VR_TVI.0"
            echo "delete devices template ${DEVICE_TEMPLATE} config orgs org ${PROVIDER_TENANT} traffic-identification using tvi-0/$TRANSPORT_VR_TVI.0"
        fi
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} interfaces tvi-0/$TRANSPORT_VR_TVI.0"
        echo "set devices template $TEMPLATE config routing-instances routing-instance $ROUTING_INSTANCE interfaces tvi-0/$RI_TVI.0"

        # --- traffic-identification Mapping base ---
        echo "set devices template $TEMPLATE config orgs org ${TENANT_NAME} traffic-identification using tvi-0/$TRANSPORT_VR_TVI.0"
        echo "set devices template $TEMPLATE config orgs org ${TENANT_NAME} traffic-identification using tvi-0/$RI_TVI.0"

        # --- Routing Instance base ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} instance-type vrf"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${ROUTING_INSTANCE} instance-type vrf"

        # --- Delete BGP From workflows template for Transport VR
        if [[ -n "$TRANSPORT_VR" ]]; then
            echo "delete devices template $DEVICE_TEMPLATE config routing-instances routing-instance ${TRANSPORT_VR} protocols bgp bgp ${TRANSPORT_VR_BGP_ID} group ${TRANSPORT_VR_BGP_GROUP_NAME} neighbor $RI_TVI_IP"
        fi


        # --- Common BGP ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} enable-alarms"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ${TRANSPORT_VR_BGP_GROUP_NAME} type external"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ${TRANSPORT_VR_BGP_GROUP_NAME} family inet unicast"
        echo "set devices template $TEMPLATE config routing-instances routing-instance ${COMMON_VR} protocols bgp bgp ${COMMON_VR_BGP_ID} group ${TRANSPORT_VR_BGP_GROUP_NAME} neighbor $RI_TVI_IP peer-as 64514 local-address $TRANSPORT_VR_TVI_IP
local-as 64515 "

        # --- Template-Specific BGP ---
        echo "set devices template $TEMPLATE config routing-instances routing-instance $ROUTING_INSTANCE protocols bgp bgp $BGP group ${ROUTING_INSTANCE_BGP_GROUP_NAME} peer-as 64515"
