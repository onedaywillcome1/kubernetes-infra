#!/bin/bash

export param="$1"
export KOPS_UPDATE_TEMPLATE_PATH=kops-update-templates
export KUBE_PEM=`grep 'SSH_PEM_NAME:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export CLUSTER_NAME=`grep 'CLUSTER_NAME:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export S3_BUCKET_NAME=`grep 'S3_BUCKET_NAME:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export KOPS_STATE_STORE=s3://$S3_BUCKET_NAME

export ZONES=`grep 'ZONE1:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'ZONE2:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'ZONE3:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export NETWORK_CIDR=`grep 'NETWORK_CIDR:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export DNS_ZONE_PUBLIC_ID=`grep 'DNS_ZONE_ID:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export VPC_ID=`grep 'VPC_ID:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export SUBNET_IDS=`grep 'SUBNET_ID1:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'SUBNET_ID2:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'SUBNET_ID3:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export UTILITY_SUBNET_IDS=`grep 'SUBNET_ID4:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'SUBNET_ID5:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`,`grep 'SUBNET_ID6:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`

export NODES_TYPE=`grep 'NODES_TYPE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export MASTER_TYPE=`grep 'MASTER_DEFAULT_TYPE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export NODE_COUNT=`grep 'NODES_DEFAULT_SIZE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export MASTER_COUNT=`grep 'MASTER_DEFAULT_SIZE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`

export NODES_MIN_SIZE=`grep 'NODES_MIN_SIZE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`
export NODES_MAX_SIZE=`grep 'NODES_MAX_SIZE:' $KOPS_UPDATE_TEMPLATE_PATH/values.yaml | awk '{ print $2}'`


function help(){
  echo "Usage of kops script:"
  echo $'\t'"./kops.sh create-cluster    : create cluster"
  echo $'\t'"./kops.sh update-cluster    : update cluster"
  echo $'\t'"./kops.sh update-master     : update master nodes"
  echo $'\t'"./kops.sh update-worker     : update worker nodes"
  echo $'\t'"./kops.sh rolling-update    : rolling update of current cluster/nodes (It takes a great amount of time)"
  echo $'\t'"./kops.sh exec-ansible      : execute ansible to insall/update addons in kubernetes cluster"
  echo $'\t'"./kops.sh delete-cluster    : delete cluster"
  exit;
}

function isMasterInstanceReady(){
    count=0
    while true; do
        if [ "$count" -eq 20 ];then
            echo "`date +'%Y-%m-%d %H:%M:%S'` Timeout"
            break
        fi
        ((count++))
        echo "`date +'%Y-%m-%d %H:%M:%S'` Waiting for master to be active & running"
        sleep 5
        OUT=`aws ec2 describe-instances --filters Name=tag:Name,Values=*masters.$CLUSTER_NAME "Name=instance-state-name,Values=running" --output text`
        INSTANCE_STATE=`echo "$OUT" | grep STATE | tail -n 1 | cut -f 3`
        if [ "$INSTANCE_STATE" == "running" ];then
            echo "`date +'%Y-%m-%d %H:%M:%S'` INSTANCE STATE is $INSTANCE_STATE"
            break
        fi
    done
    echo "`date +'%Y-%m-%d %H:%M:%S'` Kubernetes master is up & running"
}

