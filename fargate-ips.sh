#!/bin/bash

# Prompt for AWS profile
read -p "Enter AWS Profile Name: " aws_profile

# Step 1: List all ECS clusters
cluster_arns=$(aws ecs list-clusters --profile "$aws_profile" --query "clusterArns" --output text)

# Check if any clusters were found
if [ -z "$cluster_arns" ]; then
    echo "No ECS clusters found in the specified AWS account."
    exit 1
fi

# Initialize an associative array to store task details
declare -A task_details

# Loop through each cluster to get the tasks and private IP addresses
for cluster_arn in $cluster_arns; do
    cluster_name=$(basename "$cluster_arn")

    echo -e "\nCollecting private IPs for tasks in cluster: $cluster_name"

    # Step 2: List all running tasks in the current ECS cluster
    task_arns=$(aws ecs list-tasks --cluster "$cluster_name" --profile "$aws_profile" --query "taskArns" --output text)

    # Check if any tasks were found in this cluster
    if [ -z "$task_arns" ]; then
        echo "No running tasks found in cluster: $cluster_name."
        continue
    fi

    # Loop through each task ARN to get the ENI and private IP address
    for task_arn in $task_arns; do
        # Step 3: Get the ENI ID for each task
        eni_id=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "$task_arn" --profile "$aws_profile" \
            --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)

        if [ -z "$eni_id" ]; then
            echo "Failed to retrieve ENI ID for task $task_arn in cluster $cluster_name."
            continue
        fi

        # Step 4: Get the private IP address associated with the ENI
        private_ip=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni_id" --profile "$aws_profile" \
            --query "NetworkInterfaces[0].PrivateIpAddress" --output text)

        if [ -n "$private_ip" ]; then
            # Store task ARN and private IP in the associative array
            task_details["$task_arn ($cluster_name)"]=$private_ip
        else
            echo "Failed to retrieve private IP address for ENI $eni_id in cluster $cluster_name."
        fi
    done
done

# Output the private IP addresses of all tasks in all clusters
echo -e "\nPrivate IP addresses of Fargate tasks in all clusters:"
for task_info in "${!task_details[@]}"; do
    echo "Task: $task_info - Private IP: ${task_details[$task_info]}"
done
