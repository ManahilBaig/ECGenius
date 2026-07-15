$logFile = "$env:TEMP\ecg_backend.log"
$proc = Start-Process -NoNewWindow -FilePath "python" -ArgumentList "-m uvicorn app.main:app --host 0.0.0.0 --port 8001" -WorkingDirectory "F:\ECG App\New folder (2)\ECGenius\ECG FYP\ECG FYP\backend" -PassThru
$proc.Id | Out-File "$env:TEMP\ecg_backend.pid"
Write-Output "Backend started with PID $($proc.Id)"
