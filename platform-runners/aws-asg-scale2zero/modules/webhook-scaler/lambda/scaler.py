import os
import json
import hmac
import hashlib
import boto3
import logging
import time
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

autoscaling = boto3.client("autoscaling")
dynamodb = boto3.client("dynamodb")

ASG_NAME = os.environ.get("ASG_NAME")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
RUNNER_LABELS = [label.strip() for label in os.environ.get("RUNNER_LABELS", "self-hosted,aws-spot").split(",")]
JOB_DEDUP_TABLE = os.environ.get("JOB_DEDUP_TABLE", "")


def claim_workflow_job(job_id) -> bool:
    """Claim a queued job once; GitHub retries retain the same job ID."""
    if not JOB_DEDUP_TABLE or job_id is None:
        return True

    try:
        dynamodb.put_item(
            TableName=JOB_DEDUP_TABLE,
            Item={
                "job_id": {"S": str(job_id)},
                "expires_at": {"N": str(int(time.time()) + 3600)},
            },
            ConditionExpression="attribute_not_exists(job_id)",
        )
        return True
    except ClientError as error:
        if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.info("Duplicate queued delivery for workflow job %s; skipping scale-out.", job_id)
            return False
        raise


def release_workflow_job(job_id) -> None:
    if JOB_DEDUP_TABLE and job_id is not None:
        dynamodb.delete_item(TableName=JOB_DEDUP_TABLE, Key={"job_id": {"S": str(job_id)}})

def verify_signature(payload_body: str, signature_header: str, secret: str) -> bool:
    if not secret or not signature_header:
        logger.error("Webhook secret or signature header is missing.")
        return False
    
    hash_object = hmac.new(secret.encode("utf-8"), msg=payload_body.encode("utf-8"), digestmod=hashlib.sha256)
    expected_signature = "sha256=" + hash_object.hexdigest()
    return hmac.compare_digest(expected_signature, signature_header)

def lambda_handler(event, context):
    try:
        headers = {k.lower(): v for k, v in event.get("headers", {}).items()}
        body = event.get("body", "")
        if len(body.encode("utf-8")) > 1024 * 1024:
            logger.warning("Rejected webhook payload larger than 1 MiB.")
            return {"statusCode": 413, "body": json.dumps({"error": "Payload too large"})}
        
        # Verify signature
        sig_header = headers.get("x-hub-signature-256", "")
        if not verify_signature(body, sig_header, WEBHOOK_SECRET):
            logger.error("Invalid HMAC signature received.")
            return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized: Invalid signature"})}
        
        event_type = headers.get("x-github-event", "")
        if event_type == "ping":
            logger.info("Received ping event from GitHub Webhook.")
            return {"statusCode": 200, "body": json.dumps({"message": "PONG"})}
        
        if event_type != "workflow_job":
            logger.info(f"Ignoring unhandled event type: {event_type}")
            return {"statusCode": 200, "body": json.dumps({"message": "Ignored"})}
        
        payload = json.loads(body)
        action = payload.get("action")
        job = payload.get("workflow_job", {})
        job_labels = job.get("labels", [])
        
        logger.info(f"Received workflow_job action='{action}', labels={job_labels}, job_id={job.get('id')}")
        
        # Check if job requires this runner pool
        # Job must request all required labels of this pool (e.g. self-hosted, aws-spot)
        required_labels = set(RUNNER_LABELS)
        job_labels_set = set(job_labels)
        if not required_labels.issubset(job_labels_set):
            logger.info(f"Job labels {job_labels} do not match required runner labels {RUNNER_LABELS}. Skipping.")
            return {"statusCode": 200, "body": json.dumps({"message": "Label mismatch"})}
        
        if action == "queued":
            job_id = job.get("id")
            if not claim_workflow_job(job_id):
                return {"statusCode": 200, "body": json.dumps({"message": "Duplicate queued event"})}

            logger.info(f"Triggering scale-out on ASG: {ASG_NAME}")
            try:
                asg_response = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])
                groups = asg_response.get("AutoScalingGroups", [])
                if not groups:
                    logger.error(f"ASG {ASG_NAME} not found!")
                    release_workflow_job(job_id)
                    return {"statusCode": 404, "body": json.dumps({"error": "ASG not found"})}

                asg = groups[0]
                current_desired = asg["DesiredCapacity"]
                max_size = asg["MaxSize"]

                if current_desired < max_size:
                    new_desired = current_desired + 1
                    logger.info(f"Scaling ASG {ASG_NAME} from {current_desired} to {new_desired}")
                    autoscaling.set_desired_capacity(
                        AutoScalingGroupName=ASG_NAME,
                        DesiredCapacity=new_desired,
                        HonorCooldown=False
                    )
                    return {"statusCode": 200, "body": json.dumps({"message": "Scaled up", "new_desired": new_desired})}

                logger.warning(f"ASG {ASG_NAME} already at max capacity ({max_size}).")
                release_workflow_job(job_id)
                return {"statusCode": 200, "body": json.dumps({"message": "At max capacity"})}
            except Exception:
                release_workflow_job(job_id)
                raise
                
        elif action == "completed":
            logger.info(f"Job {job.get('id')} completed. Runner instance handles self-termination.")
            return {"statusCode": 200, "body": json.dumps({"message": "Job completed acknowledged"})}
        
        return {"statusCode": 200, "body": json.dumps({"message": "Action processed"})}

    except Exception as e:
        logger.error(f"Error handling webhook: {str(e)}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
