import os
import json
import hmac
import hashlib
import logging
import urllib.request
import urllib.error
import azure.functions as func
from azure.core.exceptions import ResourceExistsError
from azure.data.tables import TableServiceClient

try:
    from azure.identity import DefaultAzureCredential
    HAS_AZURE_IDENTITY = True
except ImportError:
    HAS_AZURE_IDENTITY = False

# GitHub sends HMAC signature header 'X-Hub-Signature-256' for authentication.
# Anonymous HTTP auth level allows GitHub Webhooks to reach this handler,
# where verify_signature enforces fail-closed cryptographic validation.
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP_NAME")
VMSS_NAME = os.environ.get("VMSS_NAME")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
RUNNER_LABELS = [l.strip() for l in os.environ.get("RUNNER_LABELS", "self-hosted,azure-spot").split(",") if l.strip()]
JOB_DEDUP_TABLE = "workflowjobdedup"


def claim_workflow_job(job_id) -> bool:
    """Claim a queued job once; GitHub redeliveries retain the same job ID."""
    if job_id is None:
        return True

    storage_connection = os.environ.get("AzureWebJobsStorage")
    if not storage_connection:
        raise RuntimeError("AzureWebJobsStorage is not configured for webhook deduplication")

    table_client = TableServiceClient.from_connection_string(storage_connection).create_table_if_not_exists(JOB_DEDUP_TABLE)
    try:
        table_client.create_entity({
            "PartitionKey": "workflow_job",
            "RowKey": str(job_id),
        })
        return True
    except ResourceExistsError:
        logging.info("Duplicate queued delivery for workflow job %s; skipping scale-out.", job_id)
        return False


def release_workflow_job(job_id) -> None:
    if job_id is None:
        return

    storage_connection = os.environ.get("AzureWebJobsStorage")
    if storage_connection:
        try:
            table_client = TableServiceClient.from_connection_string(storage_connection).get_table_client(JOB_DEDUP_TABLE)
            table_client.delete_entity("workflow_job", str(job_id))
        except Exception as e:
            logging.warning("Failed to release deduplication claim for job %s: %s", job_id, str(e))

def verify_signature(payload_body: bytes, signature_header: str, secret: str) -> bool:
    if not secret or not signature_header:
        logging.error("Webhook secret or signature header is missing.")
        return False
    hash_object = hmac.new(secret.encode("utf-8"), msg=payload_body, digestmod=hashlib.sha256)
    expected_signature = "sha256=" + hash_object.hexdigest()
    return hmac.compare_digest(expected_signature, signature_header)

def get_azure_management_token() -> str:
    # 1. Try DefaultAzureCredential if azure-identity is available
    if HAS_AZURE_IDENTITY:
        try:
            credential = DefaultAzureCredential()
            token_obj = credential.get_token("https://management.azure.com/.default")
            return token_obj.token
        except Exception as e:
            logging.info("DefaultAzureCredential fallback: %s", str(e))

    # 2. App Service / Azure Functions Managed Identity endpoint
    identity_endpoint = os.environ.get("IDENTITY_ENDPOINT") or os.environ.get("MSI_ENDPOINT")
    identity_header = os.environ.get("IDENTITY_HEADER") or os.environ.get("MSI_SECRET")

    if identity_endpoint and identity_header:
        url = f"{identity_endpoint}?resource=https://management.azure.com/&api-version=2019-08-01"
        req = urllib.request.Request(url, headers={"X-IDENTITY-HEADER": identity_header})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["access_token"]

    # 3. Azure IMDS endpoint fallback
    imds_url = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
    req = urllib.request.Request(imds_url, headers={"Metadata": "true"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["access_token"]

def scale_vmss_capacity(subscription_id: str, resource_group: str, vmss_name: str, increment: int = 1) -> int:
    token = get_azure_management_token()
    base_url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/{vmss_name}?api-version=2023-09-01"

    # Get current VMSS details
    get_req = urllib.request.Request(base_url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(get_req, timeout=15) as resp:
        vmss_data = json.loads(resp.read().decode("utf-8"))
        current_sku = vmss_data.get("sku", {})
        current_capacity = current_sku.get("capacity", 0)

    new_capacity = current_capacity + increment
    current_sku["capacity"] = new_capacity
    logging.info(f"Scaling VMSS {vmss_name} capacity from {current_capacity} to {new_capacity}")

    # Patch new capacity
    patch_body = json.dumps({
        "location": vmss_data.get("location"),
        "sku": current_sku
    }).encode("utf-8")

    patch_req = urllib.request.Request(
        base_url,
        data=patch_body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        },
        method="PATCH"
    )

    try:
        with urllib.request.urlopen(patch_req, timeout=20) as patch_resp:
            logging.info(f"Scale PATCH responded with status {patch_resp.status}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        logging.error(f"HTTPError {e.code}: {err_body}")
        raise RuntimeError(f"ARM API Error {e.code}: {err_body}")

    return new_capacity

@app.route(route="webhook", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def github_webhook(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Received GitHub Webhook request on Azure Function Scaler.")
    try:
        body_bytes = req.get_body()
        if len(body_bytes) > 1024 * 1024:
            logging.warning("Rejected webhook payload larger than 1 MiB.")
            return func.HttpResponse(json.dumps({"error": "Payload too large"}), status_code=413, mimetype="application/json")
        sig_header = req.headers.get("x-hub-signature-256", "")

        if not verify_signature(body_bytes, sig_header, WEBHOOK_SECRET):
            logging.error("Invalid HMAC signature received.")
            return func.HttpResponse(json.dumps({"error": "Unauthorized"}), status_code=401, mimetype="application/json")

        event_type = req.headers.get("x-github-event", "")
        if event_type == "ping":
            return func.HttpResponse(json.dumps({"message": "PONG"}), status_code=200, mimetype="application/json")

        if event_type != "workflow_job":
            return func.HttpResponse(json.dumps({"message": f"Ignored event: {event_type}"}), status_code=200, mimetype="application/json")

        payload = json.loads(body_bytes.decode("utf-8"))
        action = payload.get("action")
        job = payload.get("workflow_job", {})
        job_labels = job.get("labels", [])

        logging.info(f"workflow_job action='{action}', labels={job_labels}, job_id={job.get('id')}")

        required_labels = set(RUNNER_LABELS)
        job_labels_set = set(job_labels)
        if not required_labels.issubset(job_labels_set):
            logging.info(f"Job labels {job_labels} do not match required runner labels {RUNNER_LABELS}. Skipping scale.")
            return func.HttpResponse(json.dumps({"message": "Label mismatch"}), status_code=200, mimetype="application/json")

        if action == "queued":
            job_id = job.get("id")
            if not claim_workflow_job(job_id):
                return func.HttpResponse(json.dumps({"message": "Duplicate queued event"}), status_code=200, mimetype="application/json")

            logging.info(f"Scaling out Azure VMSS: {VMSS_NAME} in resource group {RESOURCE_GROUP}")
            try:
                new_capacity = scale_vmss_capacity(SUBSCRIPTION_ID, RESOURCE_GROUP, VMSS_NAME, increment=1)
                return func.HttpResponse(json.dumps({"message": "Scaling out triggered", "new_capacity": new_capacity}), status_code=200, mimetype="application/json")
            except Exception:
                release_workflow_job(job_id)
                raise

        return func.HttpResponse(json.dumps({"message": f"Action {action} acknowledged"}), status_code=200, mimetype="application/json")

    except Exception as e:
        logging.error(f"Error handling webhook: {str(e)}", exc_info=True)
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")

