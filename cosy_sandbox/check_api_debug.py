import requests

url = "http://127.0.0.1:8000/generate"
data = {
    "text": "The weather is looking great today",
    "reference_voice": "savio_short.wav",
    "cross_lingual": "false"
}
response = requests.post(url, data=data)
print("Status Code:", response.status_code)
