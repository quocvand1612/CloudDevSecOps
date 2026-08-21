import os
import json
import hmac
import hashlib
import logging
import urllib.request
import urllib.error
import azure.functions as func

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

def get_azure_management_token() -> str:
    # 1. App Service / Azure Functions Managed Identity endpoint
    identity_endpoint = os.environ.get("IDENTITY_ENDPOINT") or os.environ.get("MSI_ENDPOINT")
    identity_header = os.environ.get("IDENTITY_HEADER") or os.environ.get("MSI_SECRET")

    if identity_endpoint and identity_header:
        url = f"{identity_endpoint}?resource=https://management.azure.com/&api-version=2019-08-01"
        req = urllib.request.Request(url, headers={"X-IDENTITY-HEADER": identity_header})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["access_token"]

    # 2. Azure IMDS endpoint fallback
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
            new_capacity = scale_vmss_capacity(SUBSCRIPTION_ID, RESOURCE_GROUP, VMSS_NAME, increment=1)
            return func.HttpResponse(json.dumps({"message": "Scaling out triggered", "new_capacity": new_capacity}), status_code=200, mimetype="application/json")

        return func.HttpResponse(json.dumps({"message": f"Action {action} acknowledged"}), status_code=200, mimetype="application/json")

    except Exception as e:
        logging.error(f"Error handling webhook: {str(e)}", exc_info=True)
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")
