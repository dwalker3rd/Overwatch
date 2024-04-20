#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# Define a function to execute on SIGINT
function cleanup {
  echo "Exit signal received, exiting script..."
  exit 1
}

# Catch the SIGINT signal and execute the cleanup function
trap cleanup SIGINT

# check if user is running via Azure Cloud Shell
if [[ $AZURE_HTTP_USER_AGENT == "cloud-shell/"* ]]; then
    echo "Running in Azure Cloud Shell..."
fi

clean=$(echo $CLEAN | tr '[:upper:]' '[:lower:]')
if [ "$clean" != "false" ]; then
    clean="true"
    echo "Using new resources..."
else
    echo "Using existing resources..."
fi

quiet=$(echo $QUIET | tr '[:upper:]' '[:lower:]')
if [ "$quiet" != "true" ]; then
    quiet="false"
    echo "Running in interactive mode..."
else
    echo "Running in non-interactive mode..."
fi

# check if user is logged in to Azure CLI
az account show > /dev/null 2>&1
if [ $? != 0 ]; then
    # check if TENANT_ID variable is set
    if [ -z "$TENANT_ID" ]; then
        echo "TENANT_ID variable is not set, please enter your tenant id:"
        read TENANT_ID
        [[ "${TENANT_ID:?}" ]]
    fi
    echo "Attempting to login to Azure CLI..."
    az login --tenant $TENANT_ID #> /dev/null 2>&1 2>&1
    if [ $? != 0 ]; then
        echo "Failed to login to Azure CLI, exiting..."
        exit 1
    fi
else
    if [ -z "$TENANT_ID" ]; then
        currentTenantId=$(az account show --query tenantId -o tsv)
        if [ "$quiet" != "true" ]; then
            echo "TENANT_ID variable is not set, the current tenant is $currentTenantId, do you want to use this tenant? (y/N)"
            read useCurrentTenant
            useCurrentTenant=$(echo ${useCurrentTenant:-"n"} | tr '[:upper:]' '[:lower:]')
            if [ "$useCurrentTenant" = "y" ]; then
                TENANT_ID=$currentTenantId
            fi
        else
            TENANT_ID=$currentTenantId
        fi
        if [ -z "$TENANT_ID" ]; then
            echo "Please enter your tenant id, you can get if from the following url if you are logged into the Azure Portal:"
            echo "https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/Properties"
            read TENANT_ID
            TENANT_ID=${TENANT_ID:-""}
            if [ -z "$TENANT_ID" ]; then
                echo "TENANT_ID cannot be empty, exiting..."
                exit 1
            fi
        fi
    fi
fi

