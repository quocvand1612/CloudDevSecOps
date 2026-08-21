import os
import json
import hmac
import hashlib
import logging
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP_NAME")
VMSS_NAME = os.environ.get("VMSS_NAME")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
RUNNER_LABELS = [l.strip() for l in os.environ.get("RUNNER_LABELS", "self-hosted,azure-spot").split(",")]

def verify_signature(payload_body: bytes, signature_header: str, secret: str) -> bool:
    if not secret or not signature_header:
        logging.warning("Webhook secret or signature header missing. Proceeding with caution.")
        return True
    hash_object = hmac.new(secret.encode("utf-8"), msg=payload_body, digestmod=hashlib.sha256)
    expected_signature = "sha256=" + hash_object.hexdigest()
    return hmac.compare_digest(expected_signature, signature_header)

@app.route(route="webhook", methods=["POST"])
def github_webhook(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Received GitHub Webhook request on Azure Function Scaler.")
    try:
        body_bytes = req.get_body()
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

        matches_runner = any(label in job_labels for label in RUNNER_LABELS)
        if not matches_runner:
            logging.info(f"Job labels {job_labels} do not match {RUNNER_LABELS}. Skipping scale.")
            return func.HttpResponse(json.dumps({"message": "Label mismatch"}), status_code=200, mimetype="application/json")

        if action == "queued":
            logging.info(f"Scaling out Azure VMSS: {VMSS_NAME} in resource group {RESOURCE_GROUP}")
            credential = DefaultAzureCredential()
            compute_client = ComputeManagementClient(credential, SUBSCRIPTION_ID)

            vmss = compute_client.virtual_machine_scale_sets.get(RESOURCE_GROUP, VMSS_NAME)
            current_capacity = vmss.sku.capacity or 0

            # Scale out by 1
            new_capacity = current_capacity + 1
            logging.info(f"Scaling VMSS capacity from {current_capacity} to {new_capacity}")

            from azure.mgmt.compute.models import VirtualMachineScaleSetUpdate, Sku
            update_params = VirtualMachineScaleSetUpdate(sku=Sku(capacity=new_capacity))

            compute_client.virtual_machine_scale_sets.begin_update(
                RESOURCE_GROUP,
                VMSS_NAME,
                update_params
            )
            return func.HttpResponse(json.dumps({"message": "Scaling out triggered", "new_capacity": new_capacity}), status_code=200, mimetype="application/json")

        return func.HttpResponse(json.dumps({"message": f"Action {action} acknowledged"}), status_code=200, mimetype="application/json")

    except Exception as e:
        logging.error(f"Error handling webhook: {str(e)}", exc_info=True)
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")