[ $# -eq 1 ] || help;

case $param in
create-cluster)
    if [[ ! $(kops get cluster --name "$CLUSTER_NAME") ]]; then
        if [ -e ~/.ssh/${KUBE_PEM} ]; then
            echo "`date +'%Y-%m-%d %H:%M:%S'` ${KUBE_PEM} is already exists under ~/.ssh folder"
        else
            echo "`date +'%Y-%m-%d %H:%M:%S'` Generating private & public key for kubernetes cluster under ~/.ssh/${KUBE_PEM}"
            ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/${KUBE_PEM} -q
        fi

        echo "`date +'%Y-%m-%d %H:%M:%S'` Creating cluster $CLUSTER_NAME"

        bucket=$S3_BUCKET_NAME
        bucket_check=$(aws s3api head-bucket --bucket $bucket 2>&1)

        if [[ -z $bucket_check ]]; then
          echo "`date +'%Y-%m-%d %H:%M:%S'` S3 Bucket ${bucket} exists"
        elif [[ $AWS_DEFAULT_REGION == "us-east-1" ]]; then
          echo "`date +'%Y-%m-%d %H:%M:%S'` Creating s3 Bucket ${bucket}"
          aws s3api create-bucket --bucket ${bucket} --region ${region}
        else
          echo "`date +'%Y-%m-%d %H:%M:%S'` Creating s3 Bucket ${bucket}"
          aws s3api create-bucket --bucket ${bucket} --region ${region} --create-bucket-configuration LocationConstraint=${region}
        fi

        kops create cluster \
            --name=${CLUSTER_NAME} \
            --zones="${ZONES}" \
            --state=s3://${S3_BUCKET_NAME} \
            --networking="calico" \
            --network-cidr="${NETWORK_CIDR}" \
            --dns-zone "${DNS_ZONE_PUBLIC_ID}" \
            --dns="public" \
            --vpc=${VPC_ID} \
            --node-size="${NODES_TYPE}" \
            --master-size="${MASTER_TYPE}" \
            --master-count=${MASTER_COUNT} \
            --node-count=${NODE_COUNT} \
            --associate-public-ip=false \
            --subnets=${SUBNET_IDS} \
            --utility-subnets=${UTILITY_SUBNET_IDS} \
            --ssh-public-key=~/.ssh/${KUBE_PEM}.pub \
            --topology=private \
            --bastion \
            --api-loadbalancer-type=public \
            --output=yaml \
            --yes
        isMasterInstanceReady
    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster is already exists. NO need to execute "
    fi
    ;;
update-cluster)
    if [[ $(kops get cluster --name "$CLUSTER_NAME") ]]; then
        echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
        kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Generating cluster yaml from template file"
        kops toolbox template --template $KOPS_UPDATE_TEMPLATE_PATH/cluster.tmpl.yaml --values $KOPS_UPDATE_TEMPLATE_PATH/values.yaml --output $KOPS_UPDATE_TEMPLATE_PATH/cluster.yaml

        echo "`date +'%Y-%m-%d %H:%M:%S'` Replacing new cluster.yaml with state file in s3: ${S3_BUCKET_NAME}"
        kops replace -f $KOPS_UPDATE_TEMPLATE_PATH/cluster.yaml --name "$CLUSTER_NAME" -v 10

        echo "`date +'%Y-%m-%d %H:%M:%S'` Updating cluster ${CLUSTER_NAME}..."
        kops update cluster ${CLUSTER_NAME} --yes --state=s3://${S3_BUCKET_NAME}

#        kops rolling-update cluster ${CLUSTER_NAME} --yes
    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster ${CLUSTER_NAME} doesn't exists. No need to update"
    fi
    ;;