# check if SUBSCRIPTION_ID variable is set
if [ -z "$SUBSCRIPTION_ID" ]; then
    currentSubscriptionId=$(az account show --query id -o tsv)
    if [ "$quiet" != "true" ]; then
        echo "SUBSCRIPTION_ID variable is not set, the current subscription is $currentSubscriptionId, do you want to use this subscription? (y/N)"
        read useCurrentSubscription
        useCurrentSubscription=$(echo ${useCurrentSubscription:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useCurrentSubscription" = "y" ]; then
            SUBSCRIPTION_ID=$currentSubscriptionId
        fi
    else
        SUBSCRIPTION_ID=$currentSubscriptionId
    fi
    if [ -z "$SUBSCRIPTION_ID" ]; then
        echo "Please enter your subscription id, you can get it from here if you are logged into the Azure Portal:"
        echo "https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionsBladeV2"
        read SUBSCRIPTION_ID
        SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-""}
        if [ -z "$SUBSCRIPTION_ID" ]; then
            echo "SUBSCRIPTION_ID cannot be empty, exiting..."
            exit 1
        fi
    fi
fi

# check if subscription is valid, else exit with error
az account show --subscription $SUBSCRIPTION_ID > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "Subscription $SUBSCRIPTION_ID is not found in tenant $TENANT_ID, exiting..."
    exit 1
else
    echo "Setting subscription to $SUBSCRIPTION_ID (Tenant: $TENANT_ID)..."
    az account set --subscription $SUBSCRIPTION_ID > /dev/null 2>&1
    if [ $? != 0 ]; then
        echo "Failed to set subscription to $SUBSCRIPTION_ID, exiting..."
        exit 1
    fi
fi

# check if RESOURCE_LOCATION variable is set, ask if using default uksouth
if [ -z "$RESOURCE_LOCATION" ]; then
    if [ "$quiet" != "true" ]; then
        echo "RESOURCE_LOCATION variable is not set, do you want to use the default location 'uksouth'? (y/N)"
        read useDefaultLocation
        useDefaultLocation=$(echo ${useDefaultLocation:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultLocation" = "y" ]; then
            RESOURCE_LOCATION="uksouth"
        fi
    else
        RESOURCE_LOCATION="uksouth"
    fi
    if [ -z "$RESOURCE_LOCATION" ]; then
        echo "Please enter your resource location, you can see the list of location names by running the following command on another terminal window:"
        echo "az account list-locations --output table"
        read RESOURCE_LOCATION
        RESOURCE_LOCATION=${RESOURCE_LOCATION:-""}
        if [ -z "$RESOURCE_LOCATION" ]; then
            echo "RESOURCE_LOCATION cannot be empty, exiting..."
            exit 1
        fi
    fi
fi

# check if location is valid, else exit with error
az account list-locations --query "[?name=='$RESOURCE_LOCATION']" > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "Location $RESOURCE_LOCATION is not valid, exiting..."
    exit 1
fi

RESOURCE_PREFIX=$RESOURCE_PREFIX
# check if RESOURCE_PREFIX variable is set
if [ -z "$RESOURCE_PREFIX" ]; then
    echo "Please enter your resource prefix:"
    read RESOURCE_PREFIX
    RESOURCE_PREFIX=${RESOURCE_PREFIX:-""}
    if [ -z "$RESOURCE_PREFIX" ]; then
        echo "PREFIX cannot be empty, exiting..."
        exit 1
    fi
    RESOURCE_PREFIX=$(echo $RESOURCE_PREFIX | tr '[:upper:]' '[:lower:]')
fi

# check length of RESOURCE_PREFIX is between 3 and 11 characters
if [ ${#RESOURCE_PREFIX} -lt 3 ] || [ ${#RESOURCE_PREFIX} -gt 11 ]; then
    echo "PREFIX '$RESOURCE_PREFIX', must be between 3 and 11 characters, current length is ${#RESOURCE_PREFIX}, exiting..."
    exit 1
fi

PROJECT_GROUP=$PROJECT_GROUP
# check if PROJECT_GROUP variable is set
if [ -z "$PROJECT_GROUP" ]; then
    echo "Please enter the group name:"
    read PROJECT_GROUP
    PROJECT_GROUP=${PROJECT_GROUP:-""}
    if [ -z "$PROJECT_GROUP" ]; then
        echo "PROJECT cannot be empty, exiting..."
        exit 1
    fi
    PROJECT_GROUP=$(echo $PROJECT_GROUP | tr '[:upper:]' '[:lower:]')
fi

# check length of PROJECT_GROUP is between 3 and 11 characters
if [ ${#PROJECT_GROUP} -lt 3 ] || [ ${#PROJECT_GROUP} -gt 11 ]; then
    echo "PREFIX '$PROJECT_GROUP', must be between 3 and 11 characters, current length is ${#PROJECT_GROUP}, exiting..."
    exit 1
fi

PROJECT_NAME=$PROJECT_NAME
# check if PROJECT_NAME variable is set
if [ -z "$PROJECT_NAME" ]; then
    echo "Please enter the project name:"
    read PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-""}
    if [ -z "$PROJECT_NAME" ]; then
        echo "PROJECT cannot be empty, exiting..."
        exit 1
    fi
    PROJECT_NAME=$(echo $PROJECT_NAME | tr '[:upper:]' '[:lower:]')
fi

# check length of PROJECT_NAME is between 3 and 11 characters
if [ ${#PROJECT_NAME} -lt 3 ] || [ ${#PROJECT_NAME} -gt 11 ]; then
    echo "PREFIX '$PROJECT_NAME', must be between 3 and 11 characters, current length is ${#PROJECT_NAME}, exiting..."
    exit 1
fi

# check if RESOURCE_GROUP_NAME variable is set, ask if using default eastus
if [ -z "$RESOURCE_GROUP_NAME" ]; then
    if [ "$quiet" != "true" ]; then
        echo "RESOURCE_GROUP_NAME variable is not set, do you want to use the default naming '$PROJECT_GROUP'-$PROJECT_NAME-rg'? (y/N)"
        read useDefaultRgName
        useDefaultRgName=$(echo ${useDefaultRgName:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultRgName" = "y" ]; then
            RESOURCE_GROUP_NAME="$PROJECT_GROUP'-$PROJECT_NAME-rg"
        fi
    fi
    if [ -z "$RESOURCE_GROUP_NAME" ]; then
        echo "Please enter your resource group name:"
        read RESOURCE_GROUP_NAME
        RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-""}
        if [ -z "$RESOURCE_GROUP_NAME" ]; then
            echo "RESOURCE_GROUP_NAME cannot be empty, exiting..."
            exit 1
        fi
    fi
fi


# check if USER_ID variable is set, else read from input
if [ -z "$USER_ID" ]; then
    set +e
    currentUserId=$(az ad signed-in-user show --query id -o tsv)
    if [ "$quiet" != "true" ]; then
        echo "USER_ID variable is not set, do you want to use the current user id '$currentUserId'? (y/N)"
        read useCurrentUserId
        useCurrentUserId=$(echo ${useCurrentUserId:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useCurrentUserId" = "y" ]; then
            USER_ID=$currentUserId
        fi
    else
        USER_ID=$(az ad signed-in-user show --query id -o tsv)
    fi
    if [ $? != 0 ]; then
        echo "Failed to get user id, exiting..."
        exit 1
    fi
    if [ -z "$USER_ID" ]; then
        echo "Please enter the user id:"
        read USER_ID
        USER_ID=${USER_ID:-""}
        if [ -z "$USER_ID" ]; then
            echo "USER_ID cannot be empty, exiting..."
            exit 1
        fi
    fi
else
    # get the user email 
    USER_EMAIL=$(az ad user show --id $USER_ID --query mail -o tsv)
    if [ -z "$USER_EMAIL" ]; then
        echo "Failed to get user email, exiting..."
        exit 1
    else
        if [ "$quiet" != "true" ]; then
            echo "Using deployers email for certificate renewal notifications: $USER_EMAIL..."
        fi    
    fi    
fi

# new params
# check if VM_SIZE variable is set
if [ -z "$VM_SIZE" ]; then
    if [ "$quiet" != "true" ]; then
        echo "VM_SIZE variable is not set, do you want to use the default size 'Standard_D4s_v3'? (y/N)"
        read useDefaultVmSize
        useDefaultVmSize=$(echo ${useDefaultVmSize:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultVmSize" = "y" ]; then
            VM_SIZE="Standard_D4s_v3"
        fi
    else
        VM_SIZE="Standard_D4s_v3"
    fi
    if [ -z "$VM_SIZE" ]; then
        echo "Please enter your VM size:"
        read VM_SIZE
        VM_SIZE=${VM_SIZE:-""}
        if [ -z "$VM_SIZE" ]; then
            echo "VM_SIZE cannot be empty, exiting..."
            exit 1
        fi
    fi
fi

# check if RESOURCE_ADMIN_USERNAME variable is set
if [ -z "$RESOURCE_ADMIN_USERNAME" ]; then
    if [ "$quiet" != "true" ]; then
        echo "RESOURCE_ADMIN_USERNAME variable is not set, do you want to use the default username 'jhubadmin'? (y/N)"
        read useDefaultAdminUsername
        useDefaultAdminUsername=$(echo ${useDefaultAdminUsername:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultAdminUsername" = "y" ]; then
            RESOURCE_ADMIN_USERNAME="jhubadmin"
        fi
    else
        RESOURCE_ADMIN_USERNAME="jhubadmin"
    fi
    if [ -z "$RESOURCE_ADMIN_USERNAME" ]; then
        echo "Please enter your admin username:"
        read RESOURCE_ADMIN_USERNAME
        RESOURCE_ADMIN_USERNAME=${RESOURCE_ADMIN_USERNAME:-""}
        if [ -z "$RESOURCE_ADMIN_USERNAME" ]; then
            echo "RESOURCE_ADMIN_USERNAME cannot be empty, exiting..."
            exit 1
        fi
    fi
fi


# check if STORAGE_ACCOUNT_TIER variable is set
if [ -z "$STORAGE_ACCOUNT_TIER" ]; then
    if [ "$quiet" != "true" ]; then
        echo "STORAGE_ACCOUNT_TIER variable is not set, do you want to use the default tier 'Standard'? (y/N)"
        read useDefaultStorageAccountTier
        useDefaultStorageAccountTier=$(echo ${useDefaultStorageAccountTier:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultStorageAccountTier" = "y" ]; then
            STORAGE_ACCOUNT_TIER="Standard"
        fi
    else
        STORAGE_ACCOUNT_TIER="Standard"
    fi
    if [ -z "$STORAGE_ACCOUNT_TIER" ]; then
        echo "Please enter your storage account tier:"
        read STORAGE_ACCOUNT_TIER
        STORAGE_ACCOUNT_TIER=${STORAGE_ACCOUNT_TIER:-""}
        if [ -z "$STORAGE_ACCOUNT_TIER" ]; then
            echo "STORAGE_ACCOUNT_TIER cannot be empty, exiting..."
            exit 1
        fi
    fi
fi

# check if USER_EMAIL variable is set
if [ -z "$USER_EMAIL" ]; then
    if [ "$quiet" != "true" ]; then
        USER_EMAIL=$(az ad user show --id $USER_ID --query mail -o tsv)
        echo "USER_EMAIL variable is not set, do you want to use the default email '$USER_EMAIL'? (y/N)"
        read useDefaultUserEmail
        useDefaultUserEmail=$(echo ${useDefaultUserEmail:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$useDefaultUserEmail" = "y" ]; then
            USER_EMAIL=$USER_EMAIL
        fi
    else
        USER_EMAIL=$(az ad user show --id $USER_ID --query mail -o tsv)
    fi
    if [ -z "$USER_EMAIL" ]; then
        echo "Please enter your user email:"
        read USER_EMAIL
        USER_EMAIL=${USER_EMAIL:-""}
        if [ -z "$USER_EMAIL" ]; then
            echo "USER_EMAIL cannot be empty, exiting..."
            exit 1
        fi
    fi
fi

# check if AUTHORIZED_IP variable is set
# if [ -z "$AUTHORIZED_IP" ]; then
#     if [ "$quiet" != "true" ]; then
#         current_ip=$(curl -s https://api.ipify.org)
#         echo "AUTHORIZED_IP variable is not set, do you want to use the default ip '$current_ip'? (y/N)"
#         read useDefaultAuthorizedIps
#         useDefaultAuthorizedIps=$(echo ${useDefaultAuthorizedIps:-"n"} | tr '[:upper:]' '[:lower:]')
#         if [ "$useDefaultAuthorizedIps" = "y" ]; then
#             AUTHORIZED_IP=$current_ip
#         fi
#     else
#         AUTHORIZED_IP=$current_ip
#     fi
#     if [ -z "$AUTHORIZED_IP" ]; then
#         current_ip=$(curl -s https://api.ipify.org)
#         echo "AUTHORIZED_IP variable is not set, do you want to use the default ip '$current_ip'? (y/N)"
#         read useDefaultAuthorizedIps
#         useDefaultAuthorizedIps=$(echo ${useDefaultAuthorizedIps:-"n"} | tr '[:upper:]' '[:lower:]')
#         if [ "$useDefaultAuthorizedIps" = "y" ]; then
#             AUTHORIZED_IP=$current_ip
#         fi
#     fi
# fi

AUTHORIZED_IP=$(curl -s https://api.ipify.org)

### Terraform state storage account information
TF_RESOURCE_GROUP_NAME=${PROJECT_GROUP}-tfstate-rg
TF_STORAGE_ACCOUNT_NAME=tfstate${PROJECT_NAME}01
TF_STORAGE_CONTAINER_NAME=tfstate
TF_STATE_KEY=${RESOURCE_PREFIX}.tfstate

# print all input variables
echo
echo "Using the following input variables:"
echo
echo "  TENANT_ID = $TENANT_ID"
echo "  SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo "  PROJECT_GROUP = $PROJECT_GROUP"
echo "  PROJECT_NAME = $PROJECT_NAME"
echo "  RESOURCE_LOCATION = $RESOURCE_LOCATION"
echo "  RESOURCE_PREFIX = $RESOURCE_PREFIX"
echo "  RESOURCE_GROUP_NAME = $RESOURCE_GROUP_NAME"
echo "  VM_SIZE = $VM_SIZE"
echo "  RESOURCE_ADMIN_USERNAME = $RESOURCE_ADMIN_USERNAME"
echo "  STORAGE_ACCOUNT_TIER = $STORAGE_ACCOUNT_TIER"
echo "  STORAGE_ACCOUNT_KIND = $STORAGE_ACCOUNT_KIND"
echo "  STORAGE_ACCOUNT_REPLICATION_TYPE = $STORAGE_ACCOUNT_REPLICATION_TYPE"
echo "  AUTHORIZED_IP = $AUTHORIZED_IP"
echo "  USER_ID = $USER_ID"
echo "  USER_EMAIL = $USER_EMAIL"
echo

# print all terraform state variables (defined again below)
echo "Using the following terraform state variables:"
echo
echo "  TF_RESOURCE_GROUP_NAME = $TF_RESOURCE_GROUP_NAME"
echo "  TF_STORAGE_ACCOUNT_NAME = $TF_STORAGE_ACCOUNT_NAME"
echo "  TF_STORAGE_CONTAINER_NAME = $TF_STORAGE_CONTAINER_NAME"
echo "  TF_STATE_KEY = $TF_STATE_KEY"
echo

if [ "$quiet" != "true" ]; then
    echo "Do you want to continue? (y/N)"
    read continue
    if [ "$continue" != "y" ]; then
        echo "Exiting..."
        exit 1
    fi
    echo ""
fi

start=`date +%s`

echo "Enabling Network watchers..."
NETWORK_WATCHER_RG="NetworkWatcherRG"
nw_enabled_locations='westus,eastus,northeurope,westeurope,eastasia,southeastasia,northcentralus,southcentralus,centralus,eastus2,japaneast,japanwest,brazilsouth,australiaeast,australiasoutheast,centralindia,southindia,westindia,canadacentral,canadaeast,westcentralus,westus2,ukwest,uksouth,koreacentral,koreasouth,francecentral,australiacentral,southafricanorth,uaenorth,switzerlandnorth,germanywestcentral,norwayeast,westus3,jioindiawest,swedencentral'
should_import_nw_flag=true

# Check if Network Watchers are available in the selected location
if [[ "$nw_enabled_locations" == *",$RESOURCE_LOCATION,"* ]]; then
    # check if network watcher exists for this location
    nw_rg_query_result=$(az resource list --resource-type 'Microsoft.Network/networkWatchers' --query "[].resourceGroup" -o tsv)
    nw_query_result=$(az resource list --location $RESOURCE_LOCATION --resource-type 'Microsoft.Network/networkWatchers' --query "[].resourceGroup" -o tsv)

    if [ -z "$nw_rg_query_result" ]; then 
        echo "The network watcher resource group was not found. Creating rg and network watcher..."
        az group create --name $NETWORK_WATCHER_RG --location $RESOURCE_LOCATION
        az network watcher configure -g $NETWORK_WATCHER_RG -l $RESOURCE_LOCATION --enabled true
    else
        if [ -z "$nw_query_result" ]; then 
            echo "Creating network watcher for this location..."
            az network watcher configure -g $nw_rg_query_result -l $RESOURCE_LOCATION --enabled true
        fi
    fi
    sleep 30
    echo "Done."
else
  echo "The provided location is not available for resource type 'Microsoft.Network/networkWatchers'"
  should_import_nw_flag=false
  export TF_VAR_network_watcher_count=0
fi

echo "Initializing terraform configuration..."

### Terraform state storage account information
TF_RESOURCE_GROUP_NAME=${PROJECT_GROUP}-tfstate-rg
TF_STORAGE_ACCOUNT_NAME=tfstate${PROJECT_NAME}01
TF_STORAGE_CONTAINER_NAME=tfstate
TF_STATE_KEY=${RESOURCE_PREFIX}.tfstate

# check rg
echo "Checking if resource group $TF_RESOURCE_GROUP_NAME exists..."
tf_resource_group_exist=$(az group exists --name $TF_RESOURCE_GROUP_NAME -o tsv --only-show-errors)
echo "Resource group $TF_RESOURCE_GROUP_NAME exists: $tf_resource_group_exist"

tf_state_key_blob_exist="false"
if [ "$tf_resource_group_exist" = "true" ]; then
    echo "Checking if tf state blob exists..."
    tf_state_key_blob_exist=$(az storage blob exists --account-name $TF_STORAGE_ACCOUNT_NAME --container-name $TF_STORAGE_CONTAINER_NAME --name $TF_STATE_KEY --query exists -o tsv --only-show-errors)
    if [ "$tf_state_key_blob_exist" = "true" ]; then
        echo "Tf state blob exists: $tf_state_key_blob_exist"
        # check lease status
        echo "Checking if tf state blob is leased..."
        tf_state_key_blob_lease_status=$(az storage blob show --account-name $TF_STORAGE_ACCOUNT_NAME --container-name $TF_STORAGE_CONTAINER_NAME --name $TF_STATE_KEY --query properties.lease.status -o tsv --only-show-errors)
        #= "locked" ]; then
        if [ "$tf_state_key_blob_lease_status" = "locked" ]; then
            echo "Breaking lease on $TF_STATE_KEY..."
            az storage blob lease break --account-name $TF_STORAGE_ACCOUNT_NAME --container-name $TF_STORAGE_CONTAINER_NAME --name $TF_STATE_KEY --only-show-errors > /dev/null 2>&1
        fi
    fi
fi

# check if .terraform folder exists
terraform_folder_exist="false"
if [ -d ".terraform" ]; then
    terraform_folder_exist="true"
fi


# The following code will check if all resources in RESOURCES_IN_DEPLOYMENT are valid for the passed in location parameter
LOCATION_DISPLAY_NAME=$(az account list-locations --query "[?name=='${RESOURCE_LOCATION}'].displayName | [0]" -o tsv)         
echo "Checking that $LOCATION_DISPLAY_NAME supports the resource types in this deployment..."

# List of resources that take part of this deployment
RESOURCES_IN_DEPLOYMENT='DataFactory/factories,Compute/virtualMachines,Network/networkInterfaces,ManagedIdentity/userAssignedIdentities,Storage/storageAccounts,KeyVault/vaults'
# Save the default IFS
OLDIFS=$IFS
export IFS=","
for item in $RESOURCES_IN_DEPLOYMENT; do
    export IFS="/"
    read -a strarr <<<"$item" 
    RESOURCE="${strarr[0]}"
    RESOURCE_TYPE="${strarr[1]}"
    result=$(az provider list --query "[?namespace=='Microsoft.${RESOURCE}'].resourceTypes[] | [?resourceType=='${RESOURCE_TYPE}'].locations[] | contains(@, '${LOCATION_DISPLAY_NAME}')")
    if [[ "$result" == "false" ]]; then
        echo "The deployment cannot continue because $item is not available in $LOCATION_DISPLAY_NAME. Change to a different location and try again."
        export IFS=$OLDIFS
        exit 1
    fi
done
# Set IFS back to what it was
export IFS=$OLDIFS

echo "Done. Registering providers..."

# Register resource providers:
az config set clients.show_secrets_warning=False
az provider register --namespace 'Microsoft.OperationalInsights' --verbose
az provider register --namespace 'Microsoft.Insights' --verbose
az provider register --namespace 'Microsoft.AAD' --verbose
az provider register --namespace 'Microsoft.AzureActiveDirectory' --verbose
az provider register --namespace 'Microsoft.KeyVault' --verbose
az provider register --namespace 'Microsoft.DataFactory' --verbose
az provider register --namespace 'Microsoft.Compute' --verbose
az provider register --namespace 'Microsoft.Storage' --verbose
az provider register --namespace 'Microsoft.Security' --verbose
az provider register --namespace 'Microsoft.Network' --verbose
az provider register --namespace 'Microsoft.ManagedIdentity' --verbose

#if tf_state_key_blob_exist or $clean is tru then delete previous deployment file
if [ "$clean" = "true" ]; then
    echo "Deleting any previous deployment file in current directory..."
    rm -d -r -f .terraform
    rm -f .terraform.lock.hcl
    rm -f deploy.tfplan
    rm -f terraform.tfstate
    echo "Done"
fi

echo "Creating/getting Terraform state storage account..."
## Create resource group for terraform state storage account
az group create --name $TF_RESOURCE_GROUP_NAME --location $RESOURCE_LOCATION > /dev/null 2>&1

storage_name_available=$(az storage account check-name --name $TF_STORAGE_ACCOUNT_NAME --query nameAvailable -o tsv)
storage_created="false"    
if [ "$storage_name_available" = "false" ]; then 
    # ask if user wants to use existing storage account
    echo "Storage account $TF_STORAGE_ACCOUNT_NAME already exists, do you want to use it? (y/N)"
    read useExistingStorageAccount
    useExistingStorageAccount=$(echo ${useExistingStorageAccount:-"n"} | tr '[:upper:]' '[:lower:]')
    if [ "$useExistingStorageAccount" = "y" ]; then
        echo "Using existing storage account $TF_STORAGE_ACCOUNT_NAME..."
        storage_created="true"
    else
        # ask if user wants to delete existing storage account
        echo "Do you want to delete anc create a new storage account $TF_STORAGE_ACCOUNT_NAME? (y/N)"
        read deleteExistingStorageAccount
        deleteExistingStorageAccount=$(echo ${deleteExistingStorageAccount:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$deleteExistingStorageAccount" = "y" ]; then
            echo "Deleting storage account $TF_STORAGE_ACCOUNT_NAME..."
            az storage account delete --resource-group $TF_RESOURCE_GROUP_NAME --name $TF_STORAGE_ACCOUNT_NAME --yes > /dev/null 2>&1
        else
            echo "Please delete storage account $TF_STORAGE_ACCOUNT_NAME and try again..."
            exit 1
        fi
    fi
fi

if [ "$storage_created" = "false" ]; then
    echo "Creating storage account $TF_STORAGE_ACCOUNT_NAME..."
    az storage account create --name $TF_STORAGE_ACCOUNT_NAME --resource-group $TF_RESOURCE_GROUP_NAME --location $RESOURCE_LOCATION --sku Standard_LRS --encryption-services blob > /dev/null 2>&1
fi

## Get storage account key of terraform state storage account
TF_STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $TF_RESOURCE_GROUP_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)

storage_container_exist=$(az storage container exists --name $TF_STORAGE_CONTAINER_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --account-key $TF_STORAGE_ACCOUNT_KEY --query exists -o tsv)
storage_container_created="false"

if [ "$storage_container_exist" = "true" ]; then
    # ask if user wants to use existing storage container
    echo "Storage container $TF_STORAGE_CONTAINER_NAME already exists, do you want to use it? (y/N)"
    read useExistingStorageContainer
    useExistingStorageContainer=$(echo ${useExistingStorageContainer:-"n"} | tr '[:upper:]' '[:lower:]')
    if [ "$useExistingStorageContainer" = "y" ]; then
        echo "Using existing storage container $TF_STORAGE_CONTAINER_NAME..."
        storage_container_created="true"
    else
        # ask if user wants to delete existing storage container
        echo "Do you want to delete anc create a new storage container $TF_STORAGE_CONTAINER_NAME? (y/N)"
        read deleteExistingStorageContainer
        deleteExistingStorageContainer=$(echo ${deleteExistingStorageContainer:-"n"} | tr '[:upper:]' '[:lower:]')
        if [ "$deleteExistingStorageContainer" = "y" ]; then
            echo "Deleting storage container $TF_STORAGE_CONTAINER_NAME..."
            az storage container delete --name $TF_STORAGE_CONTAINER_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --account-key $TF_STORAGE_ACCOUNT_KEY --yes > /dev/null 2>&1
        else
            echo "Please delete storage container $TF_STORAGE_CONTAINER_NAME and try again..."
            exit 1
        fi
    fi
fi
if [ "$storage_container_created" = "false" ]; then
    echo "Creating storage container $TF_STORAGE_CONTAINER_NAME..."
    az storage container create --name $TF_STORAGE_CONTAINER_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --account-key $TF_STORAGE_ACCOUNT_KEY > /dev/null 2>&1
fi

echo "Resource group, storage account and container for Terraform state storage created successfully"
echo
echo "Using the following Terraform state storage account information:"
echo
echo "  TF_RESOURCE_GROUP_NAME = $TF_RESOURCE_GROUP_NAME"
echo "  TF_STORAGE_ACCOUNT_NAME = $TF_STORAGE_ACCOUNT_NAME"
echo "  TF_STORAGE_CONTAINER_NAME = $TF_STORAGE_CONTAINER_NAME"
echo "  TF_STORAGE_ACCOUNT_KEY = $TF_STORAGE_ACCOUNT_KEY"
echo "  TF_STATE_KEY = $TF_STATE_KEY"
echo

export TF_VAR_prefix=$RESOURCE_PREFIX
export TF_VAR_location=$RESOURCE_LOCATION
export TF_VAR_compute_size=$VM_SIZE
export TF_VAR_admin_username=$RESOURCE_ADMIN_USERNAME

export TF_VAR_user_object_id=$USER_ID
export TF_VAR_log_analytics_workspace_location=$RESOURCE_LOCATION
export TF_VAR_network_watcher_name=$(az network watcher list --query "[?location=='$RESOURCE_LOCATION'].name" --output tsv)
export TF_VAR_user_ip=$AUTHORIZED_IP
export TF_VAR_main_resource_group_name=$RESOURCE_GROUP_NAME

export TF_VAR_main_storage_account_tier=$STORAGE_ACCOUNT_TIER
if [[ "$STORAGE_ACCOUNT_TIER" == "Premium" ]]; then
    export TF_VAR_main_storage_account_kind="BlockBlobStorage"
else
    export TF_VAR_main_storage_account_kind="BlobStorage"
fi

export MSYS_NO_PATHCONV=1

### Deploy ###
echo "Initializing terraform..."
terraform init -backend-config="storage_account_name=$TF_STORAGE_ACCOUNT_NAME" -backend-config="container_name=$TF_STORAGE_CONTAINER_NAME" -backend-config="access_key=$TF_STORAGE_ACCOUNT_KEY" -backend-config="key=$TF_STATE_KEY" 

if [ "$should_import_nw_flag" = true ]; then 
    export TF_VAR_network_watcher_name=$(az network watcher list --query "[?location=='$RESOURCE_LOCATION'].name" --output tsv)
    export TF_VAR_network_watcher_id=$(az network watcher list --query "[?location=='$RESOURCE_LOCATION'].id" --output tsv)
    export TF_VAR_network_watcher_rg_name=$NETWORK_WATCHER_RG
    terraform import azurerm_network_watcher.main $TF_VAR_network_watcher_id
else
    echo "NW will not be imported"
fi

terraform plan -out deploy.tfplan
echo "Deploying resources, please wait..."
terraform apply deploy.tfplan

if [ $? -eq 0 ]; then
    echo "Resources deployed successfully, finishing configuration..."
else
    echo "Resources deployment failed"
    exit 1
fi

echo '====================================================================================='
echo "All resources were deployed. DS environment configuration running now..."
echo '====================================================================================='

end=`date +%s`
runtime=$((end-start))
vm_password=$(terraform output vm_password)

echo ""
echo '====================================================================================='
echo "Data Science environment setup completed in ${runtime} seconds."
echo "You can access the virtual machine thru the Azure Portal, connect thu Bastion or RDP."
echo ""
echo "Use these credentials to login to the VM:"
echo "VM Username: $RESOURCE_ADMIN_USERNAME"
echo "VM Password: $vm_password"
echo '====================================================================================='
echo ""