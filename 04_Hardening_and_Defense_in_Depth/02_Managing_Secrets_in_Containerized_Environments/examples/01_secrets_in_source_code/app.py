import requests

PAYMENT_API_KEY = "sk_live_FAKE_DO_NOT_USE_123456"

def charge():
    return requests.get(
        "https://payments.example/api",
        headers={"Authorization": f"Bearer {PAYMENT_API_KEY}"}
    )