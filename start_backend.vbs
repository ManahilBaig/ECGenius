CreateObject("Wscript.Shell").Run "python -m uvicorn app.main:app --host 0.0.0.0 --port 8001", 0, False