update-worker)
    if [[ $(kops get cluster --name "$CLUSTER_NAME" --state=s3://${S3_BUCKET_NAME} ) ]]; then
        echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
        kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Generating nodes yaml from template file"
        kops toolbox template --template $KOPS_UPDATE_TEMPLATE_PATH/nodes.tmpl.yaml --values $KOPS_UPDATE_TEMPLATE_PATH/values.yaml --output $KOPS_UPDATE_TEMPLATE_PATH/nodes.yaml

        echo "`date +'%Y-%m-%d %H:%M:%S'` Replacing new nodes.yaml with state file in s3: ${S3_BUCKET_NAME}"
        kops replace -f $KOPS_UPDATE_TEMPLATE_PATH/nodes.yaml --name "$CLUSTER_NAME" -v 10

        echo "`date +'%Y-%m-%d %H:%M:%S'` Updating nodes asg ${CLUSTER_NAME}..."
        kops update cluster ${CLUSTER_NAME} --yes --state=s3://${S3_BUCKET_NAME}
    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster ${CLUSTER_NAME} doesn't exists. No need to update"
    fi
    ;;
update-master)
    if [[ $(kops get cluster --name "$CLUSTER_NAME" --state=s3://${S3_BUCKET_NAME} ) ]]; then
        echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
        kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Generating master-us-ast-1a yaml from template file"
        kops toolbox template --template $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1a.tmpl.yaml --values $KOPS_UPDATE_TEMPLATE_PATH/values.yaml --output $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1a.yaml

        echo "`date +'%Y-%m-%d %H:%M:%S'` Replacing master-us-east-1a.yaml with state file in s3: ${S3_BUCKET_NAME}"
        kops replace -f $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1a.yaml --name "$CLUSTER_NAME" -v 10

        echo "`date +'%Y-%m-%d %H:%M:%S'` Updating master-us-east-1a asg ${CLUSTER_NAME}..."
        kops update cluster ${CLUSTER_NAME} --yes --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Generating master-us-ast-1b yaml from template file"
        kops toolbox template --template $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1b.tmpl.yaml --values $KOPS_UPDATE_TEMPLATE_PATH/values.yaml --output $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1b.yaml

        echo "`date +'%Y-%m-%d %H:%M:%S'` Replacing master-us-east-1b.yaml with state file in s3: ${S3_BUCKET_NAME}"
        kops replace -f $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1b.yaml --name "$CLUSTER_NAME" -v 10

        echo "`date +'%Y-%m-%d %H:%M:%S'` Updating master-us-east-1b asg ${CLUSTER_NAME}..."
        kops update cluster ${CLUSTER_NAME} --yes --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Generating master-us-ast-1c yaml from template file"
        kops toolbox template --template $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1c.tmpl.yaml --values $KOPS_UPDATE_TEMPLATE_PATH/values.yaml --output $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1c.yaml

        echo "`date +'%Y-%m-%d %H:%M:%S'` Replacing master-us-east-1c.yaml with state file in s3: ${S3_BUCKET_NAME}"
        kops replace -f $KOPS_UPDATE_TEMPLATE_PATH/master-us-east-1c.yaml --name "$CLUSTER_NAME" -v 10

        echo "`date +'%Y-%m-%d %H:%M:%S'` Updating master-us-east-1c asg ${CLUSTER_NAME}..."
        kops update cluster ${CLUSTER_NAME} --yes --state=s3://${S3_BUCKET_NAME}

    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster ${CLUSTER_NAME} doesn't exists. No need to update"
    fi
    ;;
rolling-update)
    if [[ $(kops get cluster --name "$CLUSTER_NAME") ]]; then
        echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
        kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Rolling update of your cluster ${CLUSTER_NAME} will start in a seconds..."
        sleep 3
        kops rolling-update cluster ${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME} --yes
    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster ${CLUSTER_NAME} doesn't exists. No need to update"
    fi
    ;;
delete-cluster)
    if [[ $(kops get cluster --name "$CLUSTER_NAME" --state=s3://${S3_BUCKET_NAME} ) ]]; then
        echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
        kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}

        echo "`date +'%Y-%m-%d %H:%M:%S'` Deleting cluster ${CLUSTER_NAME}..."
        kops delete cluster ${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME} --yes
    else
        echo "`date +'%Y-%m-%d %H:%M:%S'` Cluster ${CLUSTER_NAME} doesn't exists. It is already deleted."
    fi
    ;;
exec-ansible)
    echo "`date +'%Y-%m-%d %H:%M:%S'` Exporting kops state to kubeconfig(~/.kube/config)"
    kops export kubecfg --name=${CLUSTER_NAME} --state=s3://${S3_BUCKET_NAME}
    echo "`date +'%Y-%m-%d %H:%M:%S'` Executing ansible playbook to install/update addons"
    ansible-playbook playbook.yaml
    ;;
*)
    help
    ;;
esac
