WScript.Sleep 5000
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "A:\GA STOCK\backend"
WshShell.Run """A:\GA STOCK\backend\.venv\Scripts\uvicorn.exe"" app.main:app --host 0.0.0.0 --port 8000", 0, False
